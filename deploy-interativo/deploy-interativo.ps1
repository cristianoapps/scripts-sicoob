param(
    [string]$Distro,
    [switch]$RunTests
)

$USUARIO = "cristiano"
$SENHA_UBUNTU = "12345"
$TEMPO_ESPERA = 20
$COMPOSE_DIR = "/opt/docker_was/was9-desenv-envioriment/websphere-backoffice"
$COMPOSE_FILE = "linux.docker-compose.yml"
$PROJETO = "C:\ambiente\integracao-credito-legado"
$ORIGEM = "$PROJETO\integracao-credito-legado-ear\target"
$CONTAINER_NAME = "websphere-backoffice_websphere-backoffice-was9_1"

function Run-WslSudoBash([string]$script) {
    $pipe = "echo '$global:SENHA_UBUNTU' | sudo -S bash -c '$script'"
    wsl -d $global:SISTEMA_OPERACIONAL -- bash -c "$pipe"
}

Clear-Host
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "    DEPLOY INTERATIVO - WSL + WAS" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $Distro) {
    Write-Host "Detectando distros WSL em execucao..." -ForegroundColor Yellow
    Write-Host ""

    $distros = @()
    $linhas = wsl -l -v
    $i = 1
    foreach ($linha in $linhas) {
        $linha = $linha -replace "`0", ""
        if ($linha -match '^\*?\s*(.+?)\s+(Running)\s+') {
            $nome = $matches[1]
            $distros += @{ Id = $i; Nome = $nome }
            Write-Host "  [$i] $nome" -ForegroundColor White
            $i++
        }
    }

    if ($distros.Count -eq 0) {
        Write-Host "Nenhuma distro WSL em execucao encontrada." -ForegroundColor Yellow
        $global:SISTEMA_OPERACIONAL = "Ubuntu-22.04"
        Write-Host "Usando fallback: $global:SISTEMA_OPERACIONAL" -ForegroundColor Gray
    } elseif ($distros.Count -eq 1) {
        $global:SISTEMA_OPERACIONAL = $distros[0].Nome
        Write-Host ""
        Write-Host "Apenas uma distro encontrada. Usando $global:SISTEMA_OPERACIONAL..." -ForegroundColor Green
    } else {
        Write-Host ""
        $escolha = Read-Host "Escolha o numero da distro onde o servidor esta"
        $sel = $distros | Where-Object { $_.Id -eq [int]$escolha }
        if ($sel) {
            $global:SISTEMA_OPERACIONAL = $sel.Nome
        } else {
            $global:SISTEMA_OPERACIONAL = $distros[0].Nome
            Write-Host "Opcao invalida. Usando $global:SISTEMA_OPERACIONAL..." -ForegroundColor Yellow
        }
    }
} else {
    $global:SISTEMA_OPERACIONAL = $Distro
    Write-Host "Distro informada: $global:SISTEMA_OPERACIONAL" -ForegroundColor Green
}
Write-Host ""

$WSL_PATH = "wsl.localhost\$SISTEMA_OPERACIONAL\home\$USUARIO\sicoob-linux-environment\GitLab\was9-desenv-envioriment"
$DEPLOY_PATH = "\\$WSL_PATH\deploy"
$LOGS_PATH = "\\$WSL_PATH\logs\was\server1"

if (-not $RunTests -and -not $PSBoundParameters.ContainsKey('RunTests')) {
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "Testes" -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    $resp = Read-Host "Deseja rodar os testes antes (padrao N)? (S/N)"
    $RunTests = ($resp -eq "S" -or $resp -eq "s")
}

if ($RunTests) {
    Write-Host ""
    Write-Host "Executando testes..." -ForegroundColor Yellow
    Push-Location $PROJETO
    mvn test
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO: Falha nos testes." -ForegroundColor Red
        Pop-Location
        pause
        exit 1
    }
    Pop-Location
} else {
    Write-Host "Pulando testes." -ForegroundColor Gray
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Parando todas as distros WSL..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
wsl --shutdown
Write-Host "Aguardando 5 segundos..." -ForegroundColor Gray
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Reiniciando containers Podman..." -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Run-WslSudoBash "cd $COMPOSE_DIR && podman-compose -f $COMPOSE_FILE down && podman-compose -f $COMPOSE_FILE up -d && podman stop $CONTAINER_NAME && podman start $CONTAINER_NAME"
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
} else {
    Write-Host "ERRO ao copiar o EAR." -ForegroundColor Red
    pause
    exit 1
}
pause