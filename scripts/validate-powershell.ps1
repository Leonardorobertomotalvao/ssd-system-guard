#requires -Version 5.1
$ErrorActionPreference = 'Stop'

Write-Host ("Validation host: {0} / Edition={1}" -f
    $PSVersionTable.PSVersion,
    $PSVersionTable.PSEdition)

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

# Explicit runtime scripts only.
# Panel.ps1 is intentionally NOT part of the v1.2.1 runtime.
$names = @(
    'GuardCore.ps1',
    'GuardCommands.ps1',
    'Install.ps1',
    'Uninstall.ps1'
)

$failure = $false

foreach ($name in $names) {
    $path = Join-Path $resourceRoot $name

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "FAIL missing $name"
        $failure = $true
        continue
    }

    $tokens = $null
    $parseErrors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if (@($parseErrors).Count -gt 0) {
        $failure = $true

        foreach ($err in $parseErrors) {
            Write-Host (
                "FAIL {0}: {1} @ line {2}, column {3}" -f
                $name,
                $err.Message,
                $err.Extent.StartLineNumber,
                $err.Extent.StartColumnNumber
            )
        }
    }
    else {
        Write-Host "PASS $name"
    }
}

if ($failure) {
    throw 'Windows PowerShell 5.1 runtime-script validation failed.'
}

Write-Host 'PASS legacy Panel.ps1 excluded from runtime validation.'
