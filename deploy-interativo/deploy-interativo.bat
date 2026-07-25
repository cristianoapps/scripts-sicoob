@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-interativo.ps1" %*
pause