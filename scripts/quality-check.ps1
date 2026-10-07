#requires -Version 5.1
$ErrorActionPreference = "Stop"

function Assert-ContainsLiteral {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Text,

        [Parameter(Mandatory=$true)]
        [string]$Marker,

        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage
    )

    if (-not $Text.Contains($Marker)) {
        throw $ErrorMessage
    }
}

# Self-test do próprio validador.
$selfTestText = 'alpha [pscustomobject] $StopFlag omega'

Assert-ContainsLiteral `
    -Text $selfTestText `
    -Marker '[pscustomobject]' `
    -ErrorMessage 'quality-check self-test failed for brackets.'

Assert-ContainsLiteral `
    -Text $selfTestText `
    -Marker '$StopFlag' `
    -ErrorMessage 'quality-check self-test failed for dollar-sign literal.'

if ($selfTestText.Contains('$DoesNotExist')) {
    throw 'quality-check self-test produced an impossible positive match.'
}

$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "src\SSDSystemGuard\SSDSystemGuard.csproj"
$src = Join-Path $root "src\SSDSystemGuard"
$resources = Join-Path $src "Resources"

$required = @(
    $project,
    (Join-Path $src "Program.cs"),
    (Join-Path $src "BackgroundHost.cs"),
    (Join-Path $src "GuardManager.cs"),
    (Join-Path $src "AdvancedPanelForm.cs"),
    (Join-Path $src "NativeAlertForm.cs"),
    (Join-Path $resources "GuardCore.ps1"),
    (Join-Path $resources "GuardCommands.ps1"),
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

foreach ($marker in @(
    "function Check-SteamDownloads",
    "function Check-EpicDownloads",
    "function Invoke-ProcessScan",
    "function Setup-DownloadWatchers",
    "function Test-GuardPathAlreadyBlocked",
    "function Show-SteamRetryBlockedAlert",
    "Write-GuardHeartbeat",
    "DOWNLOAD WATCHERS READY"
)) {
    Assert-ContainsLiteral `
        -Text $guardText `
        -Marker $marker `
        -ErrorMessage "GuardCore.ps1 perdeu função/recurso obrigatório: $marker"
}

if ($guardText -match '\)\.\s*(?:\r?\n)') {
    throw "GuardCore.ps1 contém member access inseguro para Windows PowerShell 5.1."
}

if ($guardText.Contains("Encerrar até o próximo login")) {
    throw "GuardCore.ps1 voltou a expor encerramento pelo tray."
}

if ($guardText.Contains('$StopFlag')) {
    throw "GuardCore.ps1 voltou a usar StopFlag."
}

foreach ($marker in @(
    "RestartCount 999",
    "RestartInterval (New-TimeSpan -Minutes 1)",
    "MultipleInstances IgnoreNew",
    "LaunchGuard.vbs",
    "GuardCommands.ps1",
    "Remove-Item (Join-Path `$Base `"Panel.ps1`")"
)) {
    Assert-ContainsLiteral `
        -Text $installText `
        -Marker $marker `
        -ErrorMessage "Install.ps1 perdeu requisito: $marker"
}

$programText = Get-Content (Join-Path $src "Program.cs") -Raw
Assert-ContainsLiteral `
    -Text $programText `
    -Marker 'Application.Run(new AdvancedPanelForm())' `
    -ErrorMessage 'Program.cs não abre o painel nativo.'

if ($programText.Contains("RunPanel(")) {
    throw "Program.cs voltou a iniciar painel PowerShell."
}

$panelText = Get-Content (Join-Path $src "AdvancedPanelForm.cs") -Raw
foreach ($marker in @(
    "NativeAlertForm.ShowRed",
    "NativeAlertForm.ShowYellow",
    "SaveProtectionSettings",
    "UnblockAllAsync",
    "RebuildBaselineAsync",
    "FECHAR PAINEL (PROTEÇÃO CONTINUA)",
    "native_panel_errors.log"
)) {
    Assert-ContainsLiteral `
        -Text $panelText `
        -Marker $marker `
        -ErrorMessage "AdvancedPanelForm.cs perdeu recurso: $marker"
}

$projectText = Get-Content $project -Raw
if ($projectText.Contains('Resources\*.ps1')) {
    throw "csproj voltou a embutir Panel.ps1 via wildcard."
}

Assert-ContainsLiteral `
    -Text $projectText `
    -Marker 'Resources\GuardCommands.ps1' `
    -ErrorMessage 'GuardCommands.ps1 não está embutido no executável.'

Write-Host "PASS self-test de marcadores literais"
Write-Host "PASS arquivos obrigatórios"
Write-Host "PASS versão consistente: $version"
Write-Host "PASS GuardCore e auto-recuperação"
Write-Host "PASS painel avançado nativo .NET 8"
Write-Host "PASS alertas de teste nativos"
Write-Host "PASS Panel.ps1 legado excluído do runtime"
