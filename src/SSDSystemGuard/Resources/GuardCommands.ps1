#requires -Version 5.1
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("UnblockAll","RebuildBaseline")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

$Base = Join-Path $env:ProgramData "SSDSystemGuard"
$Data = Join-Path $Base "Data"

try {
    $SidKey = [System.Security.Principal.WindowsIdentity]::GetCurrent().
        User.Value.Replace("-","_")
}
catch {
    $SidKey = "unknown"
}

$StatePath = Join-Path $Data ("state-" + $SidKey + ".json")

function Read-State {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }

    return Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 |
        ConvertFrom-Json
}

function Save-State {
    param($State)

    $State |
        ConvertTo-Json -Depth 15 |
        Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Remove-GuardAcl {
    param(
        [string]$Path,
        [string]$Identity
    )

    if (
        [string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path)
    ) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        $Identity =
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    }

    try {
        $acl = Get-Acl -LiteralPath $Path
        $changed = $false

        foreach ($rule in @($acl.Access)) {
            if (
                $rule.IdentityReference.Value -eq $Identity -and
                $rule.AccessControlType -eq
                    [System.Security.AccessControl.AccessControlType]::Deny
            ) {
                [void]$acl.RemoveAccessRuleSpecific($rule)
                $changed = $true
            }
        }

        if ($changed) {
            Set-Acl -LiteralPath $Path -AclObject $acl
        }
    }
    catch {}
}

function Unblock-StatePaths {
    param($State)

    if ($null -eq $State) {
        return
    }

    foreach ($item in @($State.BlockedPaths)) {
        if ($null -eq $item) {
            continue
        }

        $path = [string]$item.Path
        $identity = ""

        if ($null -ne $item.PSObject.Properties["Identity"]) {
            $identity = [string]$item.Identity
        }

        Remove-GuardAcl -Path $path -Identity $identity
    }

    $State.BlockedPaths = @()
}

try {
    $state = Read-State

    if ($null -eq $state) {
        exit 0
    }

    Unblock-StatePaths -State $state

    if ($Action -eq "RebuildBaseline") {
        $state.Initialized = $false
        $state.SteamBaselineAppIds = @()
        $state.EpicBaselineLocations = @()
        $state.LastBaseline = $null
    }

    Save-State -State $state
    exit 0
}
catch {
    try {
        New-Item -ItemType Directory -Path $Data -Force | Out-Null
        Add-Content `
            -LiteralPath (Join-Path $Data "commands_errors.log") `
            -Value ("[{0}] {1}" -f `
                (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
                $_.Exception.ToString()) `
            -Encoding UTF8
    }
    catch {}

    exit 1
}
