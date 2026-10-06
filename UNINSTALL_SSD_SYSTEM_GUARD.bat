@echo off
setlocal EnableExtensions
chcp 65001 >nul
title SSD System Guard - Desinstalador

:: Elevar para Administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando permissao de Administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo ============================================================
echo   SSD SYSTEM GUARD - DESINSTALADOR
echo ============================================================
echo.
echo Este arquivo remove o SSD System Guard deste computador.
echo.
choice /C SN /N /M "Deseja continuar? [S/N]: "
if errorlevel 2 exit /b 0

set "SELF=%~f0"
set "TMPPS=%TEMP%\SSDGuard_Uninstall_%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$raw=[IO.File]::ReadAllText($env:SELF); $m=[regex]::Match($raw,'(?m)^###_SSDGUARD_UNINSTALL_PS_###\r?\n'); if(-not $m.Success){exit 90}; $payload=$raw.Substring($m.Index+$m.Length); [IO.File]::WriteAllText($env:TMPPS,$payload,(New-Object Text.UTF8Encoding($true)))"

if errorlevel 1 (
    echo.
    echo ERRO: nao foi possivel iniciar o desinstalador.
    pause
    exit /b 90
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%TMPPS%"
set "ERR=%ERRORLEVEL%"

del /f /q "%TMPPS%" >nul 2>&1

echo.
if not "%ERR%"=="0" (
    echo A desinstalacao terminou com erro %ERR%.
    echo.
    pause
    exit /b %ERR%
)

echo.
echo SSD System Guard removido com sucesso.
echo.
pause
exit /b 0

###_SSDGUARD_UNINSTALL_PS_###
$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms

$Base = Join-Path $env:LOCALAPPDATA 'SSDSystemGuard'
$LegacyBase = Join-Path $env:LOCALAPPDATA 'SSDSystemGuardDefinitive'

$InstalledUninstaller = Join-Path $Base 'Uninstall.ps1'

# Se a instalacao possui o desinstalador interno, prefira ele.
if (Test-Path -LiteralPath $InstalledUninstaller) {
    try {
        & powershell.exe `
            -NoProfile `
            -STA `
            -ExecutionPolicy Bypass `
            -File $InstalledUninstaller

        if ($LASTEXITCODE -eq 0) {
            exit 0
        }
    } catch {}
}

# Fallback para instalacao incompleta/corrompida.
function Remove-GuardAclFromState {
    param([string]$Folder)

    $statePath = Join-Path $Folder 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        return
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    } catch {
        return
    }

    foreach ($item in @($state.BlockedPaths)) {
        $p = $null

        if ($item -is [string]) {
            $p = [string]$item
        }
        elseif ($item.PSObject.Properties['Path']) {
            $p = [string]$item.Path
        }

        if (-not $p -or -not (Test-Path -LiteralPath $p)) {
            continue
        }

        try {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $acl = Get-Acl -LiteralPath $p
            $changed = $false

            foreach ($rule in @($acl.Access)) {
                if (
                    $rule.IdentityReference.Value -eq $identity -and
                    $rule.AccessControlType -eq
                        [System.Security.AccessControl.AccessControlType]::Deny
                ) {
                    [void]$acl.RemoveAccessRuleSpecific($rule)
                    $changed = $true
                }
            }

            if ($changed) {
                Set-Acl -LiteralPath $p -AclObject $acl
            }
        } catch {}
    }
}

# Captura a quarentena antes de remover configuracoes.
$quarantine = ''

foreach ($cfgPath in @(
    (Join-Path $Base 'config.json'),
    (Join-Path $LegacyBase 'config.json')
)) {
    if ($quarantine) { break }

    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 |
                ConvertFrom-Json

            $quarantine = [string]$cfg.QuarantinePath
        } catch {}
    }
}

# Encerra apenas processos pertencentes ao Guard.
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            (
                $_.CommandLine -like '*\SSDSystemGuard\GuardCore.ps1*' -or
                $_.CommandLine -like '*\SSDSystemGuard\Panel.ps1*' -or
                $_.CommandLine -like '*\SSDSystemGuardDefinitive\GuardCore.ps1*' -or
                $_.CommandLine -like '*\SSDSystemGuardDefinitive\Panel.ps1*'
            )
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
} catch {}

Remove-GuardAclFromState $Base
Remove-GuardAclFromState $LegacyBase

foreach ($taskName in @(
    'SSD System Guard',
    'SSD System Guard Download Blocker',
    'SSD System Guard Definitivo'
)) {
    try {
        Unregister-ScheduledTask `
            -TaskName $taskName `
            -Confirm:$false `
            -ErrorAction SilentlyContinue
    } catch {}
}

$desktop = [Environment]::GetFolderPath('Desktop')
$startup = [Environment]::GetFolderPath('Startup')

foreach ($shortcut in @(
    (Join-Path $desktop 'SSD System Guard - Painel.lnk'),
    (Join-Path $desktop 'SSD Guard Definitivo - Painel.lnk'),
    (Join-Path $startup 'SSD System Guard - Painel.lnk'),
    (Join-Path $startup 'SSD Guard Definitivo - Painel.lnk')
)) {
    Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
}

foreach ($folder in @($Base, $LegacyBase)) {
    if (Test-Path -LiteralPath $folder) {
        Remove-Item -LiteralPath $folder `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

if ($quarantine -and (Test-Path -LiteralPath $quarantine)) {
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "O SSD System Guard foi removido.`n`nDeseja apagar tambem a quarentena e todos os arquivos dentro dela?`n`n$quarantine",
        'SSD System Guard - Desinstalador',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        Remove-Item -LiteralPath $quarantine `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

[System.Windows.Forms.MessageBox]::Show(
    "SSD System Guard removido com sucesso.`n`nAs tarefas e regras de bloqueio criadas pelo aplicativo foram removidas.",
    'SSD System Guard',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null

exit 0
