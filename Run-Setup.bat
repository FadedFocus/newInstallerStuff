@echo off
setlocal

set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "SCRIPT=%~dp0Install-Apps.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: Install-Apps.ps1 was not found next to this BAT file.
    pause
    exit /b 1
)

rem Launch the PowerShell backend detached and hidden, then close this CMD window.
start "" "%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT%"
exit /b 0
