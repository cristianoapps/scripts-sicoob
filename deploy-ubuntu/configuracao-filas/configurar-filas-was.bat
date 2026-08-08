@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =====================================================
REM CONFIGURACOES
REM =====================================================
set "SISTEMA_OPERACIONAL=Ubuntu-22.04"
set "USUARIO=cristiano"
set "SENHA_UBUNTU=12345"

set "CONTAINER_NAME=websphere-backoffice_websphere-backoffice-was9_1"
set "COMPOSE_DIR=/opt/docker_was/was9-desenv-envioriment/websphere-backoffice"
set "COMPOSE_FILE=linux.docker-compose.yml"

set "JYTHON_SCRIPT=%~dp0configurar-filas-was.py"
set "WSL_PATH=/tmp/configurar-filas-was.py"

echo ==============================================
echo   CONFIGURADOR DE FILAS - WAS
echo   Projeto: integracao-credito-legado
echo ==============================================
echo WSL Distro  : %SISTEMA_OPERACIONAL%
echo Container   : %CONTAINER_NAME%
echo.

echo [1/4] Copiando script Jython para o WSL...
wsl -d %SISTEMA_OPERACIONAL% -- bash -c "cat > %WSL_PATH%" < "%JYTHON_SCRIPT%"
if errorlevel 1 (
    echo ERRO ao copiar script para o WSL.
    pause
    exit /b 1
)
echo   OK: %WSL_PATH%

echo.
echo [2/4] Verificando se o container esta rodando...

wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S podman ps --format '{{.Names}}' 2>/dev/null | grep -x '%CONTAINER_NAME%' >/dev/null"
if errorlevel 1 (
    echo   Container parado. Iniciando via podman-compose...
    wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S bash -c 'cd %COMPOSE_DIR% && podman-compose -f %COMPOSE_FILE% up -d'"
    echo   Aguardando container iniciar...
    timeout /t 15 /nobreak >nul
)
echo   OK: Container rodando.

echo.
echo [3/4] Copiando script para o container...
wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S podman cp %WSL_PATH% %CONTAINER_NAME%:/tmp/configurar-filas-was.py 2>&1"
if errorlevel 1 (
    for /f "delims=" %%c in ('wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S podman ps --format '{{.Names}}' 2>/dev/null"') do (
        set "WAS_NAMES=!WAS_NAMES! %%c"
    )
    echo   Containers disponiveis:!WAS_NAMES!
    set /p "CONTAINER_NAME=  Nome do container: "
    wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S podman cp %WSL_PATH% !CONTAINER_NAME!:/tmp/configurar-filas-was.py 2>&1"
    if errorlevel 1 (
        echo ERRO ao copiar para o container.
        pause
        exit /b 1
    )
)
echo   OK: %CONTAINER_NAME%:/tmp/configurar-filas-was.py

echo.
echo [4/4] Executando wsadmin.sh...
echo   (pode levar alguns minutos)
echo.

wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S podman exec %CONTAINER_NAME% /bin/bash -c 'cd /opt/IBM/WAS/WebSphere/AppServer/profiles/AppSrv01/bin && ./wsadmin.sh -lang jython -f /tmp/configurar-filas-was.py'"

echo.
echo ==============================================
echo   RESULTADO DA EXECUCAO
echo ==============================================
echo Comando executado. Verifique as mensagens acima.
echo.

set /p "RESTART=Deseja reiniciar o container? (S/N): "
if /i "!RESTART!"=="S" (
    echo Reiniciando container via podman-compose...
    wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' | sudo -S bash -c 'cd %COMPOSE_DIR% && podman-compose -f %COMPOSE_FILE% down && podman-compose -f %COMPOSE_FILE% up -d && podman stop \$(podman ps -q) && podman start \$(podman ps -a -q)'"
    echo Container reiniciado! (aguarde ~2-3 min)
) else (
    echo Para reiniciar manualmente:
    echo   wsl -d %SISTEMA_OPERACIONAL% -- bash -c "echo '%SENHA_UBUNTU%' ^| sudo -S bash -c 'cd %COMPOSE_DIR% ^&^& podman-compose -f %COMPOSE_FILE% down ^&^& podman-compose -f %COMPOSE_FILE% up -d'"
)

echo.
echo ==============================================
echo   PROCESSO FINALIZADO
echo ==============================================
pause