@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-db2-local.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Processo finalizado com codigo %EXIT_CODE%.
pause
endlocal & exit /b %EXIT_CODE%
