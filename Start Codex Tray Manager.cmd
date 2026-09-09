@echo off
start "" pwsh.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0CodexTrayManager.ps1"
exit /b 0
