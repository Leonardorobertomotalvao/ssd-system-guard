#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms

$Base = Join-Path $env:LOCALAPPDATA "SSDSystemGuard"
$LegacyBase = Join-Path $env:LOCALAPPDATA "SSDSystemGuardDefinitive"

$StatePath = Join-Path $Base "state.json"
$ConfigPath = Join-Path $Base "config.json"

$Desktop = [Environment]::GetFolderPath("Desktop")
$PanelLink = Join-Path $Desktop "SSD System Guard - Painel.lnk"
$OldPanelLink = Join-Path $Desktop "SSD Guard Definitivo - Painel.lnk"

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

function Remove-StateBlocks {
    param([string]$Folder)

    $stateFile = Join-Path $Folder "state.json"
    if (-not (Test-Path $stateFile)) { return }

    try {
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json

        foreach ($item in @($state.BlockedPaths)) {
            $p = $null

            if ($item -is [string]) {
                $p = [string]$item
            } elseif ($item.PSObject.Properties["Path"]) {
                $p = [string]$item.Path
            }

            if ($p) {
                Remove-GuardACL $p
            }
        }
    } catch {}
}

$deleteQuarantine = $false
$quarantine = ""

foreach ($cfgPath in @(
    (Join-Path $Base "config.json"),
    (Join-Path $LegacyBase "config.json")
)) {
    if (-not $quarantine -and (Test-Path $cfgPath)) {
        try {
            $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $quarantine = [string]$cfg.QuarantinePath
        } catch {}
    }
}

if ($quarantine -and (Test-Path $quarantine)) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Também deseja APAGAR a pasta de quarentena e os arquivos dentro dela?`n`n$quarantine",
        "Desinstalar SSD System Guard",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        $deleteQuarantine = $true
    }
}

try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            (
                $_.CommandLine -like "*SSDSystemGuard*GuardCore.ps1*" -or
                $_.CommandLine -like "*SSDSystemGuardDefinitive*"
            )
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
} catch {}

Remove-StateBlocks $Base
Remove-StateBlocks $LegacyBase

foreach ($taskName in @(
    "SSD System Guard",
    "SSD System Guard Download Blocker",
    "SSD System Guard Definitivo"
)) {
    try {
        Unregister-ScheduledTask -TaskName $taskName `
            -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
}

Remove-Item $PanelLink -Force -ErrorAction SilentlyContinue
Remove-Item $OldPanelLink -Force -ErrorAction SilentlyContinue

foreach ($folder in @($Base,$LegacyBase)) {
    if (Test-Path $folder) {
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($deleteQuarantine -and $quarantine -and (Test-Path $quarantine)) {
    Remove-Item $quarantine -Recurse -Force -ErrorAction SilentlyContinue
}

[System.Windows.Forms.MessageBox]::Show(
    "SSD System Guard removido.`n`nAs regras de bloqueio criadas pelo Guard foram desfeitas.",
    "SSD System Guard",
    "OK",
    "Information"
) | Out-Null
