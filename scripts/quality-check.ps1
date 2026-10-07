#requires -Version 5.1
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "src\SSDSystemGuard\SSDSystemGuard.csproj"
$resources = Join-Path $root "src\SSDSystemGuard\Resources"

$required = @(
    $project,
    (Join-Path $root "src\SSDSystemGuard\Program.cs"),
    (Join-Path $root "src\SSDSystemGuard\BackgroundHost.cs"),
    (Join-Path $root "src\SSDSystemGuard\GuardManager.cs"),
    (Join-Path $resources "GuardCore.ps1"),
    (Join-Path $resources "Panel.ps1"),
    (Join-Path $resources "Install.ps1"),
    (Join-Path $resources "Uninstall.ps1")
)

foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Arquivo obrigatório ausente: $path"
    }
}

[xml]$xml = Get-Content -LiteralPath $project -Raw
$version = [string]$xml.Project.PropertyGroup.Version

if ([string]::IsNullOrWhiteSpace($version)) {
    throw "A versão não foi encontrada no csproj."
}

$installText = Get-Content (Join-Path $resources "Install.ps1") -Raw
if ($installText -notmatch [regex]::Escape('Version="' + $version + '"')) {
    throw "Versão do Install.ps1 não corresponde ao csproj: $version"
}

$guardText = Get-Content (Join-Path $resources "GuardCore.ps1") -Raw
$requiredGuardMarkers = @(
    "function Check-SteamDownloads",
    "function Check-EpicDownloads",
    "function Invoke-ProcessScan",
    "function Setup-DownloadWatchers",
    "function Test-GuardPathAlreadyBlocked",
    "function Show-SteamRetryBlockedAlert"
)

foreach ($marker in $requiredGuardMarkers) {
    if ($guardText -notlike "*$marker*") {
        throw "GuardCore.ps1 perdeu função obrigatória: $marker"
    }
}

$panelText = Get-Content (Join-Path $resources "Panel.ps1") -Raw
foreach ($marker in @(
    'Show-PanelTestAlert "Red"',
    'Show-PanelTestAlert "Yellow"',
    "panel_errors.log"
)) {
    if ($panelText -notlike "*$marker*") {
        throw "Panel.ps1 perdeu recurso obrigatório: $marker"
    }
}

$hostText = Get-Content (Join-Path $root "src\SSDSystemGuard\BackgroundHost.cs") -Raw
if ($hostText -notlike "*RunBackground*" -or
    $hostText -notlike "*RunPanel*") {
    throw "BackgroundHost.cs está incompleto."
}

Write-Host "PASS arquivos obrigatórios"
Write-Host "PASS versão consistente: $version"
Write-Host "PASS marcadores críticos do GuardCore"
Write-Host "PASS alertas de teste do painel"
Write-Host "PASS host background/panel"

# PowerShell 7 permits syntax combinations that can regress on Windows PowerShell 5.1.
# The real parser gate runs separately, but keep this explicit regression guard too.
if ($guardText -match '\)\.\s*(?:\r?\n)') {
    throw "GuardCore.ps1 contains member access split after '.', unsafe for Windows PowerShell 5.1."
}

foreach ($marker in @(
    "Write-GuardHeartbeat",
    "DOWNLOAD WATCHERS READY"
)) {
    if ($guardText -notlike "*$marker*") {
        throw "GuardCore.ps1 lost runtime diagnostic marker: $marker"
    }
}
