#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms

$Base = Join-Path $env:LOCALAPPDATA "SSDSystemGuardDefinitive"
$StatePath = Join-Path $Base "state.json"
$ConfigPath = Join-Path $Base "config.json"
$TaskName = "SSD System Guard Definitivo"

$Desktop = [Environment]::GetFolderPath("Desktop")
$PanelLink = Join-Path $Desktop "SSD Guard Definitivo - Painel.lnk"

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

$deleteQuarantine = $false
$quarantine = ""

if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $quarantine = [string]$cfg.QuarantinePath
    } catch {}
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
            $_.CommandLine -like "*SSDSystemGuardDefinitive*"
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force
        }
} catch {}

if (Test-Path $StatePath) {
    try {
        $state = Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json

        foreach ($item in @($state.BlockedPaths)) {
            Remove-GuardACL ([string]$item.Path)
        }
    } catch {}
}

try {
    Unregister-ScheduledTask -TaskName $TaskName `
        -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

Remove-Item $PanelLink -Force -ErrorAction SilentlyContinue

if (Test-Path $Base) {
    Remove-Item $Base -Recurse -Force -ErrorAction SilentlyContinue
}

if ($deleteQuarantine -and $quarantine -and (Test-Path $quarantine)) {
    Remove-Item $quarantine -Recurse -Force -ErrorAction SilentlyContinue
}

[System.Windows.Forms.MessageBox]::Show(
    "SSD System Guard Definitivo removido.`n`nAs regras de bloqueio criadas pelo Guard foram desfeitas.",
    "SSD System Guard",
    "OK",
    "Information"
) | Out-Null
