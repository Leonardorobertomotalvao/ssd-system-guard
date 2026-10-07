#requires -Version 5.1
$ErrorActionPreference = "Stop"

function Assert-ContainsLiteral {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Marker,
        [Parameter(Mandatory=$true)][string]$ErrorMessage
    )

    if (-not $Text.Contains($Marker)) {
        throw $ErrorMessage
    }
}

$selfTestText = 'alpha [pscustomobject] $StopFlag omega'

Assert-ContainsLiteral `
    -Text $selfTestText `
    -Marker '[pscustomobject]' `
    -ErrorMessage 'quality-check self-test failed for brackets.'

Assert-ContainsLiteral `
    -Text $selfTestText `
    -Marker '$StopFlag' `
    -ErrorMessage 'quality-check self-test failed for dollar-sign literal.'

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "src\SSDSystemGuard"
$resources = Join-Path $src "Resources"
$project = Join-Path $src "SSDSystemGuard.csproj"

$required = @(
    $project,
    (Join-Path $src "Program.cs"),
    (Join-Path $src "BackgroundHost.cs"),
    (Join-Path $src "GuardManager.cs"),
    (Join-Path $src "GuardPaths.cs"),
    (Join-Path $src "ResourceInstaller.cs"),
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

if ($version -ne "1.2.1") {
    throw "Versão esperada 1.2.1; encontrada: $version"
}

$programText = Get-Content (Join-Path $src "Program.cs") -Raw
$hostText = Get-Content (Join-Path $src "BackgroundHost.cs") -Raw
$managerText = Get-Content (Join-Path $src "GuardManager.cs") -Raw
$installerText = Get-Content (Join-Path $src "ResourceInstaller.cs") -Raw
$panelText = Get-Content (Join-Path $src "AdvancedPanelForm.cs") -Raw
$projectText = Get-Content $project -Raw
$installText = Get-Content (Join-Path $resources "Install.ps1") -Raw

Assert-ContainsLiteral `
    -Text $programText `
    -Marker 'Application.Run(new AdvancedPanelForm())' `
    -ErrorMessage 'Program.cs não abre o painel nativo.'

if ($programText.Contains("RunPanel(")) {
    throw "Program.cs voltou a usar host PowerShell para painel."
}

if ($hostText.Contains("RunPanel(")) {
    throw "BackgroundHost.cs voltou a expor painel PowerShell."
}

Assert-ContainsLiteral `
    -Text $managerText `
    -Marker 'Environment.ProcessPath' `
    -ErrorMessage 'OpenPanel não está usando o EXE atual.'

Assert-ContainsLiteral `
    -Text $managerText `
    -Marker 'SaveProtectionSettings' `
    -ErrorMessage 'GuardManager perdeu SaveProtectionSettings.'

foreach ($marker in @(
    "NativeAlertForm.ShowRed",
    "NativeAlertForm.ShowYellow",
    "Painel: .NET 8 nativo",
    "native_panel_errors.log"
)) {
    Assert-ContainsLiteral `
        -Text $panelText `
        -Marker $marker `
        -ErrorMessage "Painel nativo perdeu marcador: $marker"
}

if ($installerText.Contains('"Panel.ps1"')) {
    throw "ResourceInstaller voltou a extrair Panel.ps1."
}

Assert-ContainsLiteral `
    -Text $installerText `
    -Marker '"GuardCommands.ps1"' `
    -ErrorMessage 'ResourceInstaller não inclui GuardCommands.ps1.'

if ($projectText.Contains('Resources\*.ps1')) {
    throw "csproj voltou a embutir todos os scripts por wildcard."
}

foreach ($marker in @(
    'Resources\GuardCore.ps1',
    'Resources\GuardCommands.ps1',
    'Resources\Install.ps1',
    'Resources\Uninstall.ps1'
)) {
    Assert-ContainsLiteral `
        -Text $projectText `
        -Marker $marker `
        -ErrorMessage "csproj perdeu recurso: $marker"
}

foreach ($marker in @(
    "GuardCommands.ps1",
    "*SSDSystemGuard*Panel.ps1*",
    'Remove-Item (Join-Path $Base "Panel.ps1")',
    'Version="1.2.1"'
)) {
    Assert-ContainsLiteral `
        -Text $installText `
        -Marker $marker `
        -ErrorMessage "Install.ps1 perdeu migração: $marker"
}

Write-Host "PASS self-test de literais"
Write-Host "PASS versão 1.2.1"
Write-Host "PASS painel 100% nativo .NET 8"
Write-Host "PASS host PowerShell não possui RunPanel"
Write-Host "PASS EXE atual abre o painel"
Write-Host "PASS Panel.ps1 excluído do ResourceInstaller/csproj"
Write-Host "PASS instalador mata e remove painel PowerShell legado"
