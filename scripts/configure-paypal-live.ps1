# (Opcional) Genera config/paypal.credentials.php local y verifica OAuth.
# En producción puedes usar Panel › Monedero › Medios de pago › PayPal (Client ID y Secret).
# Sube credenciales PayPal Live a trevix.ond-s.com y verifica OAuth + paypal.configured.
# Uso: guarda secretos en %TEMP%\trevix-deploy\paypal-live.secrets.json (no commitear):
# {"client_id":"...","secret":"..."}
param(
    [string]$Domain = 'trevix.ond-s.com',
    [string]$SecretsFile = "$env:TEMP\trevix-deploy\paypal-live.secrets.json"
)

$ErrorActionPreference = 'Stop'
$deployDir = "$env:TEMP\trevix-deploy"
$root = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path $SecretsFile)) {
    Write-Error "Falta $SecretsFile. Crea JSON con client_id y secret (Live, app TREVIX)."
}

$raw = Get-Content -LiteralPath $SecretsFile -Raw | ConvertFrom-Json
$cid = [string]$raw.client_id
$sec = [string]$raw.secret
$secretOnly = Join-Path $deployDir 'paypal-live.secret.txt'
if ((Test-Path $secretOnly) -and ([string]$raw.secret).Length -lt 30) {
    $sec = (Get-Content -LiteralPath $secretOnly -Raw).Trim()
}
if ($cid.Length -lt 20 -or $sec.Length -lt 20) {
    Write-Error 'client_id o secret inválidos en el archivo.'
}
if ($cid -eq $sec) {
    Write-Error @'
El "secret" en paypal-live.secrets.json es igual al client_id (copiaste dos veces el Client ID).
En Developer → Live → TREVIX: ojo en "Secret key 1" → copiar.
Opción: guarda solo el Secret en paypal-live.secret.txt (una línea, sin comillas).
'@
}

$credPath = Join-Path $deployDir 'paypal.credentials.php'
$php = @"
<?php
declare(strict_types=1);

return [
    'app' => [
        'paypal' => [
            'client_id' => '$($cid -replace "'","\\'")',
            'secret'    => '$($sec -replace "'","\\'")',
            'mode'      => 'live',
        ],
    ],
];
"@
$php | Set-Content -LiteralPath $credPath -Encoding utf8

$pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${cid}:${sec}"))
$oauth = curl.exe -s -X POST 'https://api-m.paypal.com/v1/oauth2/token' `
    -H "Authorization: Basic $pair" `
    -H 'Content-Type: application/x-www-form-urlencoded' `
    --data 'grant_type=client_credentials'
if ($oauth -notmatch 'access_token') {
    Write-Error "OAuth Live falló. Revisa client_id/secret en Developer (Live + app TREVIX). Respuesta: $oauth"
}
Write-Host 'OAuth Live: OK'

$smokePhp = @"
<?php
declare(strict_types=1);
define('TREVIX_API', true);
require dirname(__DIR__) . '/app/bootstrap.php';
header('Content-Type: text/plain; charset=utf-8');
`$token = 'ppadm-' . hash('sha256', 'trevix-paypal-method-live');
if (!hash_equals(`$token, (string) (`$_GET['t'] ?? ''))) { http_response_code(404); exit('missing'); }
`$pdo = Trevix\Core\Database::connection();
`$row = `$pdo->query("SELECT id FROM payment_methods WHERE provider='paypal' LIMIT 1")->fetch(PDO::FETCH_ASSOC);
if (`$row) {
    `$pdo->exec("UPDATE payment_methods SET name='PayPal', provider='paypal', instructions='Recarga automática con PayPal.', is_active=1 WHERE id=" . (int) `$row['id']);
    echo 'updated id=' . `$row['id'] . "\n";
} else {
    `$pos = (int) `$pdo->query('SELECT COALESCE(MAX(position),0)+1 FROM payment_methods')->fetchColumn();
    `$pdo->exec("INSERT INTO payment_methods (name, provider, instructions, min_amount_cents, is_active, position) VALUES ('PayPal','paypal','Recarga automática con PayPal.', 100, 1, `$pos)");
    echo 'inserted id=' . `$pdo->lastInsertId() . "\n";
}
echo 'paypal.configured: ' . (Trevix\Services\PayPalCheckout::configured() ? 'yes' : 'no') . "\n";
echo 'paypal.mode: ' . (string) Trevix\Core\Config::get('app.paypal.mode', '') . "\n";
@unlink(__FILE__);
"@
$smokePath = Join-Path $root 'api\_paypal_live_smoke.php'
$smokePhp | Set-Content -LiteralPath $smokePath -Encoding utf8NoBOM

Write-Host 'Sube archivos con Hostinger TUS (ejecuta hosting_files_generate-upload-url y upload.ps1) o sube manualmente:'
Write-Host "  config/paypal.credentials.php -> $credPath"
Write-Host "  api/_paypal_live_smoke.php (temporal)"
Write-Host "Luego: https://$Domain/api/_paypal_live_smoke.php?t=ppadm-..."
Write-Host '(El token t es hash de trevix-paypal-method-live)'