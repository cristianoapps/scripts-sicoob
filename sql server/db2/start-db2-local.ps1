param(
    [ValidateSet('Start', 'Stop')]
    [string]$Action = 'Start'
)

$ErrorActionPreference = 'Stop'

# Distribuicao WSL que hospeda o container. Troque aqui quando necessario.
$WslDistro = 'Ubuntu-Podman-Testes'
$ContainerName = 'db2-community'
$CreationScript = Join-Path $PSScriptRoot 'cria-banco-db2-podman.ps1'

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
Write-Host "Acao: $Action"

# Usa podman ou docker, o que estiver disponivel na distro.
$engine = Invoke-WslBash 'if command -v podman >/dev/null 2>&1; then echo podman; elif command -v docker >/dev/null 2>&1; then echo docker; else echo nenhum; fi'
$engine = ($engine | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 1)
if ($engine -eq 'nenhum') {
    throw "Nenhum motor de contêineres (podman/docker) encontrado na distro WSL $WslDistro."
}

Write-Host "Motor de contêineres: $engine"

if ($Action -eq 'Stop') {
    Write-Host "Parando container $ContainerName..."
    Invoke-WslBash "$engine stop $ContainerName" | ForEach-Object { Write-Host $_ }
    Write-Host "Container $ContainerName parado."
    exit 0
}

$checkCommand = @'
ENGINE='__ENGINE__'
NAME='__NAME__'
if "$ENGINE" inspect "$NAME" >/dev/null 2>&1; then
    echo 'existe'
else
    echo 'nao-existe'
fi
'@
$checkCommand = $checkCommand.Replace('__ENGINE__', $engine).Replace('__NAME__', $ContainerName)
$containerExists = (Invoke-WslBash $checkCommand | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 1)

if ($containerExists -eq 'existe') {
    Write-Host "Container $ContainerName existe. Iniciando..."
    Invoke-WslBash "$engine start $ContainerName" | ForEach-Object { Write-Host $_ }
    $status = Invoke-WslBash "$engine ps --filter name=$ContainerName --format '{{.Names}}: {{.Status}}'"
    $status | ForEach-Object { Write-Host $_ }
    Write-Host "Container $ContainerName iniciado."
}
else {
    Write-Host "Container $ContainerName nao existe. Criando banco Db2..."
    if (-not (Test-Path -LiteralPath $CreationScript)) {
        throw "Script de criacao nao encontrado: $CreationScript"
    }
    & $CreationScript
    Write-Host "Banco Db2 criado na distro $WslDistro."
}
