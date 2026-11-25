# Alpha 3.8.5 · OND-ADS multi-superficie + migración 058.
param([string]$SecretsFile = "$env:TEMP\trevix-deploy\tus-onds-alpha-384-fresh.json")
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SecretsFile)) { throw "Falta $SecretsFile" }
$cfg = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json
$root = Split-Path $PSScriptRoot -Parent
$base = [string]$cfg.tus_base
$auth = [string]$cfg.auth
$rest = [string]$cfg.rest
$h = @('-H', "X-Auth: $auth", '-H', "X-Auth-Rest: $rest", '-H', 'Tus-Resumable: 1.0.0')
$rels = @(
    '_migrate_058.php',
    'app/Models/Ad.php',
    'app/Models/User.php',
    'app/Services/AdService.php',
    'app/Services/MediaUpload.php',
    'app/Services/SettingsService.php',
    'app/Api/Present.php',
    'app/Api/routes.php',
    'app/Api/Controllers/AdController.php',
    'app/Api/Controllers/PostController.php',
    'app/Api/Controllers/UserController.php',
    'app/Api/Controllers/StoryController.php',
    'app/Api/Controllers/CommunityController.php',
    'app/Api/Controllers/MeController.php',
    'app/Controllers/FeedController.php'
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
$tok = 'cl058-' + [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('trevix-ond-ads-placements-058'))).Replace('-','').ToLower()
Write-Host "DEPLOY Alpha 3.8.5 OK — migración: https://trevix.ond-s.com/_migrate_058.php?t=$tok"