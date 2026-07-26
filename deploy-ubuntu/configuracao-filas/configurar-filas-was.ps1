<#
.SYNOPSIS
    Configura filas JMS do projeto integracao-credito-legado no WebSphere via wsadmin.sh
.DESCRIPTION
    Conecta no container Podman do WAS via WSL e executa comandos Jython para criar
    os recursos JMS necessarios: bus SIB, filas (QL.PLATAFORMA.CREDITO e
    QL.SICOR.REQ.BANCOOB.01), connection factory, activation spec.
.PARAMETER WSLDistro
    Nome da distribuicao WSL (default: Ubuntu-22.04)
.PARAMETER ContainerName
    Nome do container Podman do WAS (default: websphere-backoffice_websphere-backoffice-was9_1)
.PARAMETER RestartContainer
    Switch para reiniciar o container apos a configuracao
.PARAMETER SkipBusCreation
    Switch para pular a criacao do bus (se ja existir)
.EXAMPLE
    .\configurar-filas-was.ps1 -RestartContainer
#>

param(
    [string]$WSLDistro = "Ubuntu-22.04",
    [string]$ContainerName = "websphere-backoffice_websphere-backoffice-was9_1",
    [switch]$RestartContainer,
    [switch]$SkipBusCreation
)

$ErrorActionPreference = "Stop"
$PODMAN = "sudo podman"
$WSLScriptPath = "/tmp/configurar-filas-was.py"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  CONFIGURADOR DE FILAS - WAS                " -ForegroundColor Cyan
Write-Host "  Projeto: integracao-credito-legado         " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "WSL Distro  : $WSLDistro"
Write-Host "Container   : $ContainerName"
Write-Host ""

Write-Host "[1/4] Gerando script Jython..." -ForegroundColor Yellow

$jythonScript = @"
import sys

def executar(comando, descricao):
    try:
        print ">>> " + descricao
        resultado = eval(comando)
        print "OK: " + str(resultado)
        return True
    except Exception as e:
        print "ERRO: " + str(e)
        return False

print "=========================================="
print "  CONFIGURACAO DE FILAS DO PROJETO        "
print "  integracao-credito-legado               "
print "=========================================="

"@

if (-not $SkipBusCreation) {
    $jythonScript += @"

print ""
print "--- PASSO 2: Criando bus SIB ---"
executar(
    """AdminTask.createSIBus("[-bus meubus -busSecurity false -scriptCompatibility 6.1 ]")""",
    "Criar bus 'meubus'"
)
executar(
    """AdminTask.addSIBusMember("[-bus meubus -node nd1 -server server1 -fileStore -logSize 100 -minPermanentStoreSize 200 -maxPermanentStoreSize 500 -unlimitedPermanentStoreSize false -minTemporaryStoreSize 200 -maxTemporaryStoreSize 500 -unlimitedTemporaryStoreSize false ]")""",
    "Adicionar membro ao bus"
)

"@
} else {
    $jythonScript += @"

print ""
print "--- PASSO 2: SKIP - Criacao do bus ignorada ---"

"@
}

$jythonScript += @"

print ""
print "--- PASSO 3: Destinos SIB (QP.QL.*) ---"
destinos = [
    ("QP.QL.PLATAFORMA.CREDITO", "Fila principal de processamento de credito"),
    ("QP.QL.SICOR.REQ.BANCOOB.01", "Fila de envio para SICOR"),
]

for nome, desc in destinos:
    executar(
        """AdminTask.createSIBDestination("[-bus meubus -name %s -type Queue -reliability ASSURED_PERSISTENT -description -node nd1 -server server1 ]")""" % nome,
        "Criar destino: %s (%s)" % (nome, desc)
    )

print ""
print "--- PASSO 4: Connection Factory ---"
# Nome padrao do projeto: WSMQCREDQueueConnectionFactory (sem java:/)
executar(
    """AdminTask.createSIBJMSConnectionFactory('server1(cells/cell01/nodes/nd1/servers/server1|server.xml)','[-type queue -name WSMQCREDQueueConnectionFactory -jndiName WSMQCREDQueueConnectionFactory -description -category -busName meubus -nonPersistentMapping ExpressNonPersistent -readAhead Default -tempQueueNamePrefix -target -targetType BusMember -targetSignificance Preferred -targetTransportChain -providerEndPoints -connectionProximity Bus -authDataAlias -containerAuthAlias -mappingAlias -shareDataSourceWithCMP false -logMissingTransactionContext false -manageCachedHandles false -xaRecoveryAuthAlias -persistentMapping ReliablePersistent -consumerDoesNotModifyPayloadAfterGet false -producerDoesNotModifyPayloadAfterSet false]')""",
    "Criar CF: WSMQCREDQueueConnectionFactory (JNDI: WSMQCREDQueueConnectionFactory)"
)

print ""
print "--- PASSO 5: Filas JMS (QL.*) ---"
queue_template = """AdminTask.createSIBJMSQueue('server1(cells/cell01/nodes/nd1/servers/server1|server.xml)', '[-name %s -jndiName queue/%s -description -deliveryMode Application -readAhead AsConnection -busName meubus -queueName QP.QL.%s -scopeToLocalQP false -producerBind false -producerPreferLocal true -gatherMessages false]')"""

filas = [
    ("QL.PLATAFORMA.CREDITO", "QL.PLATAFORMA.CREDITO", "PLATAFORMA.CREDITO"),
    ("QL.SICOR.REQ.BANCOOB.01", "QL.SICOR.REQ.BANCOOB.01", "SICOR.REQ.BANCOOB.01"),
]

for nome, jndi, queue in filas:
    executar(
        queue_template % (nome, jndi, queue),
        "Criar fila JMS: %s" % nome
    )

print ""
print "--- PASSO 6: Activation Spec ---"
executar(
    """AdminTask.createSIBJMSActivationSpec('server1(cells/cell01/nodes/nd1/servers/server1|server.xml)', '[-name QL.PLATAFORMA.CREDITO.AS -jndiName as/QL.PLATAFORMA.CREDITO.AS -destinationJndiName queue/QL.PLATAFORMA.CREDITO -connectionFactoryLookup -description -busName meubus -clientId -durableSubscriptionHome nd1.server1-meubus -destinationType javax.jms.Queue -messageSelector -acknowledgeMode Auto-acknowledge -subscriptionName -maxBatchSize 1 -maxConcurrency 10 -subscriptionDurability NonDurable -shareDurableSubscriptions InCluster -authenticationAlias -readAhead Default -target -targetType BusMember -targetSignificance Preferred -targetTransportChain -providerEndPoints -shareDataSourceWithCMP false -consumerDoesNotModifyPayloadAfterGet false -forwarderDoesNotModifyPayloadAfterSet false -alwaysActivateAllMDBs false -retryInterval 30 -autoStopSequentialMessageFailure 0 -failingMessageDelay 0]')""",
    "Criar ActivationSpec: as/QL.PLATAFORMA.CREDITO.AS"
)

print ""
print "--- PASSO 7: Salvando configuracoes ---"
try:
    AdminConfig.save()
    print "OK: Configuracoes salvas com sucesso!"
except Exception as e:
    print "ERRO: Falha ao salvar configuracoes: " + str(e)

print ""
print "=========================================="
print "  CONFIGURACAO FINALIZADA!                "
print "=========================================="

"@

Write-Host "  Script Jython gerado com sucesso!" -ForegroundColor Green

Write-Host "[2/4] Copiando script para o WSL ($WSLDistro)..." -ForegroundColor Yellow
$jythonScript | wsl -d $WSLDistro -- bash -c "cat > $WSLScriptPath"

if ($LASTEXITCODE -ne 0) {
    $tempFile = Join-Path $env:TEMP "configurar-filas-was.py"
    Set-Content -Path $tempFile -Value $jythonScript -Encoding ASCII
    wsl -d $WSLDistro -- bash -c "cp '/mnt/c/Users/$env:USERNAME/AppData/Local/Temp/configurar-filas-was.py' $WSLScriptPath"
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "Falha ao copiar script para o WSL" }
}

Write-Host "  Script copiado para WSL: $WSLScriptPath" -ForegroundColor Green

Write-Host "[3/4] Copiando script para o container ($ContainerName)..." -ForegroundColor Yellow
$containerResult = wsl -d $WSLDistro -- bash -c "$PODMAN cp $WSLScriptPath ${ContainerName}:/tmp/configurar-filas-was.py 2>&1"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  AVISO: $containerResult" -ForegroundColor Red
    $containerList = wsl -d $WSLDistro -- bash -c "$PODMAN ps --format '{{.Names}}' 2>/dev/null | grep -i was" 2>&1
    if ($containerList) {
        Write-Host "  Containers WAS encontrados:" -ForegroundColor Cyan
        $containers = $containerList -split "`n" | Where-Object { $_.Trim() -ne "" }
        $i = 0
        foreach ($c in $containers) { Write-Host "    [$i] $c"; $i++ }
        if ($containers.Count -eq 1) { $ContainerName = $containers[0].Trim() }
        else { $choice = Read-Host "  Selecione o numero do container (0-$($containers.Count-1))"; $ContainerName = $containers[[int]$choice].Trim() }
        $containerResult = wsl -d $WSLDistro -- bash -c "$PODMAN cp $WSLScriptPath ${ContainerName}:/tmp/configurar-filas-was.py 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "Falha ao copiar: $containerResult" }
    } else {
        throw "Nenhum container WAS encontrado. Execute 'sudo podman start' primeiro."
    }
}
Write-Host "  OK: ${ContainerName}:/tmp/configurar-filas-was.py" -ForegroundColor Green

Write-Host "[4/4] Executando wsadmin.sh..." -ForegroundColor Yellow
Write-Host "  (pode levar alguns minutos)" -ForegroundColor Gray
Write-Host ""

$wsadminResult = wsl -d $WSLDistro -- bash -c "$PODMAN exec $ContainerName /bin/bash -c 'cd /opt/IBM/WAS/WebSphere/AppServer/profiles/AppSrv01/bin && ./wsadmin.sh -lang jython -f /tmp/configurar-filas-was.py' 2>&1"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  RESULTADO DA EXECUCAO                      " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "$wsadminResult"
Write-Host ""

$shouldRestart = $RestartContainer
if (-not $shouldRestart) {
    $response = Read-Host "Deseja reiniciar o container WAS? (S/N)"
    $shouldRestart = ($response -eq "S" -or $response -eq "s")
}
if ($shouldRestart) {
    Write-Host "Reiniciando container $ContainerName..." -ForegroundColor Yellow
    $restartResult = wsl -d $WSLDistro -- bash -c "$PODMAN restart $ContainerName 2>&1"
    Write-Host "  $restartResult" -ForegroundColor Green
    Write-Host "Container reiniciado! (aguarde ~2-3 min)" -ForegroundColor Cyan
} else {
    Write-Host "Nao esqueca de reiniciar:" -ForegroundColor Yellow
    Write-Host "  wsl -d $WSLDistro -- sudo podman restart $ContainerName" -ForegroundColor White
}
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  PROCESSO FINALIZADO                         " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
