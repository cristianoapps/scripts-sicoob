@echo off
rem ============================================================
rem Exporta a estrutura de um banco SQL Server (DDL, sem dados)
rem
rem Edite as variaveis abaixo (SERV, DB, USR, PASS) com as
rem credenciais do seu banco. Depois e so dar dois cliques.
rem
rem Para usar autenticacao do Windows, deixe USR e PASS vazias:
rem   set USR=
rem   set PASS=
rem
rem Para sobrescrever pela linha de comando:
rem   Exportar-Estrutura.bat -Servidor "OUTRO" -Banco "OutroBanco"
rem ============================================================

set SERV=SQLH113
set DB=BD3219_MariaLuiza
set USR=USRGesin2
set PASS=Usr@2Gesin**

cd /d "%~dp0"

if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Exportar-EstruturaSqlServer.ps1" -Servidor "%SERV%" -Banco "%DB%" -Usuario "%USR%" -Senha "%PASS%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Exportar-EstruturaSqlServer.ps1" %*
)

if %errorlevel% neq 0 (
    echo.
    echo Falha na execucao do script. Verifique a mensagem acima.
    pause
)
