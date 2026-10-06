#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Base = Join-Path $env:LOCALAPPDATA "SSDSystemGuard"
$ConfigPath = Join-Path $Base "config.json"
$StatePath = Join-Path $Base "state.json"
$LogPath = Join-Path $Base "guard.log"
$DetectionsPath = Join-Path $Base "detections.csv"
$CorePath = Join-Path $Base "GuardCore.ps1"
$StopFlag = Join-Path $Base "stop.flag"
$TestRedFlag = Join-Path $Base "test_red.flag"
$TestYellowFlag = Join-Path $Base "test_yellow.flag"
$TaskName = "SSD System Guard"
$IconPath = Join-Path $Base "SSDSystemGuard.ico"
$script:AppIcon = $null

if (Test-Path $IconPath) {
    try {
        $script:AppIcon = New-Object System.Drawing.Icon($IconPath)
    } catch {}
}

function Get-Cfg {
    try {
        return (Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Save-Cfg {
    param($cfg)
    try {
        $cfg | ConvertTo-Json -Depth 12 | Set-Content $ConfigPath -Encoding UTF8
    } catch {}
}

function Get-State {
    try {
        return (Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Save-State {
    param($state)
    try {
        $state | ConvertTo-Json -Depth 15 | Set-Content $StatePath -Encoding UTF8
    } catch {}
}

function Ensure-CoreRunning {
    $running = $false

    try {
        $running = @(
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object {
                $_.CommandLine -like "*SSDSystemGuard*GuardCore.ps1*"
            }
        ).Count -gt 0
    } catch {}

    if (-not $running -and (Test-Path $CorePath)) {
        Start-Process powershell.exe -ArgumentList (
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$CorePath`""
        ) -WindowStyle Hidden
    }
}

function Remove-GuardACL {
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
    } catch {}
}

function Unblock-All {
    $state = Get-State
    if (-not $state) { return }

    foreach ($item in @($state.BlockedPaths)) {
        Remove-GuardACL ([string]$item.Path)
    }

    $state.BlockedPaths = @()
    Save-State $state
}

function Get-Counts {
    $red = 0
    $yellow = 0

    if (Test-Path $DetectionsPath) {
        try {
            $rows = @(Import-Csv $DetectionsPath)

            $red = @(
                $rows | Where-Object { $_.Status -like "*BLOQUEADO*" }
            ).Count

            $yellow = @(
                $rows | Where-Object { $_.Status -like "*SUSPEITO*" }
            ).Count
        } catch {}
    }

    return @($red,$yellow)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "SSD System Guard"
$form.Width = 810
$form.Height = 720
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

if ($script:AppIcon) {
    $form.Icon = $script:AppIcon
}

$title = New-Object System.Windows.Forms.Label
$title.Text = "SSD SYSTEM GUARD"
$title.Font = New-Object System.Drawing.Font(
    "Segoe UI",23,[System.Drawing.FontStyle]::Bold
)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(28,20)

$desc = New-Object System.Windows.Forms.Label
$desc.Text = "Uma única proteção para downloads, Steam/Epic e executáveis portáteis no SSD C:."
$desc.Font = New-Object System.Drawing.Font("Segoe UI",10)
$desc.AutoSize = $true
$desc.Location = New-Object System.Drawing.Point(31,68)

$status = New-Object System.Windows.Forms.Label
$status.Font = New-Object System.Drawing.Font(
    "Segoe UI",12,[System.Drawing.FontStyle]::Bold
)
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(31,110)

$summary = New-Object System.Windows.Forms.Label
$summary.Font = New-Object System.Drawing.Font("Segoe UI",10)
$summary.AutoSize = $true
$summary.Location = New-Object System.Drawing.Point(31,145)

$checks = New-Object System.Windows.Forms.GroupBox
$checks.Text = "Proteções"
$checks.Width = 735
$checks.Height = 165
$checks.Location = New-Object System.Drawing.Point(30,185)

$cbDownloads = New-Object System.Windows.Forms.CheckBox
$cbDownloads.Text = "Bloquear downloads de risco no C:"
$cbDownloads.AutoSize = $true
$cbDownloads.Location = New-Object System.Drawing.Point(20,32)

$cbSteam = New-Object System.Windows.Forms.CheckBox
$cbSteam.Text = "Bloquear NOVOS jogos Steam baixados no C:"
$cbSteam.AutoSize = $true
$cbSteam.Location = New-Object System.Drawing.Point(20,67)

$cbEpic = New-Object System.Windows.Forms.CheckBox
$cbEpic.Text = "Bloquear NOVOS jogos Epic instalados no C:"
$cbEpic.AutoSize = $true
$cbEpic.Location = New-Object System.Drawing.Point(20,102)

$cbPortable = New-Object System.Windows.Forms.CheckBox
$cbPortable.Text = "Bloquear jogo portátil executado de Downloads"
$cbPortable.AutoSize = $true
$cbPortable.Location = New-Object System.Drawing.Point(385,32)

$cbUnknown = New-Object System.Windows.Forms.CheckBox
$cbUnknown.Text = "Alertar sobre aplicativos desconhecidos"
$cbUnknown.AutoSize = $true
$cbUnknown.Location = New-Object System.Drawing.Point(385,67)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Salvar proteções"
$btnSave.Width = 170
$btnSave.Height = 35
$btnSave.Location = New-Object System.Drawing.Point(385,105)

$checks.Controls.AddRange(@(
    $cbDownloads,$cbSteam,$cbEpic,$cbPortable,$cbUnknown,$btnSave
))

$btnOn = New-Object System.Windows.Forms.Button
$btnOn.Text = "ATIVAR / RETOMAR"
$btnOn.Width = 345
$btnOn.Height = 48
$btnOn.Location = New-Object System.Drawing.Point(30,375)

$btnOff = New-Object System.Windows.Forms.Button
$btnOff.Text = "DESATIVAR PROTEÇÃO"
$btnOff.Width = 345
$btnOff.Height = 48
$btnOff.Location = New-Object System.Drawing.Point(420,375)

$btnPause = New-Object System.Windows.Forms.Button
$btnPause.Text = "Pausar por 1 hora"
$btnPause.Width = 345
$btnPause.Height = 44
$btnPause.Location = New-Object System.Drawing.Point(30,438)

$btnUnblock = New-Object System.Windows.Forms.Button
$btnUnblock.Text = "Desbloquear pastas Steam/Epic"
$btnUnblock.Width = 345
$btnUnblock.Height = 44
$btnUnblock.Location = New-Object System.Drawing.Point(420,438)

$btnTestRed = New-Object System.Windows.Forms.Button
$btnTestRed.Text = "Testar alerta vermelho"
$btnTestRed.Width = 165
$btnTestRed.Height = 42
$btnTestRed.Location = New-Object System.Drawing.Point(30,497)

$btnTestYellow = New-Object System.Windows.Forms.Button
$btnTestYellow.Text = "Testar alerta amarelo"
$btnTestYellow.Width = 165
$btnTestYellow.Height = 42
$btnTestYellow.Location = New-Object System.Drawing.Point(210,497)

$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Text = "Abrir log"
$btnLog.Width = 165
$btnLog.Height = 42
$btnLog.Location = New-Object System.Drawing.Point(420,497)

$btnDetections = New-Object System.Windows.Forms.Button
$btnDetections.Text = "Abrir detecções"
$btnDetections.Width = 165
$btnDetections.Height = 42
$btnDetections.Location = New-Object System.Drawing.Point(600,497)

$btnQuarantine = New-Object System.Windows.Forms.Button
$btnQuarantine.Text = "Abrir quarentena"
$btnQuarantine.Width = 165
$btnQuarantine.Height = 42
$btnQuarantine.Location = New-Object System.Drawing.Point(30,554)

$btnBaseline = New-Object System.Windows.Forms.Button
$btnBaseline.Text = "Refazer base Steam/Epic"
$btnBaseline.Width = 165
$btnBaseline.Height = 42
$btnBaseline.Location = New-Object System.Drawing.Point(210,554)

$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = "Abrir pasta do Guard"
$btnFolder.Width = 165
$btnFolder.Height = 42
$btnFolder.Location = New-Object System.Drawing.Point(420,554)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Encerrar até próximo login"
$btnExit.Width = 165
$btnExit.Height = 42
$btnExit.Location = New-Object System.Drawing.Point(600,554)

$note = New-Object System.Windows.Forms.Label
$note.Text = "Steam/Epic podem abrir normalmente. O Guard só bloqueia uma NOVA instalação/download no C:. Jogos que já existiam no C: entram na base inicial e não são bloqueados."
$note.Font = New-Object System.Drawing.Font("Segoe UI",9)
$note.MaximumSize = New-Object System.Drawing.Size(730,0)
$note.AutoSize = $true
$note.Location = New-Object System.Drawing.Point(31,620)

function Refresh-UI {
    $cfg = Get-Cfg
    if (-not $cfg) {
        $status.Text = "Status: erro ao ler configuração"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
        return
    }

    $paused = $false

    if ($cfg.PauseUntil) {
        try {
            $until = [datetime]::Parse([string]$cfg.PauseUntil)
            if ((Get-Date) -lt $until) { $paused = $true }
        } catch {}
    }

    if (-not $cfg.Enabled) {
        $status.Text = "Status: DESATIVADO"
        $status.ForeColor = [System.Drawing.Color]::DarkRed
    } elseif ($paused) {
        $status.Text = "Status: PAUSADO"
        $status.ForeColor = [System.Drawing.Color]::DarkOrange
    } else {
        $status.Text = "Status: ATIVO"
        $status.ForeColor = [System.Drawing.Color]::DarkGreen
    }

    $counts = Get-Counts
    $q = if ($cfg.QuarantinePath) {
        $cfg.QuarantinePath
    } else {
        "sem quarentena externa"
    }

    $summary.Text = (
        "Bloqueios registrados: {0}   |   Alertas: {1}   |   Quarentena: {2}" -f
        $counts[0],$counts[1],$q
    )

    $cbDownloads.Checked = [bool]$cfg.DownloadProtection
    $cbSteam.Checked = [bool]$cfg.SteamProtection
    $cbEpic.Checked = [bool]$cfg.EpicProtection
    $cbPortable.Checked = [bool]$cfg.PortableGameProtection
    $cbUnknown.Checked = [bool]$cfg.UnknownAppAlerts
}

$btnSave.Add_Click({
    $cfg = Get-Cfg

    if ($cfg) {
        $cfg.DownloadProtection = $cbDownloads.Checked
        $cfg.SteamProtection = $cbSteam.Checked
        $cfg.EpicProtection = $cbEpic.Checked
        $cfg.PortableGameProtection = $cbPortable.Checked
        $cfg.UnknownAppAlerts = $cbUnknown.Checked
        Save-Cfg $cfg
        Refresh-UI
    }
})

$btnOn.Add_Click({
    $cfg = Get-Cfg

    if ($cfg) {
        $cfg.Enabled = $true
        $cfg.PauseUntil = $null
        Save-Cfg $cfg
        Remove-Item $StopFlag -Force -ErrorAction SilentlyContinue
        Ensure-CoreRunning
        Refresh-UI
    }
})

$btnOff.Add_Click({
    $cfg = Get-Cfg

    if ($cfg) {
        $cfg.Enabled = $false
        $cfg.PauseUntil = $null
        Save-Cfg $cfg

        # Segurança: ao desativar, remove ACLs criadas pelo Guard.
        Unblock-All
        Refresh-UI
    }
})

$btnPause.Add_Click({
    $cfg = Get-Cfg

    if ($cfg) {
        $cfg.Enabled = $true
        $cfg.PauseUntil = (Get-Date).AddHours(1).ToString("o")
        Save-Cfg $cfg
        Refresh-UI
    }
})

$btnUnblock.Add_Click({
    Unblock-All

    [System.Windows.Forms.MessageBox]::Show(
        "Todos os bloqueios de pasta criados pelo Guard foram removidos.",
        "SSD System Guard",
        "OK",
        "Information"
    ) | Out-Null
})

$btnTestRed.Add_Click({
    "test" | Set-Content $TestRedFlag -Encoding ASCII
    Ensure-CoreRunning
})

$btnTestYellow.Add_Click({
    "test" | Set-Content $TestYellowFlag -Encoding ASCII
    Ensure-CoreRunning
})

$btnLog.Add_Click({
    if (-not (Test-Path $LogPath)) { "" | Set-Content $LogPath }
    Start-Process notepad.exe $LogPath
})

$btnDetections.Add_Click({
    if (-not (Test-Path $DetectionsPath)) {
        'Timestamp,Status,Category,Risk,Source,Name,Path,Reason,Action' |
            Set-Content $DetectionsPath -Encoding UTF8
    }

    Start-Process notepad.exe $DetectionsPath
})

$btnQuarantine.Add_Click({
    $cfg = Get-Cfg

    if ($cfg -and $cfg.QuarantinePath) {
        New-Item -ItemType Directory -Path $cfg.QuarantinePath -Force |
            Out-Null
        Start-Process explorer.exe $cfg.QuarantinePath
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Nenhum disco alternativo foi definido para quarentena.",
            "SSD System Guard",
            "OK",
            "Information"
        ) | Out-Null
    }
})

$btnBaseline.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "Isso fará o Guard considerar os jogos Steam/Epic que existem AGORA no C: como permitidos. Continuar?",
        "Refazer base",
        "YesNo",
        "Question"
    )

    if ($ans -eq "Yes") {
        Unblock-All

        $state = Get-State

        if ($state) {
            $state.Initialized = $false
            $state.SteamBaselineAppIds = @()
            $state.EpicBaselineLocations = @()
            $state.BlockedPaths = @()
            $state.LastBaseline = $null
            Save-State $state

            [System.Windows.Forms.MessageBox]::Show(
                "A base será recriada automaticamente pelo Guard.",
                "SSD System Guard",
                "OK",
                "Information"
            ) | Out-Null
        }
    }
})

$btnFolder.Add_Click({
    Start-Process explorer.exe $Base
})

$btnExit.Add_Click({
    "stop" | Set-Content $StopFlag -Encoding ASCII
})

$form.Controls.AddRange(@(
    $title,$desc,$status,$summary,$checks,
    $btnOn,$btnOff,$btnPause,$btnUnblock,
    $btnTestRed,$btnTestYellow,$btnLog,$btnDetections,
    $btnQuarantine,$btnBaseline,$btnFolder,$btnExit,$note
))

Ensure-CoreRunning
Refresh-UI

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.Add_Tick({ Refresh-UI })
$timer.Start()

[void]$form.ShowDialog()

try {
    $timer.Stop()
    $timer.Dispose()
} catch {}


$form.Add_FormClosed({
    try {
        if ($script:AppIcon) {
            $script:AppIcon.Dispose()
        }
    } catch {}
})
