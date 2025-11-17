@echo off
chcp 65001 >nul
title TWDS Traffic Boom (with API)
echo ========================================
echo TWDS Traffic Boom Launcher (with API)
echo ========================================
echo.

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"

REM Set your API endpoint here (replace with your actual Cloudflare Workers URL)
set "API_URL=https://your-worker.your-subdomain.workers.dev"

REM Set custom device name (optional, defaults to computer name)
set "DEVICE_NAME=%COMPUTERNAME%"

echo API Endpoint: %API_URL%
echo Device Name: %DEVICE_NAME%
echo.

REM Run the PowerShell script with Bypass execution policy
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%Traffic-Boom-Windows-Version.ps1" -ApiEndpoint "%API_URL%" -DeviceName "%DEVICE_NAME%"

echo.
echo ========================================
echo Script has ended. Press any key to close.
pause >nul
