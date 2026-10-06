#requires -Version 5.1
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

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

$TaskName = "SSD System Guard"

$Desktop = [Environment]::GetFolderPath("Desktop")
$PanelLink = Join-Path $Desktop "SSD System Guard - Painel.lnk"
$OldPanelLink = Join-Path $Desktop "SSD Guard Definitivo - Painel.lnk"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceCore = Join-Path $SourceDir "GuardCore.ps1"
$SourcePanel = Join-Path $SourceDir "Panel.ps1"
$SourceIcon = Join-Path $SourceDir "SSDSystemGuard.ico"

function Show-Box {
    param([string]$Text,[string]$Title="SSD System Guard")

    [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
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

function Remove-RecordedBlocks {
    param([string]$Folder)

    $oldState = Join-Path $Folder "state.json"
    if (-not (Test-Path $oldState)) { return }

    try {
        $state = Get-Content $oldState -Raw -Encoding UTF8 | ConvertFrom-Json

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

if (-not (Test-Path $SourceCore) -or -not (Test-Path $SourcePanel)) {
    throw "GuardCore.ps1 ou Panel.ps1 não encontrado ao lado do instalador."
}

# Para upgrade limpo, desfaz bloqueios registrados pela versão anterior.
Remove-RecordedBlocks $Base
Remove-RecordedBlocks $LegacyBase

# Encerra núcleos antigos/atuais antes da atualização.
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            (
                $_.CommandLine -like "*SSDSystemGuard*GuardCore.ps1*" -or
                $_.CommandLine -like "*SSDSystemGuardDefinitive*GuardCore.ps1*" -or
                $_.CommandLine -like "*SSDSystemGuard*Monitor.ps1*" -or
                $_.CommandLine -like "*SSDSystemGuard*DownloadBlocker.ps1*"
            )
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
} catch {}

# Remove tarefas de versões anteriores.
foreach ($oldTask in @(
    "SSD System Guard",
    "SSD System Guard Download Blocker",
    "SSD System Guard Definitivo"
)) {
    try {
        Unregister-ScheduledTask -TaskName $oldTask `
            -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
}

# Remove o atalho antigo com o nome/tema anterior.
Remove-Item $OldPanelLink -Force -ErrorAction SilentlyContinue

# Remove apenas a pasta "Definitive" antiga depois de desfazer as ACLs.
if (Test-Path $LegacyBase) {
    Remove-Item $LegacyBase -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $Base -Force | Out-Null

Copy-Item $SourceCore $CorePath -Force
Copy-Item $SourcePanel $PanelPath -Force

if (Test-Path $SourceIcon) {
    Copy-Item $SourceIcon $IconPath -Force
}

# Escolhe quarentena em um disco fixo diferente de C:, preferindo maior espaço livre.
$QuarantinePath = ""

try {
    $candidate = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Where-Object {
            $_.DeviceID -ne "C:" -and
            [uint64]$_.FreeSpace -gt 1073741824
        } |
        Sort-Object FreeSpace -Descending |
        Select-Object -First 1

    if ($candidate) {
        $QuarantinePath = Join-Path (
            $candidate.DeviceID + "\"
        ) "SSDGuard_Quarantine"
    }
} catch {}

$downloads = Join-Path $env:USERPROFILE "Downloads"

$config = [ordered]@{
    Version = "1.0.2"
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

$config | ConvertTo-Json -Depth 12 |
    Set-Content $ConfigPath -Encoding UTF8

[ordered]@{
    Initialized = $false
    SteamBaselineAppIds = @()
    EpicBaselineLocations = @()
    BlockedPaths = @()
    LastBaseline = $null
} | ConvertTo-Json -Depth 15 |
    Set-Content $StatePath -Encoding UTF8

"" | Set-Content $LogPath -Encoding UTF8

if (-not (Test-Path $DetectionsPath)) {
    'Timestamp,Status,Category,Risk,Source,Name,Path,Reason,Action' |
        Set-Content $DetectionsPath -Encoding UTF8
}

if ($QuarantinePath) {
    New-Item -ItemType Directory -Path $QuarantinePath -Force |
        Out-Null
}

# Atalho do painel com o MESMO ícone visual do aplicativo.
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($PanelLink)

$shortcut.TargetPath = (
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
)

$shortcut.Arguments = (
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PanelPath`""
)

$shortcut.WorkingDirectory = $Base

if (Test-Path $IconPath) {
    $shortcut.IconLocation = "$IconPath,0"
} else {
    $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,77"
}

$shortcut.Description = "Abrir o painel do SSD System Guard"
$shortcut.Save()

# Uma única tarefa, um único processo principal.
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument (
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$CorePath`""
    )

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

$principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "SSD System Guard - proteção de downloads e jogos no SSD do sistema." `
    -Force | Out-Null

Start-Process powershell.exe -ArgumentList (
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$CorePath`""
) -WindowStyle Hidden

Start-Sleep -Seconds 2

Start-Process powershell.exe -ArgumentList (
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PanelPath`""
) -WindowStyle Hidden

Show-Box @"
SSD System Guard instalado com sucesso.

PROTEÇÕES ATIVAS:
• Downloads de risco no C:;
• novos jogos Steam no C:;
• novas instalações Epic no C:;
• jogos portáteis executados de Downloads;
• alertas de aplicativos desconhecidos.

Steam e Epic podem abrir normalmente.

Jogos já existentes no C: entram na base inicial e não são bloqueados.

Quarentena:
$(if($QuarantinePath){$QuarantinePath}else{"Nenhum disco alternativo encontrado; arquivos bloqueados finais serão removidos do C:."})

Atalho criado:
SSD System Guard - Painel
"@
