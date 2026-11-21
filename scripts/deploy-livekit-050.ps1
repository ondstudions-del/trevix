# Sube LiveKit UX (Alpha 3.0.5) + migración 050 vía TUS.
param([string]$SecretsFile = "$env:TEMP\trevix-deploy\tus-onds-livekit.json")

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SecretsFile)) { throw "Falta $SecretsFile" }
$cfg = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json
$root = Split-Path $PSScriptRoot -Parent
$base = [string]$cfg.tus_base
$auth = [string]$cfg.auth
$rest = [string]$cfg.rest
$h = @('-H', "X-Auth: $auth", '-H', "X-Auth-Rest: $rest", '-H', 'Tus-Resumable: 1.0.0')
$rels = @(
    '_migrate_050.php',
    'database/migrations/050_livekit_live_ux.sql',
    'app/Api/Controllers/LiveKitController.php',
    'app/Api/Controllers/UserController.php',
    'app/Api/Controllers/GiftController.php',
    'app/Api/routes.php',
    'app/Models/LiveSession.php',
    'app/Models/Gift.php',
    'app/Services/LiveKitService.php',
    'app/Services/LiveKitNotify.php',
    'app/Services/GiftService.php'
)
foreach ($rel in $rels) {
    $path = Join-Path $root ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) { throw "Falta $path" }
    $len = (Get-Item -LiteralPath $path).Length
    $enc = [uri]::EscapeDataString($rel).Replace('%2F', '/')
    $url = if ($base -match 'public_html(/trevix)?$' -or $base -match '/tus$') {
        "$base/$enc`?override=true"
    } else {
        "$base/tus/$enc`?override=true"
    }
    $c1 = (curl.exe -s -o NUL -w '%{http_code}' -X POST @h -H "Upload-Length: $len" -H 'Upload-Offset: 0' $url).Trim()
    $c2 = (curl.exe -s -o NUL -w '%{http_code}' -X PATCH @h -H 'Upload-Offset: 0' -H 'Content-Type: application/offset+octet-stream' --data-binary "@$path" $url).Trim()
    if ($c1 -ne '201' -or $c2 -ne '204') { throw "FALLO $rel $c1/$c2" }
    Write-Host "OK $rel"
}
$token = 'cl050-' + [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [Text.Encoding]::UTF8.GetBytes('trevix-livekit-live-ux-050')
    )
).Replace('-', '').ToLowerInvariant()
Write-Host 'DONE'
Write-Host "MIGRATE https://trevix.ond-s.com/_migrate_050.php?t=$token"
