<?php
declare(strict_types=1);

/*
 * /.well-known/assetlinks.json (reescrito en .htaccess): Android verifica con este archivo que la app firmada con
 * estas huellas puede abrir los enlaces https de este dominio (App Links).
 */
require __DIR__ . '/app/bootstrap.php';

use Trevix\Core\Config;

$android = (array) Config::get('app.android', []);
$package = (string) ($android['package'] ?? '');
$prints = array_values(array_filter(
    (array) ($android['sha256'] ?? []),
    static fn ($p): bool => is_string($p) && preg_match('/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/', $p) === 1
));

header('Content-Type: application/json');
header('Cache-Control: public, max-age=3600');
if ($package === '' || $prints === []) {
    echo '[]';
    exit;
}
echo json_encode([[
    'relation' => ['delegate_permission/common.handle_all_urls'],
    'target'   => ['namespace' => 'android_app', 'package_name' => $package, 'sha256_cert_fingerprints' => $prints],
]], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
