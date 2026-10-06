#requires -Version 5.1
$ErrorActionPreference = "Stop"

$ProductName = "SSD System Guard"
$Base = Join-Path $env:LOCALAPPDATA "SSDSystemGuard"
$LegacyBase = Join-Path $env:LOCALAPPDATA "SSDSystemGuardDefinitive"

$CorePath = Join-Path $Base "GuardCore.ps1"
$PanelPath = Join-Path $Base "Panel.ps1"
$IconPath = Join-Path $Base "SSDSystemGuard.ico"
$ConfigPath = Join-Path $Base "config.json"
$StatePath = Join-Path $Base "state.json"
$LogPath = Join-Path $Base "guard.log"
$DetectionsPath = Join-Path $Base "detections.csv"
$InstallLogPath = Join-Path $Base "install.log"
$InstallResultPath = Join-Path $Base "install.result.json"

$TaskName = "SSD System Guard"

$Desktop = [Environment]::GetFolderPath("Desktop")
$PanelLink = Join-Path $Desktop "SSD System Guard - Painel.lnk"
$OldPanelLink = Join-Path $Desktop "SSD Guard Definitivo - Painel.lnk"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceCore = Join-Path $SourceDir "GuardCore.ps1"
$SourcePanel = Join-Path $SourceDir "Panel.ps1"
$SourceIcon = Join-Path $SourceDir "SSDSystemGuard.ico"
$SourceUninstall = Join-Path $SourceDir "Uninstall.ps1"

function Write-InstallLog {
    param([string]$Message)

    try {
        New-Item -ItemType Directory -Path $Base -Force |
            Out-Null

        $line = "[{0}] {1}" -f (
            Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ), $Message

        Add-Content -LiteralPath $InstallLogPath `
            -Value $line `
            -Encoding UTF8
    } catch {}
}

function Write-InstallResult {
    param(
        [bool]$Success,
        [string]$Message
    )

    try {
        New-Item -ItemType Directory -Path $Base -Force |
            Out-Null

        [ordered]@{
            Success = $Success
            Message = $Message
            Timestamp = (Get-Date).ToString("o")
        } |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $InstallResultPath `
                -Encoding UTF8
    } catch {}
}

function Remove-GuardACL {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return }

    try {
        $identity =
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        $acl = Get-Acl $Path
        $changed = $false

        foreach ($rule in @($acl.Access)) {
            if (
                $rule.IdentityReference.Value -eq $identity -and
                $rule.AccessControlType -eq
                    [System.Security.AccessControl.AccessControlType]::Deny
            ) {
                [void]$acl.RemoveAccessRuleSpecific($rule)
                $changed = $true
            }
        }

        if ($changed) {
            Set-Acl -Path $Path -AclObject $acl
        }
    } catch {}
}

function Remove-RecordedBlocks {
    param([string]$Folder)

    $oldState = Join-Path $Folder "state.json"

    if (-not (Test-Path $oldState)) {
        return
    }

    try {
        $state =
            Get-Content $oldState -Raw -Encoding UTF8 |
            ConvertFrom-Json

        foreach ($item in @($state.BlockedPaths)) {
            $p = $null

            if ($item -is [string]) {
                $p = [string]$item
            }
            elseif ($item.PSObject.Properties["Path"]) {
                $p = [string]$item.Path
            }

            if ($p) {
                Remove-GuardACL $p
            }
        }
    } catch {}
}

function Register-StartupTask {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument (
            "-NoProfile -STA -ExecutionPolicy Bypass " +
            "-WindowStyle Hidden -File `"$CorePath`""
        )

    $trigger = New-ScheduledTaskTrigger `
        -AtLogOn `
        -User $env:USERNAME

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    $principal = New-ScheduledTaskPrincipal `
        -UserId (
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        ) `
        -LogonType Interactive `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description (
            "SSD System Guard - proteção de downloads e jogos no SSD do sistema."
        ) `
        -Force |
        Out-Null
}

try {
    New-Item -ItemType Directory -Path $Base -Force |
        Out-Null

    Remove-Item -LiteralPath $InstallResultPath `
        -Force -ErrorAction SilentlyContinue

    Write-InstallLog "Início da instalação/atualização v1.0.5."

    if (
        -not (Test-Path $SourceCore) -or
        -not (Test-Path $SourcePanel) -or
        -not (Test-Path $SourceIcon)
    ) {
        throw "Recursos essenciais do instalador não foram encontrados."
    }

    # Preserva a preferência de quem já usava uma versão anterior.
    $HadStartupTask = $false

    foreach ($existingTask in @(
        "SSD System Guard",
        "SSD System Guard Download Blocker",
        "SSD System Guard Definitivo"
    )) {
        try {
            if (
                Get-ScheduledTask `
                    -TaskName $existingTask `
                    -ErrorAction SilentlyContinue
            ) {
                $HadStartupTask = $true
                break
            }
        } catch {}
    }

    Remove-RecordedBlocks $Base
    Remove-RecordedBlocks $LegacyBase

    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object {
                $_.ProcessId -ne $PID -and
                (
                    $_.CommandLine -like "*\SSDSystemGuard\GuardCore.ps1*" -or
                    $_.CommandLine -like "*\SSDSystemGuard\Panel.ps1*" -or
                    $_.CommandLine -like "*\SSDSystemGuardDefinitive\GuardCore.ps1*" -or
                    $_.CommandLine -like "*\SSDSystemGuardDefinitive\Panel.ps1*"
                )
            } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
    } catch {}

    foreach ($oldTask in @(
        "SSD System Guard",
        "SSD System Guard Download Blocker",
        "SSD System Guard Definitivo"
    )) {
        try {
            Unregister-ScheduledTask `
                -TaskName $oldTask `
                -Confirm:$false `
                -ErrorAction SilentlyContinue
        } catch {}
    }

    Remove-Item $OldPanelLink `
        -Force `
        -ErrorAction SilentlyContinue

    if (Test-Path $LegacyBase) {
        Remove-Item $LegacyBase `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $Base -Force |
        Out-Null

    Copy-Item $SourceCore $CorePath -Force
    Copy-Item $SourcePanel $PanelPath -Force
    Copy-Item $SourceIcon $IconPath -Force

    if (Test-Path $SourceUninstall) {
        Copy-Item $SourceUninstall `
            (Join-Path $Base "Uninstall.ps1") `
            -Force
    }

    $QuarantinePath = ""

    try {
        $candidate =
            Get-CimInstance Win32_LogicalDisk `
                -Filter "DriveType=3" |
            Where-Object {
                $_.DeviceID -ne "C:" -and
                [uint64]$_.FreeSpace -gt 1073741824
            } |
            Sort-Object FreeSpace -Descending |
            Select-Object -First 1

        if ($candidate) {
            $QuarantinePath =
                Join-Path (
                    $candidate.DeviceID + "\"
                ) "SSDGuard_Quarantine"
        }
    } catch {}

    $downloads =
        Join-Path $env:USERPROFILE "Downloads"

    $config = [ordered]@{
        Version = "1.0.5"
        Enabled = $true
        SystemDrive = "C:"
        DownloadProtection = $true
        SteamProtection = $true
        EpicProtection = $true
        PortableGameProtection = $true
        UnknownAppAlerts = $true
        ProtectedDownloadFolders = @($downloads)
        QuarantinePath = $QuarantinePath
        PauseUntil = $null
    }

    $config |
        ConvertTo-Json -Depth 12 |
        Set-Content $ConfigPath -Encoding UTF8

    [ordered]@{
        Initialized = $false
        SteamBaselineAppIds = @()
        EpicBaselineLocations = @()
        BlockedPaths = @()
        LastBaseline = $null
    } |
        ConvertTo-Json -Depth 15 |
        Set-Content $StatePath -Encoding UTF8

    "" |
        Set-Content $LogPath -Encoding UTF8

    if (-not (Test-Path $DetectionsPath)) {
        'Timestamp,Status,Category,Risk,Source,Name,Path,Reason,Action' |
            Set-Content $DetectionsPath -Encoding UTF8
    }

    if ($QuarantinePath) {
        New-Item -ItemType Directory `
            -Path $QuarantinePath `
            -Force |
            Out-Null
    }

    $ws = New-Object -ComObject WScript.Shell
    $shortcut = $ws.CreateShortcut($PanelLink)

    $shortcut.TargetPath =
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $shortcut.Arguments =
        "-NoProfile -STA -ExecutionPolicy Bypass " +
        "-WindowStyle Hidden -File `"$PanelPath`""

    $shortcut.WorkingDirectory = $Base
    $shortcut.IconLocation = "$IconPath,0"
    $shortcut.Description =
        "Abrir o painel do SSD System Guard"

    $shortcut.Save()

    # Instalação limpa: inicialização com Windows fica OFF por padrão.
    # Atualização: preserva a preferência anterior.
    if ($HadStartupTask) {
        Register-StartupTask
        Write-InstallLog (
            "Preferência anterior preservada: " +
            "inicialização com Windows ativada."
        )
    }
    else {
        Write-InstallLog (
            "Inicialização com Windows desativada por padrão. " +
            "O usuário pode ativá-la pelo aplicativo."
        )
    }

    # O Guard sempre inicia na sessão atual após instalar.
    Start-Process powershell.exe `
        -ArgumentList (
            "-NoProfile -STA -ExecutionPolicy Bypass " +
            "-WindowStyle Hidden -File `"$CorePath`""
        ) `
        -WindowStyle Hidden

    Start-Sleep -Milliseconds 800

    Write-InstallResult `
        -Success $true `
        -Message "Instalação concluída com sucesso."

    Write-InstallLog "Instalação v1.0.5 concluída com sucesso."

    exit 0
}
catch {
    $message = $_.Exception.Message

    Write-InstallLog (
        "ERRO: " +
        $message +
        " | " +
        $_.ScriptStackTrace
    )

    Write-InstallResult `
        -Success $false `
        -Message $message

    exit 1
}
