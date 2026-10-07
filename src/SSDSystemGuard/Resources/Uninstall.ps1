#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms

$Base = Join-Path $env:ProgramData "SSDSystemGuard"
$Data = Join-Path $Base "Data"
$ConfigPath = Join-Path $Data "config.json"
$TaskName = "SSD System Guard"
$CommonDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
$PanelLink = Join-Path $CommonDesktop "SSD System Guard.lnk"

function Remove-StateBlocks([string]$StatePath) {
    if (-not (Test-Path $StatePath)) { return }
    try { $state=Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return }
    foreach($item in @($state.BlockedPaths)) {
        $p=[string]$item.Path
        if (-not $p -or -not (Test-Path $p)) { continue }
        $identity = if ($item.Identity) { [string]$item.Identity } else { $null }
        if (-not $identity) { continue }
        try {
            $acl=Get-Acl $p; $changed=$false
            foreach($rule in @($acl.Access)) {
                if ($rule.IdentityReference.Value -eq $identity -and $rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) {
                    [void]$acl.RemoveAccessRuleSpecific($rule); $changed=$true
                }
            }
            if ($changed) { Set-Acl $p $acl }
        } catch {}
    }
}

$quarantine=""
if (Test-Path $ConfigPath) { try { $quarantine=[string](Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json).QuarantinePath } catch {} }

try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*SSDSystemGuard*GuardCore.ps1*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {}

# Termina hosts instalados que mantêm o executável aberto em outras sessões.
try {
    Get-CimInstance Win32_Process -Filter "Name='SSDSystemGuard.exe'" |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq (Join-Path $Base 'SSDSystemGuard.exe') } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch {}
Start-Sleep -Milliseconds 600
foreach($state in @(Get-ChildItem $Data -Filter "state-*.json" -File -ErrorAction SilentlyContinue)) { Remove-StateBlocks $state.FullName }
foreach($t in @("SSD System Guard","SSD System Guard Download Blocker","SSD System Guard Definitivo")) { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }
Remove-Item $PanelLink -Force -ErrorAction SilentlyContinue

$deleteQ=$false
if ($quarantine -and (Test-Path $quarantine)) {
    $answer=[System.Windows.Forms.MessageBox]::Show("Deseja também apagar a quarentena e todos os arquivos dentro dela?`n`n$quarantine","SSD System Guard - Desinstalar",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
    $deleteQ=($answer -eq [System.Windows.Forms.DialogResult]::Yes)
}

Remove-Item $Base -Recurse -Force -ErrorAction SilentlyContinue
if ($deleteQ -and $quarantine) { Remove-Item $quarantine -Recurse -Force -ErrorAction SilentlyContinue }

[System.Windows.Forms.MessageBox]::Show("SSD System Guard removido deste computador para todas as contas locais.","SSD System Guard",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
exit 0
