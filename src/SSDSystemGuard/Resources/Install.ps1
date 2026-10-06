#requires -Version 5.1
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

$Base = Join-Path $env:LOCALAPPDATA "SSDSystemGuardDefinitive"
$CorePath = Join-Path $Base "GuardCore.ps1"
$PanelPath = Join-Path $Base "Panel.ps1"
$ConfigPath = Join-Path $Base "config.json"
$StatePath = Join-Path $Base "state.json"
$LogPath = Join-Path $Base "guard.log"
$DetectionsPath = Join-Path $Base "detections.csv"

$TaskName = "SSD System Guard Definitivo"

$Desktop = [Environment]::GetFolderPath("Desktop")
$PanelLink = Join-Path $Desktop "SSD Guard Definitivo - Painel.lnk"

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceCore = Join-Path $SourceDir "GuardCore.ps1"
$SourcePanel = Join-Path $SourceDir "Panel.ps1"

function Show-Box {
    param([string]$Text,[string]$Title="SSD System Guard Definitivo")

    [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

if (-not (Test-Path $SourceCore) -or -not (Test-Path $SourcePanel)) {
    throw "GuardCore.ps1 ou Panel.ps1 não encontrado ao lado do instalador."
}

New-Item -ItemType Directory -Path $Base -Force | Out-Null

# Limpeza preventiva de versões antigas caso tenham restado vestígios.
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

try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            (
                $_.CommandLine -like "*SSDSystemGuard*Monitor.ps1*" -or
                $_.CommandLine -like "*SSDSystemGuard*DownloadBlocker.ps1*" -or
                $_.CommandLine -like "*SSDSystemGuardDefinitive*GuardCore.ps1*"
            )
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
} catch {}

Copy-Item $SourceCore $CorePath -Force
Copy-Item $SourcePanel $PanelPath -Force

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
    Version = "3.0"
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

# Painel na área de trabalho.
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($PanelLink)

$shortcut.TargetPath = (
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
)

$shortcut.Arguments = (
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PanelPath`""
)

$shortcut.WorkingDirectory = $Base
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,77"
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
    -Description "SSD System Guard Definitivo v3 - proteção de downloads e jogos no SSD C:." `
    -Force | Out-Null

Start-Process powershell.exe -ArgumentList (
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$CorePath`""
) -WindowStyle Hidden

Start-Sleep -Seconds 2

Start-Process powershell.exe -ArgumentList (
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PanelPath`""
) -WindowStyle Hidden

Show-Box @"
SSD System Guard Definitivo v3 instalado.

ARQUITETURA LIMPA:
• 1 único núcleo;
• 1 único ícone na bandeja;
• 1 única tarefa de inicialização;
• 1 único painel.

PROTEÇÕES:
• Downloads de risco no C:;
• novos jogos Steam no C:;
• novas instalações Epic no C:;
• jogos portáteis executados de Downloads;
• alerta de aplicativos desconhecidos.

Steam e Epic podem abrir normalmente.

Jogos já existentes no C: entram na base inicial e não são bloqueados.

Quarentena:
$(if($QuarantinePath){$QuarantinePath}else{"Nenhum disco alternativo encontrado; arquivos bloqueados finais serão removidos do C:."})

Atalho criado:
SSD Guard Definitivo - Painel
"@
