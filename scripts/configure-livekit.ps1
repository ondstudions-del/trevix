# Genera config/livekit.credentials.php para subir al servidor (no commitear).
# Uso: JSON en %TEMP%\trevix-deploy\livekit-live.secrets.json
# {"url":"wss://tu-proyecto.livekit.cloud","api_key":"APIxx","api_secret":"secret"}
param(
    [string]$SecretsFile = "$env:TEMP\trevix-deploy\livekit-live.secrets.json"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$deployDir = "$env:TEMP\trevix-deploy"

if (-not (Test-Path $SecretsFile)) {
    Write-Host @"
Crea $SecretsFile con:
{
  "url": "wss://TU-PROYECTO.livekit.cloud",
  "api_key": "API...",
  "api_secret": "..."
}
Desde https://cloud.livekit.io → proyecto → Settings → Keys
"@
    exit 1
}

$raw = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json
$url = [string]$raw.url
$key = [string]$raw.api_key
$sec = [string]$raw.api_secret
if ($url -notmatch '^wss?://' -or $key.Length -lt 6 -or $sec.Length -lt 16) {
    Write-Error 'url, api_key o api_secret inválidos.'
}

$credPath = Join-Path $deployDir 'livekit.credentials.php'
@"

<?php
declare(strict_types=1);

return [
    'app' => [
        'livekit' => [
            'url'        => '$($url -replace "'", "\\'")',
            'api_key'    => '$($key -replace "'", "\\'")',
            'api_secret' => '$($sec -replace "'", "\\'")',
        ],
    ],
];
"@ | Set-Content -LiteralPath $credPath -Encoding UTF8

Copy-Item -LiteralPath $credPath -Destination (Join-Path $root 'config\livekit.credentials.php.example.generated') -Force -ErrorAction SilentlyContinue
Write-Host "Generado: $credPath"
Write-Host 'Sube a config/livekit.credentials.php en el servidor (TUS), no al repo.'