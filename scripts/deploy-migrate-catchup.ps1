# Sube _migrate_catchup.php + SQL 040-042 a treviix.app (JWT del File Manager en JSON).
param([string]$SecretsFile = "$env:TEMP\trevix-deploy\tus-treviix-livekit.json")

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SecretsFile)) { throw "Falta $SecretsFile (copia JWT desde Hostinger → treviix.app → File Manager)" }
$cfg = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json
$root = Split-Path $PSScriptRoot -Parent
$base = [string]$cfg.tus_base
$auth = [string]$cfg.auth
$rest = [string]$cfg.rest
$h = @('-H', "X-Auth: $auth", '-H', "X-Auth-Rest: $rest", '-H', 'Tus-Resumable: 1.0.0')
$rels = @(
    '_migrate_catchup.php', '_migrate_041.php', '_migrate_041_portable.php', '_migrate_042.php',
    'database/migrations/040_comment_media_paypal.sql',
    'database/migrations/041_profile_photos.sql',
    'database/migrations/042_livekit.sql',
    'app/Core/Config.php', 'app/Core/Auth.php', 'app/Core/ErrorHandler.php',
    'app/Helpers/functions.php',
    'admin/livekit.php',
    'app/Api/Controllers/AppController.php', 'app/Api/Controllers/LiveKitController.php', 'app/Api/routes.php',
    'app/Controllers/Admin/AdminController.php', 'app/Controllers/Admin/LiveKitController.php',
    'app/Models/AppSetting.php', 'app/Models/LiveSession.php',
    'app/Services/LiveKitNotify.php', 'app/Services/LiveKitService.php', 'app/Services/LiveKitSettings.php', 'app/Services/LiveKitToken.php',
    'app/Views/admin/livekit.php',
    'config/app.php'
)
foreach ($rel in $rels) {
    $path = Join-Path $root ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) { throw "Falta $path" }
    $len = (Get-Item -LiteralPath $path).Length
    $enc = [uri]::EscapeDataString($rel).Replace('%2F', '/')
    $url = if ($base -match 'public_html(/trevix)?$' -or $base -match '/tus$') { "$base/$enc`?override=true" } else { "$base/tus/$enc`?override=true" }
    $c1 = (curl.exe -s -o NUL -w '%{http_code}' -X POST @h -H "Upload-Length: $len" -H 'Upload-Offset: 0' $url).Trim()
    $c2 = (curl.exe -s -o NUL -w '%{http_code}' -X PATCH @h -H 'Upload-Offset: 0' -H 'Content-Type: application/offset+octet-stream' --data-binary "@$path" $url).Trim()
    if ($c1 -ne '201' -or $c2 -ne '204') { throw "FALLO $rel $c1/$c2" }
    Write-Host "OK $rel"
}
$token = (php -r "echo 'clcatchup-' . hash('sha256', 'trevix-catchup-040-042');")
Write-Host ''
Write-Host "Migración: https://treviix.app/_migrate_catchup.php?t=$token"