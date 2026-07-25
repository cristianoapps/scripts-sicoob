@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =====================================================
REM CONFIGURACOES
REM =====================================================
set "SISTEMA_OPERACIONAL=Ubuntu-22.04"
set "USUARIO=cristiano"
set "SENHA_UBUNTU=12345"
set "TEMPO_ESPERA=20"

set "COMPOSE_DIR=/opt/docker_was/was9-desenv-envioriment/websphere-backoffice"
set "COMPOSE_FILE=linux.docker-compose.yml"

set "PROJETO=C:\ambiente\integracao-credito-legado"
set "ORIGEM=%PROJETO%\integracao-credito-legado-ear\target"
set "WSL_PATH=wsl.localhost\%SISTEMA_OPERACIONAL%\home\%USUARIO%\sicoob-linux-environment\GitLab\was9-desenv-envioriment"
set "DEPLOY=\\%WSL_PATH%\deploy"
set "LOGS=\\%WSL_PATH%\logs\was\server1"

echo.
echo ===========================================
echo Reiniciando containers Podman...
echo ===========================================

wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S bash -c 'cd %COMPOSE_DIR% && podman-compose -f %COMPOSE_FILE% down && podman-compose -f %COMPOSE_FILE% up -d && podman stop \$(podman ps -q) && podman start \$(podman ps -a -q)'"
if errorlevel 1 (
    echo.
    echo ERRO ao reiniciar os containers.
    pause
    exit /b 1
)

echo.
echo ===========================================
echo Gerando novo EAR com Maven (paralelo a subida do servidor)...
echo ===========================================

pushd "%PROJETO%"
call mvn clean install -DskipTests
if errorlevel 1 (
    echo ERRO: Falha ao compilar o projeto com Maven.
    popd
    pause
    exit /b 1
)
popd

echo.
echo ===========================================
echo Procurando ultimo arquivo EAR gerado...
echo ===========================================

set "EAR="

for /f "delims=" %%F in ('dir "%ORIGEM%\*.ear" /O-D /B 2^>nul') do (
    set "EAR=%ORIGEM%\%%F"
    goto :ear_encontrado
)

:ear_encontrado

if not defined EAR (
    echo ERRO: Nenhum arquivo .ear encontrado em:
    echo %ORIGEM%
    pause
    exit /b 1
)

echo Encontrado:
echo !EAR!
echo.

echo ===========================================
echo Removendo EARs antigos...
echo ===========================================

del /q "%DEPLOY%\*.ear" 2>nul

echo.
echo ===========================================
echo Limpando logs para nova execucao...
echo ===========================================

if exist "%LOGS%\SystemOut.log" (
    type nul > "%LOGS%\SystemOut.log"
    echo SystemOut.log limpo.
)

if exist "%LOGS%\SystemErr.log" (
    type nul > "%LOGS%\SystemErr.log"
    echo SystemErr.log limpo.
)

echo.
echo Aguardando %TEMPO_ESPERA% segundos antes de copiar o novo EAR...
echo.
timeout /t %TEMPO_ESPERA% /nobreak >nul

echo.
echo ===========================================
echo Copiando novo EAR...
echo ===========================================

copy /Y "!EAR!" "%DEPLOY%"

if errorlevel 1 (
    echo ERRO ao copiar o EAR.
    pause
    exit /b 1
)

echo.
echo ===========================================
echo DEPLOY FINALIZADO COM SUCESSO
echo ===========================================
pause