@echo off
if not exist "%LOCALAPPDATA%\claude-notify" mkdir "%LOCALAPPDATA%\claude-notify" >nul 2>nul
more > "%LOCALAPPDATA%\claude-notify\payload.json"
start "" /min powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-notify.ps1" -PayloadFile "%LOCALAPPDATA%\claude-notify\payload.json"
exit /b 0
