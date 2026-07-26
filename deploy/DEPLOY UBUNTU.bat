@echo off
setlocal EnableExtensions EnableDelayedExpansion

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "deploy-ubuntu.ps1"
if errorlevel 1 (
    pause
    exit /b 1
)
