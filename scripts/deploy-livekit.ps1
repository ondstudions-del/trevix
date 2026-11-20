# Sube LiveKit (Alpha 2.4) a producción vía TUS.
param(
    [string]$TusBase = '',
    [string]$Auth = '',
    [string]$Rest = ''
)

$ErrorActionPreference = 'Stop'
$base = Split-Path $PSScriptRoot -Parent
if ($TusBase -eq '' -or $Auth -eq '' -or $Rest -eq '') {
    Write-Host 'Uso: .\scripts\deploy-livekit.ps1 -TusBase "https://srv....hstgr.io/rest/.../api/tus/public_html" -Auth "eyJ..." -Rest "hash-id"'
    exit 1
}

$files = @(
    '_migrate_042.php',
    'admin/livekit.php',
    'app/Api/Controllers/AppController.php',
    'app/Api/Controllers/LiveKitController.php',
    'app/Api/routes.php',
    'app/Controllers/Admin/AdminController.php',
    'app/Controllers/Admin/LiveKitController.php',
    'app/Controllers/Admin/WalletController.php',
    'app/Core/Config.php',
    'app/Models/AppSetting.php',
    'app/Models/LiveSession.php',
    'app/Services/LiveKitNotify.php',
    'app/Services/LiveKitService.php',
    'app/Services/LiveKitSettings.php',
    'app/Services/LiveKitToken.php',
    'app/Views/admin/livekit.php',
    'config/app.php',
    'database/migrations/042_livekit.sql'
)

foreach ($rel in $files) {
    $local = Join-Path $base ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $local)) { throw "Falta $local" }
    $size = (Get-Item -LiteralPath $local).Length
    $url = "$TusBase/$rel`?override=true"
    $create = (& curl.exe -s -i -X POST $url -H "X-Auth: $Auth" -H "X-Auth-Rest: $Rest" -H 'Tus-Resumable: 1.0.0' -H "Upload-Length: $size" -H 'Upload-Offset: 0' | Out-String)
    if ($create -notmatch '201 Created') { throw "TUS create failed for $rel`n$create" }
    $patch = (& curl.exe -s -i -X PATCH $url -H "X-Auth: $Auth" -H "X-Auth-Rest: $Rest" -H 'Tus-Resumable: 1.0.0' -H 'Content-Type: application/offset+octet-stream' -H 'Upload-Offset: 0' --data-binary "@$local" | Out-String)
    if ($patch -notmatch '204 No Content') { throw "TUS patch failed for $rel`n$patch" }
    Write-Host "OK $rel ($size bytes)"
}

Write-Host ''
Write-Host 'Migración: https://trevix.ond-s.com/_migrate_042.php?t=cl042-5b1f0a39bb915c88d53d0c6d76de3f20280b717cc782c9718f03d56d1a57858c'
Write-Host 'Panel: Admin > LiveKit (URL wss, API Key, Secret).'