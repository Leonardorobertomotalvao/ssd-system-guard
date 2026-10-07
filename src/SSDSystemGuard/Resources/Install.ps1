#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$AppExe)

$ErrorActionPreference = "Stop"

$Base = Join-Path $env:ProgramData "SSDSystemGuard"
$Data = Join-Path $Base "Data"
$CorePath = Join-Path $Base "GuardCore.ps1"
$CommandsPath = Join-Path $Base "GuardCommands.ps1"
$IconPath = Join-Path $Base "SSDSystemGuard.ico"
$ConfigPath = Join-Path $Data "config.json"
$LogPath = Join-Path $Data "guard.log"
$DetectionsPath = Join-Path $Data "detections.csv"
$InstallLogPath = Join-Path $Data "install.log"
$InstallResultPath = Join-Path $Data "install.result.json"
$TaskName = "SSD System Guard"
$LauncherPath = Join-Path $Base "LaunchGuard.vbs"

$LegacyBase = Join-Path $env:LOCALAPPDATA "SSDSystemGuard"
$LegacyDefinitive = Join-Path $env:LOCALAPPDATA "SSDSystemGuardDefinitive"

$CommonDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
$PanelLink = Join-Path $CommonDesktop "SSD System Guard.lnk"
$OldUserDesktop = [Environment]::GetFolderPath("Desktop")

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceCore = Join-Path $SourceDir "GuardCore.ps1"
$InstalledExe = Join-Path $Base "SSDSystemGuard.exe"
$SourceCommands = Join-Path $SourceDir "GuardCommands.ps1"
$SourceIcon = Join-Path $SourceDir "SSDSystemGuard.ico"
$SourceUninstall = Join-Path $SourceDir "Uninstall.ps1"

function Write-InstallLog([string]$Message) {
    try {
        New-Item -ItemType Directory -Path $Data -Force | Out-Null
        Add-Content $InstallLogPath ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Message) -Encoding UTF8
    } catch {}
}

function Write-InstallResult([bool]$Success,[string]$Message) {
    try {
        [ordered]@{ Success=$Success; Message=$Message; Timestamp=(Get-Date).ToString("o") } |
            ConvertTo-Json | Set-Content $InstallResultPath -Encoding UTF8
    } catch {}
}

function Remove-LegacyRules([string]$Folder) {
    foreach ($stateFile in @(Get-ChildItem $Folder -Filter "state*.json" -File -ErrorAction SilentlyContinue)) {
        try {
            $state = Get-Content $stateFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($item in @($state.BlockedPaths)) {
                $p=[string]$item.Path
                if (-not $p -or -not (Test-Path $p)) { continue }
                $identity = if ($item.Identity) { [string]$item.Identity } else { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
                $acl=Get-Acl $p; $changed=$false
                foreach($rule in @($acl.Access)) {
                    if ($rule.IdentityReference.Value -eq $identity -and $rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) {
                        [void]$acl.RemoveAccessRuleSpecific($rule); $changed=$true
                    }
                }
                if ($changed) { Set-Acl -Path $p -AclObject $acl }
            }
        } catch {}
    }
}

function Write-GuardLauncher {
    $vbs = @'
Set shell = CreateObject("WScript.Shell")
ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
core = shell.ExpandEnvironmentStrings("%ProgramData%") & "\SSDSystemGuard\GuardCore.ps1"
cmd = """" & ps & """ -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & core & """"
rc = shell.Run(cmd, 0, True)
WScript.Quit rc
'@

    Set-Content -LiteralPath $LauncherPath -Value $vbs -Encoding ASCII
}

function Register-AllUsersTask {
    $wscript = Join-Path $env:SystemRoot "System32\wscript.exe"

    $action = New-ScheduledTaskAction `
        -Execute $wscript `
        -Argument ('"' + $LauncherPath + '"')

    $trigger = New-ScheduledTaskTrigger -AtLogOn

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew `
        -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -Priority 8

    $principal = New-ScheduledTaskPrincipal `
        -GroupId "S-1-5-32-545" `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "SSD System Guard - proteção contínua para todas as contas locais." `
        -Force |
        Out-Null
}

try {
    New-Item -ItemType Directory -Path $Base -Force | Out-Null
    New-Item -ItemType Directory -Path $Data -Force | Out-Null

    # Dados compartilhados podem ser atualizados pelas contas locais; scripts
    # permanecem protegidos no diretório pai do ProgramData.
    # Users can read and execute installed code, but must not edit it.
    # Mutable per-user state and logs remain in the Data directory.
    & icacls.exe $Base /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Falha ao configurar ACL da pasta de instalação." }
    & icacls.exe $Data /grant:r '*S-1-5-32-545:(OI)(CI)M' /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Falha ao configurar ACL da pasta de dados." }

    Remove-Item $InstallResultPath -Force -ErrorAction SilentlyContinue
    Write-InstallLog "Início da instalação machine-wide v1.2.1."

    if (-not (Test-Path $SourceCore) -or -not (Test-Path $SourceCommands) -or -not (Test-Path $SourceIcon) -or -not (Test-Path $AppExe -PathType Leaf)) {
        throw "Recursos essenciais do instalador não foram encontrados."
    }

    Remove-LegacyRules $LegacyBase
    Remove-LegacyRules $LegacyDefinitive

    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*SSDSystemGuard*GuardCore.ps1*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch {}

    # Kill the legacy PowerShell WinForms panel from old builds.
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object {
                $_.ProcessId -ne $PID -and
                $_.CommandLine -like "*SSDSystemGuard*Panel.ps1*"
            } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
    } catch {}

    # Kill old --panel hosts too. The main installer window is not --panel.
    try {
        Get-CimInstance Win32_Process -Filter "Name='SSDSystemGuard.exe'" |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine -like "*--panel*"
            } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
    } catch {}

    try {
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -match '^(wscript|cscript)\.exe$' -and
                $_.CommandLine -like "*SSDSystemGuard*LaunchGuard.vbs*"
            } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
    } catch {}

    foreach($t in @("SSD System Guard","SSD System Guard Download Blocker","SSD System Guard Definitivo")) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Stop an old installed host before updating its executable.
    try {
        Get-CimInstance Win32_Process -Filter "Name='SSDSystemGuard.exe'" |
            Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $InstalledExe } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch {}
    Start-Sleep -Milliseconds 600

    if (-not [string]::Equals(( [IO.Path]::GetFullPath($AppExe) ),
                             ( [IO.Path]::GetFullPath($InstalledExe) ),
                             [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $AppExe -Destination $InstalledExe -Force -ErrorAction Stop
    }
    Copy-Item $SourceCore $CorePath -Force
    Copy-Item $SourceCommands $CommandsPath -Force
    Copy-Item $SourceIcon $IconPath -Force

    # v1.2.1: legacy PowerShell UI is forbidden at runtime.
    Remove-Item (Join-Path $Base "Panel.ps1") `
        -Force `
        -ErrorAction SilentlyContinue
    if (Test-Path $SourceUninstall) { Copy-Item $SourceUninstall (Join-Path $Base "Uninstall.ps1") -Force }
    Write-GuardLauncher

    $oldCfg=$null
    foreach($candidate in @((Join-Path $LegacyBase "config.json"),(Join-Path $LegacyDefinitive "config.json"),$ConfigPath)) {
        if (-not $oldCfg -and (Test-Path $candidate)) { try { $oldCfg=Get-Content $candidate -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
    }

    $QuarantinePath = if ($oldCfg -and $oldCfg.QuarantinePath) { [string]$oldCfg.QuarantinePath } else { "" }
    if (-not $QuarantinePath) {
        try {
            $candidate = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
                Where-Object { $_.DeviceID -ne "C:" -and [uint64]$_.FreeSpace -gt 1073741824 } |
                Sort-Object FreeSpace -Descending | Select-Object -First 1
            if ($candidate) { $QuarantinePath = Join-Path ($candidate.DeviceID + "\") "SSDGuard_Quarantine" }
        } catch {}
    }

    $config=[ordered]@{
        Version="1.2.1"; Enabled=if($oldCfg){[bool]$oldCfg.Enabled}else{$true}; SystemDrive="C:"
        DownloadProtection=if($oldCfg){[bool]$oldCfg.DownloadProtection}else{$true}
        SteamProtection=if($oldCfg){[bool]$oldCfg.SteamProtection}else{$true}
        EpicProtection=if($oldCfg){[bool]$oldCfg.EpicProtection}else{$true}
        PortableGameProtection=if($oldCfg){[bool]$oldCfg.PortableGameProtection}else{$true}
        UnknownAppAlerts=if($oldCfg){[bool]$oldCfg.UnknownAppAlerts}else{$true}
        ProtectedDownloadFolders=@(); QuarantinePath=$QuarantinePath; PauseUntil=$null
    }
    $config | ConvertTo-Json -Depth 12 | Set-Content $ConfigPath -Encoding UTF8
    if (-not (Test-Path $DetectionsPath)) { 'Timestamp,Status,Category,Risk,Source,Name,Path,Reason,Action' | Set-Content $DetectionsPath -Encoding UTF8 }
    if (-not (Test-Path $LogPath)) { "" | Set-Content $LogPath -Encoding UTF8 }
    if ($QuarantinePath) { New-Item -ItemType Directory -Path $QuarantinePath -Force | Out-Null }

    # Atalho público: aparece para todas as contas do Windows.
    $ws=New-Object -ComObject WScript.Shell
    $shortcut=$ws.CreateShortcut($PanelLink)
    $shortcut.TargetPath=$InstalledExe
    $shortcut.Arguments="--panel"
    $shortcut.WorkingDirectory=$Base
    $shortcut.IconLocation="$IconPath,0"
    $shortcut.Description="Abrir SSD System Guard"
    $shortcut.Save()

    foreach($oldLink in @(
        (Join-Path $OldUserDesktop "SSD System Guard - Painel.lnk"),
        (Join-Path $OldUserDesktop "SSD Guard Definitivo - Painel.lnk")
    )) { Remove-Item $oldLink -Force -ErrorAction SilentlyContinue }

    Get-ChildItem -LiteralPath $Data -Filter "stop-*.flag" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Register-AllUsersTask
    Write-InstallLog "Tarefa com recuperação automática registrada."

    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    } catch {
        Write-InstallLog ("Aviso ao iniciar tarefa: " + $_.Exception.Message)
        Start-Process `
            -FilePath (Join-Path $env:SystemRoot "System32\wscript.exe") `
            -ArgumentList ('"' + $LauncherPath + '"') `
            -WindowStyle Hidden
    }

    Start-Sleep -Milliseconds 900

    # Remove somente versões antigas por usuário após migrar/desbloquear.
    Remove-Item $LegacyBase -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $LegacyDefinitive -Recurse -Force -ErrorAction SilentlyContinue

    Write-InstallResult $true "Instalação para todas as contas concluída com sucesso."
    Write-InstallLog "Instalação v1.2.1 concluída."
    exit 0
}
catch {
    Write-InstallLog ("ERRO: " + $_.Exception.Message + " | " + $_.ScriptStackTrace)
    Write-InstallResult $false $_.Exception.Message
    exit 1
}
