@echo off
chcp 65001 >nul
title TWDS Traffic Boom
echo ========================================
echo TWDS Traffic Boom Launcher
echo ========================================
echo.

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Run the PowerShell script with Bypass execution policy
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%Traffic-Boom-Windows-Version.ps1" %*

echo.
echo ========================================
echo Script has ended. Press any key to close.
pause >nul
