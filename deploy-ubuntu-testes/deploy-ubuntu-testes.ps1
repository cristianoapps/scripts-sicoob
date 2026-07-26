param(
    [string]$Distro = "Ubuntu-Podman-Testes"
)

$USUARIO = "cristiano"
$SENHA_UBUNTU = "12345"
$TEMPO_ESPERA = 20
$COMPOSE_DIR = "/opt/docker_was/was9-desenv-envioriment/websphere-backoffice"
$COMPOSE_FILE = "linux.docker-compose.yml"
$PROJETO = "C:\ambiente\integracao-credito-legado"
$ORIGEM = "$PROJETO\integracao-credito-legado-ear\target"
$CONTAINER_NAME = "websphere-backoffice_websphere-backoffice-was9_1"
$SISTEMA_OPERACIONAL = $Distro

function Run-WslSudoBash([string]$script) {
    $pipe = "echo '$SENHA_UBUNTU' | sudo -S bash -c '$script'"
    wsl -d $SISTEMA_OPERACIONAL -- bash -c "$pipe"
}

function ContainerExists([string]$name) {
    $result = wsl -d $SISTEMA_OPERACIONAL -- bash -c "echo '$SENHA_UBUNTU' | sudo -S podman ps -a -q --filter name=$name 2>/dev/null"
    return [bool]$result
}

$WSL_PATH = "wsl.localhost\$SISTEMA_OPERACIONAL\home\$USUARIO\sicoob-linux-environment\GitLab\was9-desenv-envioriment"
$DEPLOY_PATH = "\\$WSL_PATH\deploy"
$LOGS_PATH = "\\$WSL_PATH\logs\was\server1"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Parando todas as distros WSL..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
wsl --shutdown
Write-Host "Aguardando 5 segundos..." -ForegroundColor Gray
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Iniciando containers Podman..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

if (ContainerExists $CONTAINER_NAME) {
    Write-Host "Container ja existe. Apenas restartando..." -ForegroundColor Yellow
    Run-WslSudoBash "podman stop $CONTAINER_NAME && podman start $CONTAINER_NAME"
} else {
    Write-Host "Container nao encontrado. Criando..." -ForegroundColor Yellow
    Run-WslSudoBash "cd $COMPOSE_DIR && podman-compose -f $COMPOSE_FILE up -d && podman stop $CONTAINER_NAME && podman start $CONTAINER_NAME"
}
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERRO ao reiniciar os containers." -ForegroundColor Red
    pause
    exit 1
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Gerando novo EAR com Maven (paralelo a subida do servidor)..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

Push-Location $PROJETO
mvn clean install -DskipTests
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: Falha ao compilar o projeto com Maven." -ForegroundColor Red
    Pop-Location
    pause
    exit 1
}
Pop-Location

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Procurando ultimo arquivo EAR gerado..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

$ears = Get-ChildItem -Path "$ORIGEM\*.ear" | Sort-Object LastWriteTime -Descending
if (-not $ears) {
    Write-Host "ERRO: Nenhum arquivo .ear encontrado em:" -ForegroundColor Red
    Write-Host $ORIGEM -ForegroundColor Red
    pause
    exit 1
}
$ear = $ears[0].FullName
Write-Host "Encontrado:" -ForegroundColor Green
Write-Host $ear -ForegroundColor White
Write-Host ""

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Removendo EARs antigos..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Remove-Item -Path "$DEPLOY_PATH\*.ear" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Limpando logs para nova execucao..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

if (Test-Path "$LOGS_PATH\SystemOut.log") {
    & cmd /c "type nul > `"$LOGS_PATH\SystemOut.log`""
    Write-Host "SystemOut.log limpo." -ForegroundColor Green
}
if (Test-Path "$LOGS_PATH\SystemErr.log") {
    & cmd /c "type nul > `"$LOGS_PATH\SystemErr.log`""
    Write-Host "SystemErr.log limpo." -ForegroundColor Green
}

Write-Host ""
Write-Host "Aguardando $TEMPO_ESPERA segundos antes de copiar o novo EAR..." -ForegroundColor Yellow
Write-Host ""
Start-Sleep -Seconds $TEMPO_ESPERA

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Copiando novo EAR..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Copy-Item -Path $ear -Destination $DEPLOY_PATH -Force
if ($?) {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "DEPLOY FINALIZADO COM SUCESSO" -ForegroundColor Green
    Write-Host "===========================================" -ForegroundColor Green

    Write-Host ""
    Write-Host "Acompanhando log do WebSphere (Ctrl+C para sair)..." -ForegroundColor Yellow
    Write-Host ""
    Start-Sleep -Seconds 2
    $logLinux = "/home/$USUARIO/sicoob-linux-environment/GitLab/was9-desenv-envioriment/logs/was/server1/SystemOut.log"
    wsl -d $SISTEMA_OPERACIONAL -- bash -c "tail -f '$logLinux'"
} else {
    Write-Host "ERRO ao copiar o EAR." -ForegroundColor Red
    pause
    exit 1
}
pause
