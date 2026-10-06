#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Base = Join-Path $env:LOCALAPPDATA "SSDSystemGuard"
$ConfigPath = Join-Path $Base "config.json"
$StatePath = Join-Path $Base "state.json"
$LogPath = Join-Path $Base "guard.log"
$DetectionsPath = Join-Path $Base "detections.csv"
$PanelPath = Join-Path $Base "Panel.ps1"
$StopFlag = Join-Path $Base "stop.flag"
$TestRedFlag = Join-Path $Base "test_red.flag"
$TestYellowFlag = Join-Path $Base "test_yellow.flag"
$IconPath = Join-Path $Base "SSDSystemGuard.ico"
$script:AppIcon = $null

if (Test-Path $IconPath) {
    try {
        $script:AppIcon = New-Object System.Drawing.Icon($IconPath)
    } catch {}
}

New-Item -ItemType Directory -Path $Base -Force | Out-Null

# ---------------------------------------------------------------------
# SINGLE INSTANCE
# ---------------------------------------------------------------------
try {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value.Replace("-","_")
    $createdNew = $false
    $script:GuardMutex = [System.Threading.Mutex]::new(
        $true,
        "Local\SSDSystemGuard_$sid",
        [ref]$createdNew
    )
    if (-not $createdNew) { exit }
} catch {}

# ---------------------------------------------------------------------
# RUNTIME STATE
# ---------------------------------------------------------------------
$script:Watchers = @()
$script:PendingFiles = @{}
$script:RecentAlerts = @{}
$script:KnownProcessKeys = @{}
$script:SteamRetrySignals = @{}

$RiskExtensions = @(
    ".exe",".msi",".iso",".zip",".rar",".7z",".apk",".torrent",
    ".bat",".cmd",".ps1",".vbs"
)

$PartialExtensions = @(
    ".crdownload",".part",".download",".tmp"
)

$GameWords = @(
    "steam","epic","riot","valorant","league of legends","leagueoflegends",
    "battle.net","blizzard","roblox","minecraft","fortnite",
    "counter-strike","counter strike","cs2","gta","grand theft auto",
    "call of duty","warzone","apex legends","overwatch","diablo",
    "elden ring","resident evil","silent hill","alan wake","cyberpunk",
    "forza","red dead","god of war","the last of us","tomb raider",
    "fobia","game","games","launcher"
)

$StrongGameMarkers = @(
    "steam_api.dll","steam_api64.dll","steamclient64.dll",
    "unityplayer.dll","eossdk-win64-shipping.dll","eossdk-win32-shipping.dll",
    "galaxy64.dll","galaxy.dll"
)

$SafePublishers = @(
    "Microsoft Corporation","Microsoft Windows",
    "NVIDIA Corporation","Advanced Micro Devices, Inc.",
    "Intel Corporation","Google LLC","Mozilla Corporation",
    "VideoLAN","RARLAB","7-Zip"
)

# ---------------------------------------------------------------------
# CONFIG / STATE
# ---------------------------------------------------------------------
function Get-GuardConfig {
    try {
        return (Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Save-GuardConfig {
    param($Config)
    try {
        $Config | ConvertTo-Json -Depth 12 | Set-Content $ConfigPath -Encoding UTF8
    } catch {}
}

function Get-GuardState {
    try {
        return (Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{
            Initialized = $false
            SteamBaselineAppIds = @()
            EpicBaselineLocations = @()
            BlockedPaths = @()
            LastBaseline = $null
        }
    }
}

function Save-GuardState {
    param($State)
    try {
        $State | ConvertTo-Json -Depth 15 | Set-Content $StatePath -Encoding UTF8
    } catch {}
}

# ---------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------
function Write-GuardLog {
    param([string]$Message)
    try {
        Add-Content $LogPath (
            "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
        ) -Encoding UTF8
    } catch {}
}

function Add-Detection {
    param(
        [string]$Status,
        [string]$Category,
        [string]$Risk,
        [string]$Source,
        [string]$Name,
        [string]$Path,
        [string]$Reason,
        [string]$Action
    )

    try {
        [pscustomobject]@{
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Status = $Status
            Category = $Category
            Risk = $Risk
            Source = $Source
            Name = $Name
            Path = $Path
            Reason = $Reason
            Action = $Action
        } | Export-Csv $DetectionsPath -NoTypeInformation -Encoding UTF8 -Append
    } catch {}

    Write-GuardLog ("DETECTION | {0} | {1} | {2} | {3}" -f $Status,$Source,$Name,$Path)
}

# ---------------------------------------------------------------------
# SAFETY / CLASSIFICATION
# ---------------------------------------------------------------------
function Test-IsPaused {
    $cfg = Get-GuardConfig
    if (-not $cfg -or -not $cfg.Enabled) { return $true }

    if ($cfg.PauseUntil) {
        try {
            $until = [datetime]::Parse([string]$cfg.PauseUntil)
            if ((Get-Date) -lt $until) { return $true }

            $cfg.PauseUntil = $null
            Save-GuardConfig $cfg
        } catch {}
    }

    return $false
}

function Test-MonitoredDrive {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $cfg = Get-GuardConfig
    if (-not $cfg) { return $false }

    try {
        $prefix = $cfg.SystemDrive.TrimEnd("\") + "\"
        return $Path.StartsWith(
            $prefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    } catch {
        return $false
    }
}

function Test-OfficialWindowsPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    try {
        $win = $env:WINDIR.TrimEnd("\") + "\"
        return $Path.StartsWith(
            $win,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    } catch {
        return $false
    }
}

function Test-AllowedLauncher {
    param([string]$Name,[string]$Path)

    if (-not $Name -or -not $Path) { return $false }

    $n = $Name.ToLowerInvariant()
    $p = $Path.ToLowerInvariant()

    if ($n -eq "steam.exe" -and $p -match '\\steam\\steam\.exe$') { return $true }

    if ($n -eq "epicgameslauncher.exe" -and
        $p -match '\\epic games\\launcher\\portal\\binaries\\') { return $true }

    if ($n -eq "riotclientservices.exe" -and
        $p -match '\\riot games\\riot client\\') { return $true }

    if ($n -eq "battle.net.exe" -and $p -match '\\battle\.net\\') { return $true }

    if (($n -eq "eadesktop.exe" -or $n -eq "ealauncher.exe") -and
        ($p -match '\\electronic arts\\ea desktop\\' -or
         $p -match '\\ea desktop\\')) { return $true }

    if (($n -eq "ubisoftconnect.exe" -or $n -eq "upc.exe") -and
        $p -match '\\ubisoft game launcher\\') { return $true }

    if ($n -eq "galaxyclient.exe" -and $p -match '\\gog galaxy\\') { return $true }

    if ($n -eq "minecraftlauncher.exe" -and
        $p -match '\\minecraft launcher\\') { return $true }

    return $false
}

function Test-GameLike {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    $low = $Text.ToLowerInvariant()

    foreach ($word in $GameWords) {
        if ($low.Contains($word)) { return $true }
    }

    if ($low -like "*-win64-shipping.exe" -or
        $low -like "*-win32-shipping.exe") {
        return $true
    }

    return $false
}

function Test-StrongGameMarkers {
    param([string]$Path)

    if (-not $Path) { return $false }

    try {
        $dir = if (Test-Path $Path -PathType Container) {
            $Path
        } else {
            Split-Path -Parent $Path
        }

        if (-not $dir -or -not (Test-Path $dir)) { return $false }

        if ($dir -match '\\steamapps\\common\\' -or
            $dir -match '\\engine\\binaries\\') {
            return $true
        }

        foreach ($marker in $StrongGameMarkers) {
            if (Test-Path (Join-Path $dir $marker)) { return $true }
        }
    } catch {}

    return $false
}

function Get-Publisher {
    param([string]$Path)

    try {
        if (-not (Test-Path $Path -PathType Leaf)) { return "" }

        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction SilentlyContinue
        if ($sig -and $sig.SignerCertificate) {
            $subject = [string]$sig.SignerCertificate.Subject

            if ($subject -match 'CN=([^,]+)') {
                return $matches[1].Trim()
            }

            return $subject
        }
    } catch {}

    return ""
}

function Test-SafePublisher {
    param([string]$Publisher)

    if (-not $Publisher) { return $false }

    foreach ($safe in $SafePublishers) {
        if ($Publisher -like "*$safe*") { return $true }
    }

    return $false
}

function Should-Alert {
    param([string]$Key,[int]$CooldownSeconds = 120)

    $now = Get-Date

    if ($script:RecentAlerts.ContainsKey($Key)) {
        if (($now - $script:RecentAlerts[$Key]).TotalSeconds -lt $CooldownSeconds) {
            return $false
        }
    }

    $script:RecentAlerts[$Key] = $now
    return $true
}

# ---------------------------------------------------------------------
# UI ALERT
# ---------------------------------------------------------------------
function Show-GuardAlert {
    param(
        [string]$Status,
        [string]$Category,
        [string]$Risk,
        [string]$Source,
        [string]$Name,
        [string]$Path,
        [string]$Reason,
        [string]$Action,
        [Nullable[int]]$ProcessId = $null
    )

    if (Test-IsPaused) { return }

    $key = "$Status|$Source|$Name|$Path"
    if (-not (Should-Alert $key 120)) { return }

    try { [System.Media.SystemSounds]::Exclamation.Play() } catch {}

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "SSD System Guard"
    $form.Width = 900
    $form.Height = 570
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    if ($script:AppIcon) {
        $form.Icon = $script:AppIcon
    }

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = "Top"
    $header.Height = 110

    if ($Status -like "*BLOQUEADO*") {
        $header.BackColor = [System.Drawing.Color]::FromArgb(160,25,25)
    } elseif ($Status -like "*SUSPEITO*") {
        $header.BackColor = [System.Drawing.Color]::FromArgb(190,120,0)
    } else {
        $header.BackColor = [System.Drawing.Color]::FromArgb(30,115,60)
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = $Status
    $title.ForeColor = [System.Drawing.Color]::White
    $title.Font = New-Object System.Drawing.Font(
        "Segoe UI",22,[System.Drawing.FontStyle]::Bold
    )
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(26,18)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = "$Category   |   Risco: $Risk   |   Origem: $Source"
    $subtitle.ForeColor = [System.Drawing.Color]::White
    $subtitle.Font = New-Object System.Drawing.Font("Segoe UI",10)
    $subtitle.AutoSize = $true
    $subtitle.Location = New-Object System.Drawing.Point(29,68)

    $header.Controls.Add($title)
    $header.Controls.Add($subtitle)

    $itemLabel = New-Object System.Windows.Forms.Label
    $itemLabel.Text = "Item detectado:"
    $itemLabel.Font = New-Object System.Drawing.Font(
        "Segoe UI",10,[System.Drawing.FontStyle]::Bold
    )
    $itemLabel.AutoSize = $true
    $itemLabel.Location = New-Object System.Drawing.Point(28,135)

    $itemBox = New-Object System.Windows.Forms.TextBox
    $itemBox.Text = $Name
    $itemBox.ReadOnly = $true
    $itemBox.Width = 820
    $itemBox.Location = New-Object System.Drawing.Point(30,160)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = "Caminho:"
    $pathLabel.Font = New-Object System.Drawing.Font(
        "Segoe UI",10,[System.Drawing.FontStyle]::Bold
    )
    $pathLabel.AutoSize = $true
    $pathLabel.Location = New-Object System.Drawing.Point(28,200)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Text = $Path
    $pathBox.ReadOnly = $true
    $pathBox.Width = 820
    $pathBox.Location = New-Object System.Drawing.Point(30,225)

    $reasonLabel = New-Object System.Windows.Forms.Label
    $reasonLabel.Text = "Motivo:"
    $reasonLabel.Font = New-Object System.Drawing.Font(
        "Segoe UI",10,[System.Drawing.FontStyle]::Bold
    )
    $reasonLabel.AutoSize = $true
    $reasonLabel.Location = New-Object System.Drawing.Point(28,265)

    $reasonBox = New-Object System.Windows.Forms.TextBox
    $reasonBox.Text = $Reason
    $reasonBox.Multiline = $true
    $reasonBox.ReadOnly = $true
    $reasonBox.ScrollBars = "Vertical"
    $reasonBox.Width = 820
    $reasonBox.Height = 70
    $reasonBox.Location = New-Object System.Drawing.Point(30,290)

    $actionLabel = New-Object System.Windows.Forms.Label
    $actionLabel.Text = "Ação executada / recomendada:"
    $actionLabel.Font = New-Object System.Drawing.Font(
        "Segoe UI",10,[System.Drawing.FontStyle]::Bold
    )
    $actionLabel.AutoSize = $true
    $actionLabel.Location = New-Object System.Drawing.Point(28,375)

    $actionBox = New-Object System.Windows.Forms.TextBox
    $actionBox.Text = $Action
    $actionBox.Multiline = $true
    $actionBox.ReadOnly = $true
    $actionBox.Width = 820
    $actionBox.Height = 55
    $actionBox.Location = New-Object System.Drawing.Point(30,400)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "ENTENDI"
    $ok.Width = 150
    $ok.Height = 42
    $ok.Location = New-Object System.Drawing.Point(30,470)
    $ok.Add_Click({ $form.Close() })

    $open = New-Object System.Windows.Forms.Button
    $open.Text = "Abrir local"
    $open.Width = 150
    $open.Height = 42
    $open.Location = New-Object System.Drawing.Point(195,470)
    $open.Add_Click({
        try {
            if (Test-Path $Path -PathType Leaf) {
                Start-Process explorer.exe -ArgumentList "/select,`"$Path`""
            } elseif (Test-Path $Path -PathType Container) {
                Start-Process explorer.exe $Path
            }
        } catch {}
    })

    $kill = New-Object System.Windows.Forms.Button
    $kill.Text = "Finalizar processo"
    $kill.Width = 170
    $kill.Height = 42
    $kill.Location = New-Object System.Drawing.Point(360,470)
    $kill.Enabled = ($ProcessId -ne $null)
    $kill.Add_Click({
        if ($ProcessId -ne $null) {
            try { Stop-Process -Id ([int]$ProcessId) -Force } catch {}
            $form.Close()
        }
    })

    $panel = New-Object System.Windows.Forms.Button
    $panel.Text = "Abrir painel"
    $panel.Width = 150
    $panel.Height = 42
    $panel.Location = New-Object System.Drawing.Point(545,470)
    $panel.Add_Click({
        Start-Process powershell.exe -ArgumentList (
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PanelPath`""
        )
        $form.Close()
    })

    $form.Controls.AddRange(@(
        $header,$itemLabel,$itemBox,$pathLabel,$pathBox,
        $reasonLabel,$reasonBox,$actionLabel,$actionBox,
        $ok,$open,$kill,$panel
    ))

    [void]$form.ShowDialog()
    $form.Dispose()
}

# ---------------------------------------------------------------------
# DOWNLOAD PROTECTION
# ---------------------------------------------------------------------
function Get-UnderlyingExtension {
    param([string]$Path)

    $name = [IO.Path]::GetFileName($Path)
    $ext = [IO.Path]::GetExtension($name).ToLowerInvariant()

    if ($PartialExtensions -contains $ext) {
        $withoutPartial = [IO.Path]::GetFileNameWithoutExtension($name)
        return [IO.Path]::GetExtension($withoutPartial).ToLowerInvariant()
    }

    return $ext
}

function Test-ProtectedDownloadPath {
    param([string]$Path)

    $cfg = Get-GuardConfig
    if (-not $cfg) { return $false }

    foreach ($folder in @($cfg.ProtectedDownloadFolders)) {
        if ($folder -and $Path.StartsWith(
            $folder,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }
    }

    return $false
}

function Test-RiskyDownload {
    param([string]$Path)

    $ext = Get-UnderlyingExtension $Path

    if ($RiskExtensions -contains $ext) { return $true }
    if (Test-GameLike $Path) { return $true }

    return $false
}

function Add-PendingFile {
    param([string]$Path,[string]$Classification)

    if (-not $script:PendingFiles.ContainsKey($Path)) {
        $script:PendingFiles[$Path] = [pscustomobject]@{
            Classification = $Classification
            FirstSeen = Get-Date
            Attempts = 0
        }
    }
}

function Get-UniqueQuarantinePath {
    param([string]$SourcePath,[string]$QuarantineRoot)

    New-Item -ItemType Directory -Path $QuarantineRoot -Force | Out-Null

    $name = [IO.Path]::GetFileName($SourcePath)
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $candidate = Join-Path $QuarantineRoot ($stamp + "_" + $name)
    $i = 1

    while (Test-Path $candidate) {
        $candidate = Join-Path $QuarantineRoot (
            $stamp + "_" + $i + "_" + $name
        )
        $i++
    }

    return $candidate
}

function Invoke-FileBlock {
    param([string]$Path,[string]$Classification)

    $cfg = Get-GuardConfig
    if (-not $cfg -or -not $cfg.Enabled -or -not $cfg.DownloadProtection) {
        return $true
    }

    if (-not (Test-Path $Path -PathType Leaf)) { return $true }

    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()

    if ($PartialExtensions -contains $ext) {
        try {
            Remove-Item $Path -Force -ErrorAction Stop

            $action = "Transferência parcial removida do SSD C:. O navegador deve indicar falha/cancelamento."

            Add-Detection "BLOQUEADO" "Download no C:" "ALTO" `
                "Navegador / download" ([IO.Path]::GetFileName($Path)) `
                $Path "Arquivo parcial de download de risco detectado no C:." $action

            Show-GuardAlert "BLOQUEADO" "Download no C:" "ALTO" `
                "Navegador / download" ([IO.Path]::GetFileName($Path)) `
                $Path "Arquivo parcial de download de risco detectado no C:." $action

            return $true
        } catch {
            return $false
        }
    }

    $quarantine = [string]$cfg.QuarantinePath

    if ($quarantine -and
        -not $quarantine.StartsWith(
            $cfg.SystemDrive,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        try {
            $dest = Get-UniqueQuarantinePath $Path $quarantine
            Move-Item $Path $dest -Force -ErrorAction Stop

            $action = "Arquivo removido do C: e movido para quarentena: $dest"

            Add-Detection "BLOQUEADO" $Classification "ALTO" `
                "Download" ([IO.Path]::GetFileName($Path)) `
                $Path "Arquivo de risco tentou permanecer na pasta Downloads do C:." $action

            Show-GuardAlert "BLOQUEADO" $Classification "ALTO" `
                "Download" ([IO.Path]::GetFileName($Path)) `
                $Path "Arquivo de risco tentou permanecer na pasta Downloads do C:." $action

            return $true
        } catch {
            return $false
        }
    }

    try {
        Remove-Item $Path -Force -ErrorAction Stop

        $action = "Arquivo removido do SSD C:. Não havia quarentena válida em outro disco."

        Add-Detection "BLOQUEADO" $Classification "ALTO" `
            "Download" ([IO.Path]::GetFileName($Path)) `
            $Path "Arquivo de risco tentou permanecer na pasta Downloads do C:." $action

        Show-GuardAlert "BLOQUEADO" $Classification "ALTO" `
            "Download" ([IO.Path]::GetFileName($Path)) `
            $Path "Arquivo de risco tentou permanecer na pasta Downloads do C:." $action

        return $true
    } catch {
        return $false
    }
}

function Handle-DownloadEvent {
    param([string]$Path)

    if (Test-IsPaused) { return }

    $cfg = Get-GuardConfig
    if (-not $cfg -or -not $cfg.DownloadProtection) { return }

    if (-not (Test-ProtectedDownloadPath $Path)) { return }
    if (-not (Test-RiskyDownload $Path)) { return }

    $classification = if (Test-GameLike $Path) {
        "Jogo / launcher / arquivo de game"
    } else {
        "Aplicativo / pacote não autorizado"
    }

    Start-Sleep -Milliseconds 80

    if (-not (Invoke-FileBlock $Path $classification)) {
        Add-PendingFile $Path $classification
    }
}

function Retry-PendingFiles {
    foreach ($path in @($script:PendingFiles.Keys)) {
        $entry = $script:PendingFiles[$path]

        if (-not (Test-Path $path)) {
            $script:PendingFiles.Remove($path)
            continue
        }

        $entry.Attempts++

        if (Invoke-FileBlock $path $entry.Classification) {
            $script:PendingFiles.Remove($path)
            continue
        }

        if ($entry.Attempts -ge 30) {
            Write-GuardLog ("PENDING TIMEOUT | " + $path)
            $script:PendingFiles.Remove($path)
        }
    }
}

function Setup-DownloadWatchers {
    $cfg = Get-GuardConfig
    $i = 0

    foreach ($folder in @($cfg.ProtectedDownloadFolders)) {
        if (-not $folder -or -not (Test-Path $folder)) { continue }

        try {
            $watcher = New-Object System.IO.FileSystemWatcher
            $watcher.Path = $folder
            $watcher.Filter = "*.*"
            $watcher.IncludeSubdirectories = $true
            $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, CreationTime, Size'
            $watcher.EnableRaisingEvents = $true

            Register-ObjectEvent $watcher Created `
                -SourceIdentifier ("SSDGD_CREATED_" + $i) | Out-Null

            Register-ObjectEvent $watcher Renamed `
                -SourceIdentifier ("SSDGD_RENAMED_" + $i) | Out-Null

            $script:Watchers += $watcher
            $i++
        } catch {
            Write-GuardLog ("WATCHER ERROR | " + $folder)
        }
    }
}

function Drain-DownloadEvents {
    $events = @(Get-Event | Where-Object {
        $_.SourceIdentifier -like "SSDGD_*"
    })

    foreach ($event in $events) {
        try {
            $path = [string]$event.SourceEventArgs.FullPath
            if ($path) { Handle-DownloadEvent $path }
        } catch {}

        try {
            Remove-Event -EventIdentifier $event.EventIdentifier
        } catch {}
    }
}

# ---------------------------------------------------------------------
# STEAM / EPIC BASELINES
# ---------------------------------------------------------------------
function Get-SteamLibrariesOnC {
    $libs = @()
    $steam = ""

    try {
        $steam = [string](
            Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        ).SteamPath
    } catch {}

    if (-not $steam) {
        try {
            $steam = [string](
                Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" `
                    -ErrorAction SilentlyContinue
            ).InstallPath
        } catch {}
    }

    if (-not $steam -or -not (Test-Path $steam)) { return @() }

    $libs += $steam

    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"

    if (Test-Path $vdf) {
        try {
            $txt = Get-Content $vdf -Raw -Encoding UTF8

            foreach ($match in [regex]::Matches(
                $txt,
                '"path"\s+"([^"]+)"'
            )) {
                $p = $match.Groups[1].Value.Replace("\\","\")

                if ($p -and $libs -notcontains $p) {
                    $libs += $p
                }
            }
        } catch {}
    }

    return @($libs | Where-Object {
        $_.StartsWith("C:\",[System.StringComparison]::OrdinalIgnoreCase)
    })
}

function Get-SteamInstalledAppIds {
    $ids = @()

    foreach ($lib in @(Get-SteamLibrariesOnC)) {
        $steamapps = Join-Path $lib "steamapps"

        if (-not (Test-Path $steamapps)) { continue }

        Get-ChildItem $steamapps -Filter "appmanifest_*.acf" `
            -File -ErrorAction SilentlyContinue | ForEach-Object {

            if ($_.BaseName -match '^appmanifest_(\d+)$') {
                $ids += $matches[1]
            }
        }
    }

    return @($ids | Sort-Object -Unique)
}

function Get-EpicInstalledLocationsOnC {
    $locations = @()
    $manifestRoot = Join-Path $env:ProgramData `
        "Epic\EpicGamesLauncher\Data\Manifests"

    if (Test-Path $manifestRoot) {
        Get-ChildItem $manifestRoot -Filter "*.item" `
            -File -ErrorAction SilentlyContinue | ForEach-Object {

            try {
                $item = Get-Content $_.FullName -Raw -Encoding UTF8 |
                    ConvertFrom-Json

                $loc = [string]$item.InstallLocation

                if ($loc -and
                    $loc.StartsWith(
                        "C:\",
                        [System.StringComparison]::OrdinalIgnoreCase
                    )) {
                    $locations += $loc.TrimEnd("\")
                }
            } catch {}
        }
    }

    return @($locations | Sort-Object -Unique)
}

function Initialize-Baseline {
    $state = Get-GuardState

    if ($state.Initialized) { return }

    $state.SteamBaselineAppIds = @(Get-SteamInstalledAppIds)
    $state.EpicBaselineLocations = @(Get-EpicInstalledLocationsOnC)
    $state.BlockedPaths = @()
    $state.Initialized = $true
    $state.LastBaseline = (Get-Date).ToString("o")

    Save-GuardState $state

    Write-GuardLog (
        "BASELINE CREATED | Steam={0} | Epic={1}" -f
        @($state.SteamBaselineAppIds).Count,
        @($state.EpicBaselineLocations).Count
    )
}

# ---------------------------------------------------------------------
# GUARDED ACL RULES
# ---------------------------------------------------------------------
function Test-GuardDenyRulePresent {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) {
        return $false
    }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = Get-Acl $Path

        foreach ($rule in @($acl.Access)) {
            if (
                $rule.IdentityReference.Value -eq $identity -and
                $rule.AccessControlType -eq
                    [System.Security.AccessControl.AccessControlType]::Deny
            ) {
                $rights = [System.Security.AccessControl.FileSystemRights]$rule.FileSystemRights

                if (
                    ($rights -band [System.Security.AccessControl.FileSystemRights]::Write) -or
                    ($rights -band [System.Security.AccessControl.FileSystemRights]::Delete) -or
                    ($rights -band [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles)
                ) {
                    return $true
                }
            }
        }
    } catch {}

    return $false
}

function Test-GuardPathAlreadyBlocked {
    param([string]$Path)

    if (-not $Path) {
        return $false
    }

    $state = Get-GuardState
    $normalized = $Path.TrimEnd("\")

    $match = @(
        $state.BlockedPaths |
        Where-Object {
            $_.Path -and
            ([string]$_.Path).TrimEnd("\").Equals(
                $normalized,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    ) | Select-Object -First 1

    if (-not $match) {
        return $false
    }

    # Só considera "já bloqueado" se a regra de negação realmente continua
    # presente. Se o usuário removeu a ACL ou a pasta foi recriada, elimina
    # a entrada velha do state para permitir um novo bloqueio real.
    if (Test-GuardDenyRulePresent $Path) {
        return $true
    }

    $remaining = @(
        $state.BlockedPaths |
        Where-Object {
            -not (
                $_.Path -and
                ([string]$_.Path).TrimEnd("\").Equals(
                    $normalized,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            )
        }
    )

    $state.BlockedPaths = $remaining
    Save-GuardState $state

    Write-GuardLog ("STALE BLOCK STATE REMOVED | $Path")

    return $false
}

function Add-GuardBlockedPath {
    param([string]$Path,[string]$Type)

    $state = Get-GuardState
    $blocked = @($state.BlockedPaths)

    if (@($blocked | Where-Object { $_.Path -eq $Path }).Count -eq 0) {
        $blocked += [pscustomobject]@{
            Path = $Path
            Type = $Type
            Added = (Get-Date).ToString("o")
        }

        $state.BlockedPaths = $blocked
        Save-GuardState $state
    }
}

function Add-GuardWriteDeny {
    param([string]$Path,[string]$Type)

    try {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }

        # Remove apenas conteúdo parcial da pasta nova.
        Get-ChildItem $Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = Get-Acl $Path

        $rights = [System.Security.AccessControl.FileSystemRights]::Write `
            -bor [System.Security.AccessControl.FileSystemRights]::Delete `
            -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles

        $inherit = [System.Security.AccessControl.InheritanceFlags](
            "ContainerInherit, ObjectInherit"
        )

        $propagation = [System.Security.AccessControl.PropagationFlags]::None
        $deny = [System.Security.AccessControl.AccessControlType]::Deny

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity,
            $rights,
            $inherit,
            $propagation,
            $deny
        )

        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl

        Add-GuardBlockedPath $Path $Type
        Write-GuardLog ("ACL BLOCK | $Type | $Path")

        return $true
    } catch {
        Write-GuardLog ("ACL BLOCK FAILED | $Type | $Path | " + $_.Exception.Message)
        return $false
    }
}

function Remove-GuardDenyRules {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = Get-Acl $Path
        $changed = $false

        foreach ($rule in @($acl.Access)) {
            if ($rule.IdentityReference.Value -eq $identity -and
                $rule.AccessControlType -eq
                    [System.Security.AccessControl.AccessControlType]::Deny) {

                [void]$acl.RemoveAccessRuleSpecific($rule)
                $changed = $true
            }
        }

        if ($changed) {
            Set-Acl -Path $Path -AclObject $acl
        }
    } catch {
        Write-GuardLog ("ACL UNBLOCK FAILED | $Path | " + $_.Exception.Message)
    }
}

function Remove-AllGuardACLs {
    $state = Get-GuardState

    foreach ($item in @($state.BlockedPaths)) {
        Remove-GuardDenyRules ([string]$item.Path)
    }

    $state.BlockedPaths = @()
    Save-GuardState $state
}

function Get-SteamInstallPath {
    $steam = ""

    try {
        $steam = [string](
            Get-ItemProperty "HKCU:\Software\Valve\Steam" `
                -ErrorAction SilentlyContinue
        ).SteamPath
    } catch {}

    if (-not $steam) {
        try {
            $steam = [string](
                Get-ItemProperty `
                    "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" `
                    -ErrorAction SilentlyContinue
            ).InstallPath
        } catch {}
    }

    if ($steam -and (Test-Path $steam)) {
        return $steam
    }

    return $null
}

function Get-SteamRetrySignal {
    param([string]$AppId)

    if (-not $AppId) {
        return $null
    }

    $steam = Get-SteamInstallPath

    if (-not $steam) {
        return $null
    }

    $contentLog = Join-Path $steam "logs\content_log.txt"

    if (-not (Test-Path $contentLog)) {
        return $null
    }

    try {
        $item = Get-Item $contentLog -ErrorAction Stop

        # Só considera atividade bem recente. Isso impede um erro antigo do log
        # de virar um popup novo apenas porque o Guard foi reiniciado.
        $ageSeconds = (
            (Get-Date).ToUniversalTime() -
            $item.LastWriteTimeUtc
        ).TotalSeconds

        if ($ageSeconds -gt 12) {
            return $null
        }

        # A tentativa atual costuma ficar nas últimas linhas do content_log.
        # Procuramos especificamente o AppID e um resultado ligado a falha/
        # escrita/remoção do agendamento.
        $tail = @(
            Get-Content $contentLog `
                -Tail 30 `
                -ErrorAction SilentlyContinue
        )

        if ($tail.Count -eq 0) {
            return $null
        }

        $pattern = (
            "(?i)AppID\s+" +
            [regex]::Escape($AppId) +
            "\b.*(disk write|write failure|failed|failure|removed from schedule)"
        )

        $matchLine = $tail |
            Where-Object { $_ -match $pattern } |
            Select-Object -Last 1

        if (-not $matchLine) {
            return $null
        }

        # O LastWriteTime entra no sinal para diferenciar duas tentativas reais
        # mesmo quando o texto emitido pela Steam for idêntico.
        return (
            $item.LastWriteTimeUtc.Ticks.ToString() +
            "|" +
            [string]$matchLine
        )
    } catch {}

    return $null
}

function Show-SteamRetryBlockedAlert {
    param(
        [string]$AppId,
        [string]$Path
    )

    $signal = Get-SteamRetrySignal $AppId

    if (-not $signal) {
        return
    }

    if (
        $script:SteamRetrySignals.ContainsKey($AppId) -and
        $script:SteamRetrySignals[$AppId] -eq $signal
    ) {
        return
    }

    $script:SteamRetrySignals[$AppId] = $signal

    $action = (
        "O download continua bloqueado no SSD C:. " +
        "A Steam permanece aberta. Escolha uma biblioteca em outro SSD/HD."
    )

    Add-Detection `
        "BLOQUEADO" `
        "Tentativa de retomar jogo Steam no C:" `
        "ALTO" `
        "Steam" `
        ("AppID " + $AppId) `
        $Path `
        "A Steam tentou novamente gravar no caminho que já está protegido." `
        $action

    Show-GuardAlert `
        "BLOQUEADO" `
        "Tentativa de retomar jogo Steam no C:" `
        "ALTO" `
        "Steam" `
        ("AppID " + $AppId) `
        $Path `
        "A Steam tentou novamente gravar no caminho que já está protegido." `
        $action
}

# ---------------------------------------------------------------------
# STEAM PROTECTION
# ---------------------------------------------------------------------
function Check-SteamDownloads {
    if (Test-IsPaused) { return }

    $cfg = Get-GuardConfig
    if (-not $cfg -or -not $cfg.SteamProtection) { return }

    $state = Get-GuardState
    $baseline = @{}

    foreach ($id in @($state.SteamBaselineAppIds)) {
        if ($id) { $baseline[[string]$id] = $true }
    }

    foreach ($lib in @(Get-SteamLibrariesOnC)) {
        $downloadRoot = Join-Path $lib "steamapps\downloading"

        if (-not (Test-Path $downloadRoot)) { continue }

        Get-ChildItem $downloadRoot -Directory `
            -ErrorAction SilentlyContinue | ForEach-Object {

            $appid = $_.Name

            if ($appid -notmatch '^\d+$') { return }
            if ($baseline.ContainsKey($appid)) { return }

            $targetPath = $_.FullName

            # Se a pasta já continua realmente bloqueada, não reaplica ACL
            # nem gera spam por varredura. Porém, se a Steam registrar uma
            # NOVA tentativa real de "Retomar", mostramos um único alerta
            # para aquela tentativa.
            if (Test-GuardPathAlreadyBlocked $targetPath) {
                Show-SteamRetryBlockedAlert $appid $targetPath
                return
            }

            if (Add-GuardWriteDeny $targetPath "Steam") {
                $action = (
                    "A pasta de download da Steam foi esvaziada e bloqueada para escrita. " +
                    "A Steam permanece aberta. Escolha uma biblioteca em outro SSD/HD."
                )

                Add-Detection "BLOQUEADO" "Novo jogo Steam no C:" "ALTO" `
                    "Steam" ("AppID " + $appid) $targetPath `
                    "Novo AppID tentou iniciar download em biblioteca do SSD C:." $action

                Show-GuardAlert "BLOQUEADO" "Novo jogo Steam no C:" "ALTO" `
                    "Steam" ("AppID " + $appid) $targetPath `
                    "Novo AppID tentou iniciar download em biblioteca do SSD C:." $action
            }
        }
    }
}

# ---------------------------------------------------------------------
# EPIC PROTECTION
# ---------------------------------------------------------------------
function Check-EpicDownloads {
    if (Test-IsPaused) { return }

    $cfg = Get-GuardConfig
    if (-not $cfg -or -not $cfg.EpicProtection) { return }

    $state = Get-GuardState
    $baseline = @(
        $state.EpicBaselineLocations |
        ForEach-Object { ([string]$_).TrimEnd("\").ToLowerInvariant() }
    )

    $roots = @(
        "C:\Program Files\Epic Games",
        "C:\Epic Games",
        "C:\Games",
        (Join-Path $env:USERPROFILE "Games")
    ) | Select-Object -Unique

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }

        foreach ($folder in @(
            Get-ChildItem $root -Directory -ErrorAction SilentlyContinue
        )) {
            $egstore = Join-Path $folder.FullName ".egstore"

            if (-not (Test-Path $egstore)) { continue }

            $parent = $folder.FullName.TrimEnd("\")

            if ($baseline -contains $parent.ToLowerInvariant()) { continue }

            # Mesmo comportamento da Steam: um bloqueio persistente
            # gera apenas um alerta, sem reaparecer a cada ciclo de varredura.
            if (Test-GuardPathAlreadyBlocked $parent) {
                continue
            }

            if (Add-GuardWriteDeny $parent "Epic") {
                $action = (
                    "A pasta da nova instalação Epic foi bloqueada para escrita. " +
                    "A Epic Games permanece aberta. Escolha outro SSD/HD."
                )

                Add-Detection "BLOQUEADO" "Novo jogo Epic no C:" "ALTO" `
                    "Epic Games" $folder.Name $parent `
                    "Nova estrutura .egstore detectada em instalação não pertencente à base inicial." `
                    $action

                Show-GuardAlert "BLOQUEADO" "Novo jogo Epic no C:" "ALTO" `
                    "Epic Games" $folder.Name $parent `
                    "Nova estrutura .egstore detectada em instalação não pertencente à base inicial." `
                    $action
            }
        }
    }
}

# ---------------------------------------------------------------------
# PORTABLE / UNKNOWN PROCESS PROTECTION
# ---------------------------------------------------------------------
function Test-PathInsideBaselineGames {
    param([string]$Path)

    $state = Get-GuardState

    foreach ($loc in @($state.EpicBaselineLocations)) {
        if ($loc -and $Path.StartsWith(
            [string]$loc,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }
    }

    foreach ($lib in @(Get-SteamLibrariesOnC)) {
        $common = Join-Path $lib "steamapps\common"

        if ($Path.StartsWith(
            $common,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }
    }

    return $false
}

function Invoke-ProcessScan {
    if (Test-IsPaused) { return }

    $cfg = Get-GuardConfig
    if (-not $cfg -or -not $cfg.PortableGameProtection) { return }

    $processes = Get-CimInstance Win32_Process `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath }

    foreach ($process in $processes) {
        $path = [string]$process.ExecutablePath

        if (-not (Test-MonitoredDrive $path)) { continue }
        if (Test-OfficialWindowsPath $path) { continue }

        $name = [string]$process.Name

        if (Test-AllowedLauncher $name $path) { continue }
        if (Test-PathInsideBaselineGames $path) { continue }

        $key = "{0}|{1}" -f $process.ProcessId,[string]$process.CreationDate

        if ($script:KnownProcessKeys.ContainsKey($key)) { continue }
        $script:KnownProcessKeys[$key] = $true

        $isProtectedLocation = $false

        foreach ($folder in @($cfg.ProtectedDownloadFolders)) {
            if ($folder -and $path.StartsWith(
                $folder,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                $isProtectedLocation = $true
                break
            }
        }

        if ($isProtectedLocation -and
            ((Test-GameLike ($name + " " + $path)) -or
             (Test-StrongGameMarkers $path))) {

            try {
                Stop-Process -Id ([int]$process.ProcessId) -Force
            } catch {}

            $action = "Processo encerrado porque foi iniciado a partir de uma pasta protegida do C:."

            Add-Detection "BLOQUEADO" "Jogo portátil / executável de game" "ALTO" `
                "Processo" $name $path `
                "Executável com padrão de jogo iniciado diretamente de uma área protegida de download." `
                $action

            Show-GuardAlert "BLOQUEADO" "Jogo portátil / executável de game" "ALTO" `
                "Processo" $name $path `
                "Executável com padrão de jogo iniciado diretamente de uma área protegida de download." `
                $action ([int]$process.ProcessId)

            continue
        }

        if ($isProtectedLocation -and $cfg.UnknownAppAlerts) {
            $publisher = Get-Publisher $path

            if (-not (Test-SafePublisher $publisher)) {
                $action = "Executável desconhecido detectado. Valide a assinatura/editor antes de permitir."

                Add-Detection "SUSPEITO / REQUER VALIDACAO" `
                    "Aplicativo desconhecido" "MEDIO" "Processo" `
                    $name $path `
                    ("Executável iniciado de Downloads. Editor: " +
                     $(if($publisher){$publisher}else{"não verificado"})) `
                    $action

                Show-GuardAlert "SUSPEITO / REQUER VALIDACAO" `
                    "Aplicativo desconhecido" "MEDIO" "Processo" `
                    $name $path `
                    ("Executável iniciado de Downloads. Editor: " +
                     $(if($publisher){$publisher}else{"não verificado"})) `
                    $action ([int]$process.ProcessId)
            }
        }
    }

    if ($script:KnownProcessKeys.Count -gt 1500) {
        $current = @{}

        foreach ($process in $processes) {
            $current[
                "{0}|{1}" -f $process.ProcessId,[string]$process.CreationDate
            ] = $true
        }

        $script:KnownProcessKeys = $current
    }
}

# ---------------------------------------------------------------------
# INITIALIZATION
# ---------------------------------------------------------------------
try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath } |
        ForEach-Object {
            $script:KnownProcessKeys[
                "{0}|{1}" -f $_.ProcessId,[string]$_.CreationDate
            ] = $true
        }
} catch {}

Initialize-Baseline
Setup-DownloadWatchers

# ---------------------------------------------------------------------
# SINGLE TRAY ICON
# ---------------------------------------------------------------------
$notify = New-Object System.Windows.Forms.NotifyIcon
if ($script:AppIcon) {
    $notify.Icon = $script:AppIcon
} else {
    $notify.Icon = [System.Drawing.SystemIcons]::Shield
}
$notify.Text = "SSD System Guard"
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$itemPanel = $menu.Items.Add("Abrir painel")
$itemPanel.Add_Click({
    Start-Process powershell.exe -ArgumentList (
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PanelPath`""
    )
})

$itemPause = $menu.Items.Add("Pausar por 1 hora")
$itemPause.Add_Click({
    $cfg = Get-GuardConfig

    if ($cfg) {
        $cfg.Enabled = $true
        $cfg.PauseUntil = (Get-Date).AddHours(1).ToString("o")
        Save-GuardConfig $cfg
    }
})

$itemResume = $menu.Items.Add("Ativar / Retomar")
$itemResume.Add_Click({
    $cfg = Get-GuardConfig

    if ($cfg) {
        $cfg.Enabled = $true
        $cfg.PauseUntil = $null
        Save-GuardConfig $cfg
    }
})

[void]$menu.Items.Add("-")

$itemExit = $menu.Items.Add("Encerrar até o próximo login")
$itemExit.Add_Click({
    [System.Windows.Forms.Application]::Exit()
})

$notify.ContextMenuStrip = $menu

$notify.Add_DoubleClick({
    Start-Process powershell.exe -ArgumentList (
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PanelPath`""
    )
})

# ---------------------------------------------------------------------
# TIMERS
# ---------------------------------------------------------------------
$fastTimer = New-Object System.Windows.Forms.Timer
$fastTimer.Interval = 1000
$fastTimer.Add_Tick({
    Drain-DownloadEvents
    Retry-PendingFiles

    if (Test-Path $StopFlag) {
        Remove-Item $StopFlag -Force
        [System.Windows.Forms.Application]::Exit()
        return
    }

    if (Test-Path $TestRedFlag) {
        Remove-Item $TestRedFlag -Force

        Show-GuardAlert "BLOQUEADO" "TESTE - jogo/download" "ALTO" `
            "Teste interno" "Steam_Game_Test.exe" `
            "C:\Users\Teste\Downloads\Steam_Game_Test.exe" `
            "Alerta vermelho de teste do SSD System Guard." `
            "Nenhum arquivo real foi alterado."
    }

    if (Test-Path $TestYellowFlag) {
        Remove-Item $TestYellowFlag -Force

        Show-GuardAlert "SUSPEITO / REQUER VALIDACAO" `
            "TESTE - aplicativo desconhecido" "MEDIO" `
            "Teste interno" "Programa_Desconhecido.exe" `
            "C:\Users\Teste\Downloads\Programa_Desconhecido.exe" `
            "Alerta amarelo de teste do SSD System Guard." `
            "Nenhum arquivo real foi alterado."
    }
})
$fastTimer.Start()

$gameTimer = New-Object System.Windows.Forms.Timer
$gameTimer.Interval = 2000
$gameTimer.Add_Tick({
    Check-SteamDownloads
    Check-EpicDownloads
})
$gameTimer.Start()

$processTimer = New-Object System.Windows.Forms.Timer
$processTimer.Interval = 4000
$processTimer.Add_Tick({
    Invoke-ProcessScan
})
$processTimer.Start()

Write-GuardLog "SSD System Guard iniciado."

try {
    [System.Windows.Forms.Application]::Run()
} finally {
    try { $fastTimer.Stop(); $fastTimer.Dispose() } catch {}
    try { $gameTimer.Stop(); $gameTimer.Dispose() } catch {}
    try { $processTimer.Stop(); $processTimer.Dispose() } catch {}

    try {
        Get-EventSubscriber |
            Where-Object { $_.SourceIdentifier -like "SSDGD_*" } |
            Unregister-Event -Force
    } catch {}

    foreach ($watcher in $script:Watchers) {
        try {
            $watcher.EnableRaisingEvents = $false
            $watcher.Dispose()
        } catch {}
    }

    try {
        $notify.Visible = $false
        $notify.Dispose()
    } catch {}

    try {
        if ($script:AppIcon) {
            $script:AppIcon.Dispose()
        }
    } catch {}

    try {
        $script:GuardMutex.ReleaseMutex()
        $script:GuardMutex.Dispose()
    } catch {}

    Write-GuardLog "SSD System Guard encerrado."
}
