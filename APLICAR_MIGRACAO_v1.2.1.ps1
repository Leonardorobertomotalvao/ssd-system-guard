$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path (Join-Path $repo "src\SSDSystemGuard\SSDSystemGuard.csproj"))) {
    throw "Execute este script a partir do patch extraído na raiz do repositório."
}

$legacy = Join-Path $repo "src\SSDSystemGuard\Resources\Panel.ps1"

if (Test-Path -LiteralPath $legacy) {
    Remove-Item -LiteralPath $legacy -Force
    Write-Host "REMOVIDO: src\SSDSystemGuard\Resources\Panel.ps1" -ForegroundColor Green
}
else {
    Write-Host "Panel.ps1 legado já não existe no código-fonte." -ForegroundColor Green
}

Write-Host ""
Write-Host "A v1.2.1 usa AdvancedPanelForm.cs (.NET 8)." -ForegroundColor Cyan
Write-Host "Agora execute: git add -A" -ForegroundColor Cyan
