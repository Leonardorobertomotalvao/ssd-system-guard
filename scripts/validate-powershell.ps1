# Validate the embedded PowerShell 5.1 resources in GitHub Actions.
$ErrorActionPreference = 'Stop'
$files = Get-ChildItem -Path (Join-Path $PSScriptRoot '../src/SSDSystemGuard/Resources') -Filter '*.ps1' -File
$failure = $false
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        $failure = $true
        foreach ($err in $parseErrors) { Write-Host "$($file.Name): $($err.Message) @ $($err.Extent.StartLineNumber)" }
    } else {
        Write-Host "PASS $($file.Name)"
    }
}
if ($failure) { throw 'PowerShell syntax validation failed.' }
