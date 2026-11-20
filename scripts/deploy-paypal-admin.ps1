# Sube el panel PayPal (Medios de pago) a producción vía TUS.
# Renueva X-Auth / X-Auth-Rest desde el File Manager de Hostinger (pestaña del sitio trevix).
param(
    [string]$TusBase = '',
    [string]$Auth = '',
    [string]$Rest = ''
)

$ErrorActionPreference = 'Stop'
$base = Split-Path $PSScriptRoot -Parent
if ($TusBase -eq '' -or $Auth -eq '' -or $Rest -eq '') {
    Write-Host 'Pega TusBase, Auth y Rest (JWT del File Manager). Ejemplo en agent store tus-upload.ps1'
    Write-Host 'Uso: .\scripts\deploy-paypal-admin.ps1 -TusBase "https://.../api/tus/public_html" -Auth "eyJ..." -Rest "hash-id"'
    exit 1
}

$files = @(
    'app/Services/PayPalSettings.php',
    'app/Services/PayPalCheckout.php',
    'app/Models/AppSetting.php',
    'app/Controllers/Admin/WalletController.php',
    'app/Views/admin/wallet.php',
    'app/Services/WalletService.php'
)

foreach ($rel in $files) {
    $local = Join-Path $base ($rel -replace '/', '\')
    $size = (Get-Item -LiteralPath $local).Length
    $url = "$TusBase/$rel`?override=true"
    $create = (& curl.exe -s -i -X POST $url -H "X-Auth: $Auth" -H "X-Auth-Rest: $Rest" -H 'Tus-Resumable: 1.0.0' -H "Upload-Length: $size" -H 'Upload-Offset: 0' | Out-String)
    if ($create -notmatch '201 Created') { throw "TUS create failed for $rel`n$create" }
    $patch = (& curl.exe -s -i -X PATCH $url -H "X-Auth: $Auth" -H "X-Auth-Rest: $Rest" -H 'Tus-Resumable: 1.0.0' -H 'Content-Type: application/offset+octet-stream' -H 'Upload-Offset: 0' --data-binary "@$local" | Out-String)
    if ($patch -notmatch '204 No Content') { throw "TUS patch failed for $rel`n$patch" }
    Write-Host "OK $rel ($size bytes)"
}

Write-Host ''
Write-Host 'Listo. En el panel: Admin > Monedero > Medios de pago > PayPal (Client ID + Secret Live).'
Write-Host 'Añade o edita un medio tipo PayPal (pago automático) y actívalo.'