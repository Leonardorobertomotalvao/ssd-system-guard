#requires -Version 5.1
$ErrorActionPreference = 'Stop'

Write-Host ("Validation host: {0} {1} / Edition={2}" -f
    $PSVersionTable.PSVersion,
    $PSVersionTable.PSVersion.Major,
    $PSVersionTable.PSEdition)

# Embedded resources are executed by Windows PowerShell 5.1 in production.
# Do not validate them only with pwsh / PowerShell 7.
if (
    $PSVersionTable.PSVersion.Major -ne 5 -or
    $PSVersionTable.PSEdition -ne 'Desktop'
) {
    throw (
        "This validation must run under Windows PowerShell 5.1 Desktop. " +
        "Current host: $($PSVersionTable.PSVersion) / " +
        "$($PSVersionTable.PSEdition)"
    )
}

$resourceRoot = Join-Path $PSScriptRoot '..\src\SSDSystemGuard\Resources'
$files = Get-ChildItem -Path $resourceRoot -Filter '*.ps1' -File
$failure = $false

foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if (@($parseErrors).Count -gt 0) {
        $failure = $true

        foreach ($err in $parseErrors) {
            Write-Host (
                "FAIL {0}: {1} @ line {2}, column {3}" -f
                $file.Name,
                $err.Message,
                $err.Extent.StartLineNumber,
                $err.Extent.StartColumnNumber
            )
        }
    }
    else {
        Write-Host "PASS $($file.Name)"
    }
}

if ($failure) {
    throw 'Windows PowerShell 5.1 syntax validation failed.'
}

Write-Host 'All embedded PowerShell resources are valid for Windows PowerShell 5.1.'
