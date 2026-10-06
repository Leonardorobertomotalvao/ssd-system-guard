$ErrorActionPreference = "Stop"

$Project = Join-Path $PSScriptRoot "..\src\SSDSystemGuard\SSDSystemGuard.csproj"
$Out = Join-Path $PSScriptRoot "..\dist\win-x64"

dotnet restore $Project
dotnet publish $Project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o $Out `
    /p:PublishSingleFile=true `
    /p:IncludeNativeLibrariesForSelfExtract=true `
    /p:DebugType=None `
    /p:DebugSymbols=false

Write-Host ""
Write-Host "Build pronto em:" -ForegroundColor Green
Write-Host $Out
