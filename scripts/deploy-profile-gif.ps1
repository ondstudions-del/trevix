# GIF en foto/portada de perfil (ImageUpload).
param([string]$SecretsFile = "$env:TEMP\trevix-deploy\tus-onds-trevix-fresh.json")
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $SecretsFile)) { throw "Falta $SecretsFile" }
$cfg = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json
$root = Split-Path $PSScriptRoot -Parent
$base = [string]$cfg.tus_base
$prefix = if ($cfg.prefix) { [string]$cfg.prefix } else { '' }
$auth = [string]$cfg.auth.Trim()
$rest = [string]$cfg.rest.Trim()
$h = @('-H', "X-Auth: $auth", '-H', "X-Auth-Rest: $rest", '-H', 'Tus-Resumable: 1.0.0')
$rel = 'app/Services/ImageUpload.php'
$path = Join-Path $root ($rel -replace '/', '\')
$len = (Get-Item -LiteralPath $path).Length
$enc = [uri]::EscapeDataString($prefix + $rel).Replace('%2F', '/')
$url = if ($base -match 'public_html(/trevix)?$' -or $base -match '/tus$') { "$base/$enc`?override=true" } else { "$base/tus/$enc`?override=true" }
$c1 = (curl.exe -s -o NUL -w '%{http_code}' -X POST @h -H "Upload-Length: $len" -H 'Upload-Offset: 0' $url).Trim()
$c2 = (curl.exe -s -o NUL -w '%{http_code}' -X PATCH @h -H 'Upload-Offset: 0' -H 'Content-Type: application/offset+octet-stream' --data-binary "@$path" $url).Trim()
if ($c1 -ne '201' -or $c2 -ne '204') { throw "FALLO $rel $c1/$c2" }
Write-Host "OK $rel"