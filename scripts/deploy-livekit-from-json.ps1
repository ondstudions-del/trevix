# Lee credenciales TUS desde JSON (no commitear el JSON).
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
    '_migrate_042.php', 'admin/livekit.php',
    'app/Api/Controllers/AppController.php', 'app/Api/Controllers/LiveKitController.php', 'app/Api/routes.php',
    'app/Controllers/Admin/AdminController.php', 'app/Controllers/Admin/LiveKitController.php',
    'app/Core/Config.php', 'app/Core/ErrorHandler.php',
    'app/Helpers/functions.php', 'app/Models/AppSetting.php', 'app/Models/LiveSession.php',
    'app/Services/LiveKitNotify.php', 'app/Services/LiveKitService.php', 'app/Services/LiveKitSettings.php', 'app/Services/LiveKitToken.php',
    'app/Views/admin/livekit.php', 'config/app.php', 'database/migrations/042_livekit.sql'
)
foreach ($rel in $rels) {
    $path = Join-Path $root ($rel -replace '/', '\')
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
Write-Host 'DONE ond-s trevix'