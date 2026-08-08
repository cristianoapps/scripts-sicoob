$ErrorActionPreference = 'Stop'

# Distribuicao WSL que hospeda o Podman.
$WslDistro = 'Ubuntu-Podman-Testes'
$ContainerName = 'db2-community'
$Image = 'docker.io/ibmcom/db2:latest'
$Database = 'CRE_TBPL'
$Db2HostPort = '50001'
$Db2ContainerPort = '50000'
$Db2Instance = 'db2inst1'
$LoginUser = 'usrcre'
$InstanceUser = 'db2inst1'

function Get-EnvOrPrompt {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Prompt)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
    }
    $secure = Read-Host -AsSecureString -Prompt $Prompt
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# Credenciais nunca ficam em texto claro no repositorio: sao lidas da variavel
# de ambiente DB2INST1_PASSWORD ou solicitadas com prompt seguro no terminal.
# A mesma senha e usada para o admin da instancia (db2inst1) e para o login usrcre.
$Db2Password = Get-EnvOrPrompt -Name 'DB2INST1_PASSWORD' -Prompt "Senha do usuario $InstanceUser e do login $LoginUser"

function Invoke-WslBash {
    param([Parameter(Mandatory = $true)][string]$Command)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Command)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & wsl.exe --distribution $WslDistro -- bash -lc "echo $encodedCommand | base64 -d | bash" 2>&1
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw (($result | Out-String).Trim())
    }

    return $result
}

Write-Host "WSL: $WslDistro"
Write-Host 'Verificando Podman...'
Invoke-WslBash 'command -v podman >/dev/null'

$startCommand = @'
set -e
NAME='__NAME__'
IMAGE='__IMAGE__'
INSTANCE='__INSTANCE__'
PASSWORD='__PASSWORD__'

mkdir -p /database
chown 10000:10000 /database 2>/dev/null || true

if podman container exists "$NAME"; then
    if podman inspect "$NAME" --format '{{.State.Running}}' | grep -qx true; then
        echo 'Container Db2 ja esta em execucao.'
    else
        podman start "$NAME"
    fi
else
    podman run -d --name "$NAME" \
        --privileged=true \
        --security-opt seccomp=unconfined \
        -p __HOST_PORT__:__CONTAINER_PORT__ \
        -e LICENSE=accept \
        -e DB2INSTANCE="$INSTANCE" \
        -e DB2INST1_PASSWORD="$PASSWORD" \
        -e DBNAME='__DATABASE__' \
        -e AUTOCONFIG=true \
        -e ARCHIVE_LOGS=false \
        -v /database:/database \
        "$IMAGE"
fi
'@
$startCommand = $startCommand.Replace('__NAME__', $ContainerName).Replace('__IMAGE__', $Image).Replace('__INSTANCE__', $InstanceUser).Replace('__PASSWORD__', $Db2Password).Replace('__DATABASE__', $Database).Replace('__HOST_PORT__', $Db2HostPort).Replace('__CONTAINER_PORT__', $Db2ContainerPort)

Write-Host 'Verificando/iniciando Db2...'
Invoke-WslBash $startCommand | ForEach-Object { Write-Host $_ }

$readyCommand = @'
set -e
for attempt in $(seq 1 100); do
    if podman exec '__NAME__' su - '__INSTANCE__' -c "db2 connect to '__DATABASE__'" >/dev/null 2>&1; then
        exit 0
    fi
    sleep 3
done
podman logs --tail 40 '__NAME__' >&2
exit 1
'@
$readyCommand = $readyCommand.Replace('__NAME__', $ContainerName).Replace('__INSTANCE__', $InstanceUser).Replace('__DATABASE__', $Database)

Write-Host 'Aguardando o Db2 ficar pronto (pode levar alguns minutos no primeiro setup)...'
Invoke-WslBash $readyCommand | ForEach-Object { Write-Host $_ }

$databaseCommand = @'
set -e
CONTAINER='__NAME__'
INSTANCE='__INSTANCE__'
DATABASE='__DATABASE__'
PASSWORD='__PASSWORD__'
LOGIN='__LOGIN__'

# Garante a database (o Db2 limita nomes a 8 caracteres; __DATABASE__ ja esta ajustado).
if ! podman exec "$CONTAINER" su - "$INSTANCE" -c "db2 list db directory | grep -q '\b$DATABASE\b'"; then
    podman exec "$CONTAINER" su - "$INSTANCE" -c "db2 CREATE DATABASE $DATABASE USING CODESET UTF-8 TERRITORY US"
    echo "Database $DATABASE criada."
else
    echo "Database $DATABASE ja existe."
fi

# Cria o login (usuario OS no container) e concede acesso a database.
if ! podman exec "$CONTAINER" id "$LOGIN" >/dev/null 2>&1; then
    podman exec "$CONTAINER" bash -c "useradd -m -s /bin/bash $LOGIN"
    echo "Usuario OS $LOGIN criado."
fi
podman exec "$CONTAINER" bash -c "echo '$LOGIN:$PASSWORD' | chpasswd"
podman exec "$CONTAINER" su - "$INSTANCE" -c "db2 connect to $DATABASE; db2 GRANT DBADM ON DATABASE TO USER $LOGIN"
echo "Acesso DBADM em $DATABASE concedido a $LOGIN."
'@
$databaseCommand = $databaseCommand.Replace('__NAME__', $ContainerName).Replace('__INSTANCE__', $InstanceUser).Replace('__DATABASE__', $Database).Replace('__PASSWORD__', $Db2Password).Replace('__LOGIN__', $LoginUser)

Write-Host "Garantindo database $Database e login $LoginUser..."
Invoke-WslBash $databaseCommand | ForEach-Object { Write-Host $_ }

Write-Host "Db2 disponivel na porta $Db2HostPort/$Database com o usuario $LoginUser."
Write-Host "Obtenha o IP para conexao Windows com: wsl -d $WslDistro -- hostname -I"
Write-Host 'Use o IP atual da distro WSL na conexao; neste ambiente o localhost do Windows nao esta encaminhando a porta corretamente.'
Write-Host "Porta configurada: $Db2HostPort (mapeada para 50000 dentro do container)."
Write-Host "Permissoes aplicadas: DBADM em $Database para $LoginUser (admin da instancia: $InstanceUser)."
