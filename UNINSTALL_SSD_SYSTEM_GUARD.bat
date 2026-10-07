@echo off
setlocal EnableExtensions
chcp 65001 >nul
title SSD System Guard - Desinstalador
set "PS=%ProgramData%\SSDSystemGuard\Uninstall.ps1"
if not exist "%PS%" (
    echo SSD System Guard nao encontrado em ProgramData.
    echo Nenhuma alteracao foi feita.
    pause
    exit /b 2
)
choice /C SN /N /M "Desinstalar SSD System Guard deste PC? [S/N]: "
if errorlevel 2 exit /b 0
net session >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%PS%"
echo.
if errorlevel 1 (
    echo Nao foi possivel concluir; revise o log.
) else (
    echo Verifique a remocao completa do Guard.
)
pause
