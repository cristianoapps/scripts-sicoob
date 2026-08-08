<#
.SYNOPSIS
    Exporta a estrutura completa (DDL, sem dados) de um banco SQL Server.

.DESCRIPTION
    Usa SMO (Microsoft.SqlServer.Management.Smo) para gerar um arquivo .sql
    com todos os objetos do banco: tipos definidos pelo usuário, tabelas,
    índices, constraints, triggers, views, stored procedures, funções,
    sequences e synonyms, já na ordem correta de dependências.

.PARAMETER Servidor
    Nome, IP ou instância do SQL Server (ex.: "localhost", "SRV\INSTANCIA", "10.0.0.1,1433").

.PARAMETER Banco
    Nome do banco de dados.

.PARAMETER Usuario
    Login de autenticação do SQL Server. Se omitido, usa autenticação do Windows.

.PARAMETER Senha
    Senha do login. Se omitida, será solicitada de forma segura (somente com -Usuario).

.PARAMETER DiretorioSaida
    Pasta onde o arquivo .sql será salvo. Padrão: C:\scripts\sqlserver

.EXAMPLE
    .\Exportar-EstruturaSqlServer.ps1 -Servidor "localhost" -Banco "Credito"

.EXAMPLE
    .\Exportar-EstruturaSqlServer.ps1 -Servidor "SRV\DEV" -Banco "Credito" -Usuario "sa" -Senha "12345"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Servidor,

    [Parameter(Mandatory = $true)]
    [string]$Banco,

    [Parameter(Mandatory = $false)]
    [string]$Usuario,

    [Parameter(Mandatory = $false)]
    [string]$Senha,

    [Parameter(Mandatory = $false)]
    [string]$DiretorioSaida = "C:\scripts\sqlserver"
)

$ErrorActionPreference = 'Stop'

function Instalar-ModuloSqlServer {
    Write-Host "Modulo SqlServer nao encontrado. Instalando..."

    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -ErrorAction Stop
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-Module -Name SqlServer -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "Modulo SqlServer instalado com sucesso."
    } catch {
        throw "Nao foi possivel instalar o modulo SqlServer. Erro: $($_.Exception.Message)"
    }
}

function Carregar-Smo {
    if (Get-Module -ListAvailable -Name SqlServer) {
        Import-Module SqlServer -ErrorAction Stop
        Write-Host "Módulo SqlServer carregado."
        return
    }

    Instalar-ModuloSqlServer
    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        throw "Falha ao carregar o modulo SqlServer apos a instalacao."
    }
    Import-Module SqlServer -ErrorAction Stop
    Write-Host "Módulo SqlServer instalado e carregado."
    return

    $padroes = @(
        "C:\Program Files (x86)\Microsoft SQL Server\*\Tools\Binn\SMO\Microsoft.SqlServer.Management.Smo.dll",
        "C:\Program Files\Microsoft SQL Server\*\Tools\Binn\SMO\Microsoft.SqlServer.Management.Smo.dll"
    )

    $smoDll = $padroes |
        ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } |
        Sort-Object -Property FullName -Descending |
        Select-Object -First 1

    if (-not $smoDll) {
        throw "SMO nao encontrado. Instale o modulo SqlServer: Install-Module -Name SqlServer -Scope CurrentUser -Force"
    }

    Add-Type -Path $smoDll.FullName
    Get-ChildItem -Path $smoDll.DirectoryName -Filter "Microsoft.SqlServer.Management.*.dll" |
        ForEach-Object {
            try { Add-Type -Path $_.FullName } catch { }
        }
    Write-Host "SMO carregado de: $($smoDll.FullName)"
}

try {
    Carregar-Smo

    $srv = New-Object Microsoft.SqlServer.Management.Smo.Server($Servidor)
    $conn = $srv.ConnectionContext
    $conn.ConnectTimeout = 30

    $usarAutenticacaoWindows = [string]::IsNullOrWhiteSpace($Usuario)
    $conn.LoginSecure = $usarAutenticacaoWindows

    if (-not $usarAutenticacaoWindows) {
        $conn.Login = $Usuario
        if ([string]::IsNullOrWhiteSpace($Senha)) {
            $conn.SecurePassword = Read-Host "Senha do usuario '$Usuario'" -AsSecureString
        } else {
            $conn.Password = $Senha
        }
    }

    Write-Host "Conectando ao servidor '$Servidor'..."
    $db = $srv.Databases[$Banco]
    if (-not $db) {
        $basesEncontradas = $srv.Databases | Where-Object { -not $_.IsSystemObject } | ForEach-Object { $_.Name }
        $mensagem = "Banco '$Banco' nao encontrado no servidor '$Servidor'."
        if ($basesEncontradas.Count -gt 0) {
            $mensagem += "`nBancos de dados encontrados no servidor:`n" + ($basesEncontradas -join "`n")
        }
        throw $mensagem
    }
    Write-Host "Conectado ao banco '$Banco'."

    $options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
    $options.ScriptData = $false
    $options.ScriptSchema = $true
    $options.IncludeHeaders = $false
    $options.SchemaQualify = $true
    $options.AnsiFile = $true
    $options.Indexes = $true
    $options.Triggers = $true
    $options.DriAll = $false
    $options.DriAllConstraints = $true
    $options.DriChecks = $true
    $options.DriDefaults = $true
    $options.DriForeignKeys = $true
    $options.DriIndexes = $false
    $options.DriPrimaryKey = $true
    $options.DriUniqueKeys = $true
    $options.ExtendedProperties = $true
    $options.NoFileGroup = $false

    $objetos = New-Object System.Collections.Generic.List[Microsoft.SqlServer.Management.Smo.SqlSmoObject]

    Write-Host "Coletando objetos do banco '$Banco'..."

    $colecoes = @(
        @{ Nome = "Tipos definidos pelo usuario"; Itens = $db.UserDefinedDataTypes },
        @{ Nome = "Tipos CLR"; Itens = $db.UserDefinedTypes },
        @{ Nome = "Tabelas"; Itens = $db.Tables },
        @{ Nome = "Views"; Itens = $db.Views },
        @{ Nome = "Stored Procedures"; Itens = $db.StoredProcedures },
        @{ Nome = "Funcoes"; Itens = $db.UserDefinedFunctions },
        @{ Nome = "Agregados"; Itens = $db.Aggregates },
        @{ Nome = "Sequences"; Itens = $db.Sequences },
        @{ Nome = "Synonyms"; Itens = $db.Synonyms }
    )

    foreach ($colecao in $colecoes) {
        $quantidade = 0
        Write-Host "  Enumerando $($colecao.Nome)..." -NoNewline
        $inicioColecao = Get-Date
        foreach ($item in $colecao.Itens) {
            $ehSistema = $item.PSObject.Properties['IsSystemObject']
            if (-not $ehSistema -or -not $item.IsSystemObject) {
                $objetos.Add($item)
                $quantidade++
            }
        }
        $duracaoColecao = (Get-Date) - $inicioColecao
        Write-Host " $quantidade objetos em $([math]::Round($duracaoColecao.TotalSeconds, 1))s"
    }

    Write-Host "Total de objetos coletados: $($objetos.Count)"

    $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($srv)
    $scripter.Options = $options

    $urnCollection = New-Object Microsoft.SqlServer.Management.Smo.UrnCollection
    foreach ($obj in $objetos) {
        try {
            $urnCollection.Add($obj.Urn)
        } catch {
            Write-Warning "Nao foi possivel incluir o objeto: $($obj.Name). Erro: $($_.Exception.Message)"
        }
    }

    Write-Host "Gerando scripts de $($urnCollection.Count) objetos (pode demorar em bancos grandes)..."
    $inicioScript = Get-Date
    $resultado = $scripter.Script($urnCollection)
    $duracaoScript = (Get-Date) - $inicioScript
    Write-Host "Scripts gerados em $([math]::Round($duracaoScript.TotalSeconds, 1)) segundos."

    if (-not (Test-Path -LiteralPath $DiretorioSaida)) {
        New-Item -ItemType Directory -Path $DiretorioSaida -Force | Out-Null
    }

    $dataArquivo = Get-Date -Format "yyyyMMdd_HHmmss"
    $arquivoSaida = Join-Path $DiretorioSaida "$($Banco)_estrutura_$dataArquivo.sql"

    $linhas = New-Object System.Collections.Generic.List[string]
    $linhas.Add("-- ============================================================")
    $linhas.Add("-- ESTRUTURA DO BANCO: $Banco")
    $linhas.Add("-- SERVIDOR: $Servidor")
    $linhas.Add("-- GERADO EM: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    $linhas.Add("-- CONTEUDO: DDL completo, SEM dados")
    $linhas.Add("-- ============================================================")
    $linhas.Add("USE [$Banco];")
    $linhas.Add("GO")
    $linhas.Add("")
    foreach ($linha in $resultado) {
        $linhas.Add($linha)
    }

    [System.IO.File]::WriteAllLines($arquivoSaida, $linhas, [System.Text.Encoding]::UTF8)

    $tamanhoKb = [math]::Round((Get-Item $arquivoSaida).Length / 1KB, 2)
    Write-Host ""
    Write-Host "Arquivo gerado: $arquivoSaida"
    Write-Host "Tamanho: $tamanhoKb KB"
} catch {
    $ex = $_.Exception
    $detalhe = New-Object System.Collections.Generic.List[string]
    while ($ex) {
        if (-not [string]::IsNullOrWhiteSpace($ex.Message)) {
            $detalhe.Add($ex.Message)
        }
        $ex = $ex.InnerException
    }
    Write-Error "Falha na exportacao: $($detalhe -join " -> ")"
    Write-Host ""
    Write-Host "Dicas para resolver:" -ForegroundColor Yellow
    Write-Host "  - Confira usuario e senha (autenticacao SQL)." -ForegroundColor Yellow
    Write-Host "  - Verifique se o servidor permite autenticacao SQL (ex.: o 'sa' pode estar desabilitado)." -ForegroundColor Yellow
    Write-Host "  - Confira o nome/IP da instancia e a porta (ex.: 'HOST,1433' ou 'HOST\INSTANCIA')." -ForegroundColor Yellow
    Write-Host "  - Teste a conexao com: sqlcmd -S SERV -U USUARIO -P SENHA -d master -Q \"SELECT 1\"" -ForegroundColor Yellow
    exit 1
}
