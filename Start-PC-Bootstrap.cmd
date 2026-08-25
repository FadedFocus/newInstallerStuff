@echo off
setlocal EnableExtensions
title PC Bootstrap

set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "DOWNLOADED_BOOTSTRAP=%TEMP%\PCBootstrap-Bootstrap.ps1"
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/FadedFocus/newInstallerStuff/main/Bootstrap.ps1"

echo PC Bootstrap
echo ------------
echo Downloading the latest launcher from GitHub...

"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%BOOTSTRAP_URL%' -OutFile (Join-Path $env:TEMP 'PCBootstrap-Bootstrap.ps1')"

if errorlevel 1 (
    echo.
    echo ERROR: The launcher could not be downloaded.
    echo Check the internet connection, then try again.
    pause
    exit /b 1
)

if not exist "%DOWNLOADED_BOOTSTRAP%" (
    echo.
    echo ERROR: The downloaded launcher could not be found.
    pause
    exit /b 1
)

if /I "%~1"=="--download-only" (
    echo The latest launcher was downloaded successfully.
    exit /b 0
)

echo Starting setup...
"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DOWNLOADED_BOOTSTRAP%"
set "SETUP_EXIT_CODE=%ERRORLEVEL%"

if not "%SETUP_EXIT_CODE%"=="0" (
    echo.
    echo ERROR: PC Bootstrap stopped with exit code %SETUP_EXIT_CODE%.
    pause
    exit /b %SETUP_EXIT_CODE%
)

echo PC Bootstrap has started. Approve the administrator prompt when it appears.
timeout /t 3 /nobreak >nul
exit /b 0
