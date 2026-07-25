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
    """AdminTask.createSIBJMSActivationSpec('server1(cells/cell01/nodes/nd1/servers/server1|server.xml)', '[-name QL.PLATAFORMA.CREDITO.AS -jndiName as/QL.PLATAFORMA.CREDITO.AS -destinationJndiName queue/QL.PLATAFORMA.CREDITO -connectionFactoryLookup WSMQCREDQueueConnectionFactory -description -busName meubus -clientId -durableSubscriptionHome nd1.server1-meubus -destinationType javax.jms.Queue -messageSelector -acknowledgeMode Auto-acknowledge -subscriptionName -maxBatchSize 1 -maxConcurrency 10 -subscriptionDurability NonDurable -shareDurableSubscriptions InCluster -authenticationAlias -readAhead Default -target -targetType BusMember -targetSignificance Preferred -targetTransportChain -providerEndPoints -shareDataSourceWithCMP false -consumerDoesNotModifyPayloadAfterGet false -forwarderDoesNotModifyPayloadAfterSet false -alwaysActivateAllMDBs false -retryInterval 30 -autoStopSequentialMessageFailure 0 -failingMessageDelay 0]')""",
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
