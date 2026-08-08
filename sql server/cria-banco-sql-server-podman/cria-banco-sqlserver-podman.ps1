$ErrorActionPreference = 'Stop'

# Distribuicao WSL que hospeda o Podman.
$WslDistro = 'Ubuntu-Podman-Testes'
$ContainerName = 'sqlserver-2025'
$Image = 'mcr.microsoft.com/mssql/server:2025-CU3-ubuntu-22.04'
$Database = 'BD3219_LOCAL'
$DatabaseCollation = 'SQL_Latin1_General_CP1_CI_AI'
$LoginUser = 'USRGesin2'
$SqlCmd = '/opt/mssql-tools18/bin/sqlcmd'

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

# Credenciais nunca ficam em texto claro no repositorio: sao lidas de variaveis
# de ambiente (MSSQL_SA_PASSWORD e GESIN2_LOGIN_PASSWORD) ou solicitadas com
# prompt seguro no terminal.
$SaPassword = Get-EnvOrPrompt -Name 'MSSQL_SA_PASSWORD' -Prompt 'Senha do usuario SA'
$LoginPassword = Get-EnvOrPrompt -Name 'GESIN2_LOGIN_PASSWORD' -Prompt "Senha do login $LoginUser"

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
SA_PASSWORD='__SA_PASSWORD__'

mkdir -p /var/opt/mssql
chown 10001:10001 /var/opt/mssql 2>/dev/null || true

if podman container exists "$NAME"; then
    if podman inspect "$NAME" --format '{{.State.Running}}' | grep -qx true; then
        echo 'Container SQL Server ja esta em execucao.'
    else
        podman start "$NAME"
    fi
else
    podman run -d --name "$NAME" \
        --network host \
        -e ACCEPT_EULA=Y \
        -e MSSQL_SA_PASSWORD="$SA_PASSWORD" \
        -e MSSQL_PID=Developer \
        -e MSSQL_TCP_PORT=1433 \
        --security-opt seccomp=unconfined \
        -v /var/opt/mssql:/var/opt/mssql \
        "$IMAGE"
fi
'@
$startCommand = $startCommand.Replace('__NAME__', $ContainerName).Replace('__IMAGE__', $Image).Replace('__SA_PASSWORD__', $SaPassword)

Write-Host 'Verificando/iniciando SQL Server...'
Invoke-WslBash $startCommand | ForEach-Object { Write-Host $_ }

$readyCommand = @'
set -e
for attempt in $(seq 1 60); do
    if podman exec '__NAME__' '__SQLCMD__' -S localhost -U sa -P '__SA_PASSWORD__' -C -No -Q 'SELECT 1' >/dev/null 2>&1; then
        exit 0
    fi
    sleep 3
done
podman logs --tail 40 '__NAME__' >&2
exit 1
'@
$readyCommand = $readyCommand.Replace('__NAME__', $ContainerName).Replace('__SQLCMD__', $SqlCmd).Replace('__SA_PASSWORD__', $SaPassword)

Write-Host 'Aguardando SQL Server ficar pronto...'
Invoke-WslBash $readyCommand | ForEach-Object { Write-Host $_ }

$databaseCommand = @'
set -e
SQLCMD='__SQLCMD__'
CONTAINER='__NAME__'
SA_PASSWORD='__SA_PASSWORD__'

podman exec "$CONTAINER" "$SQLCMD" -b -S localhost -U sa -P "$SA_PASSWORD" -C -No -Q "IF DB_ID('__DATABASE__') IS NULL BEGIN CREATE DATABASE [__DATABASE__] COLLATE __COLLATION__; END ELSE IF (SELECT collation_name FROM sys.databases WHERE name = '__DATABASE__') <> '__COLLATION__' BEGIN RAISERROR('A database existente possui collation diferente de __COLLATION__. Recrie a database antes de carregar a estrutura.', 16, 1); RETURN; END"
podman exec "$CONTAINER" "$SQLCMD" -b -S localhost -U sa -P "$SA_PASSWORD" -C -No -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '__LOGIN__') BEGIN CREATE LOGIN [__LOGIN__] WITH PASSWORD = '__LOGIN_PASSWORD__', DEFAULT_DATABASE = [__DATABASE__], CHECK_POLICY = ON; END"
podman exec "$CONTAINER" "$SQLCMD" -b -S localhost -U sa -P "$SA_PASSWORD" -C -No -Q "IF IS_SRVROLEMEMBER('sysadmin', '__LOGIN__') = 0 ALTER SERVER ROLE [sysadmin] ADD MEMBER [__LOGIN__];"
podman exec "$CONTAINER" "$SQLCMD" -b -S localhost -U sa -P "$SA_PASSWORD" -C -No -Q "IF IS_SRVROLEMEMBER('dbcreator', '__LOGIN__') = 0 ALTER SERVER ROLE [dbcreator] ADD MEMBER [__LOGIN__];"
podman exec "$CONTAINER" "$SQLCMD" -b -S localhost -U sa -P "$SA_PASSWORD" -C -No -d '__DATABASE__' -Q "IF IS_SRVROLEMEMBER('sysadmin', '__LOGIN__') = 0 BEGIN IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '__LOGIN__') BEGIN CREATE USER [__LOGIN__] FOR LOGIN [__LOGIN__]; END; IF IS_ROLEMEMBER('db_owner', '__LOGIN__') = 0 ALTER ROLE [db_owner] ADD MEMBER [__LOGIN__]; END"
'@
$databaseCommand = $databaseCommand.Replace('__SQLCMD__', $SqlCmd).Replace('__NAME__', $ContainerName).Replace('__SA_PASSWORD__', $SaPassword).Replace('__DATABASE__', $Database).Replace('__COLLATION__', $DatabaseCollation).Replace('__LOGIN__', $LoginUser).Replace('__LOGIN_PASSWORD__', $LoginPassword)

Write-Host "Garantindo database $Database e login $LoginUser..."
Invoke-WslBash $databaseCommand | ForEach-Object { Write-Host $_ }

Write-Host "SQL Server disponivel na porta 1433/$Database com o usuario $LoginUser."
Write-Host "Obtenha o IP para conexao Windows com: wsl -d $WslDistro -- hostname -I"
Write-Host 'Use o IP atual da distro WSL na conexao; neste ambiente o localhost do Windows nao esta encaminhando o TDS corretamente.'
Write-Host "Collation verificada: $DatabaseCollation."
Write-Host "Permissoes aplicadas: sysadmin no servidor, dbcreator no servidor e db_owner em $Database."
