$ErrorActionPreference = "Stop"

$Exe = Join-Path $PSScriptRoot "..\dist\win-x64\SSDSystemGuard.exe"

if (-not (Test-Path $Exe)) {
    throw "Build não encontrado. Execute scripts\build.ps1 primeiro."
}

Write-Host "Arquivo encontrado:" -ForegroundColor Green
Get-Item $Exe | Select-Object FullName,Length,LastWriteTime

Write-Host ""
Write-Host "SHA256:" -ForegroundColor Cyan
Get-FileHash $Exe -Algorithm SHA256
