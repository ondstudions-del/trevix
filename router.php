<?php
declare(strict_types=1);

/*
 * Router para el servidor integrado de PHP (solo desarrollo), que no lee .htaccess.
 * Uso:  php -S localhost:8000 router.php
 * Replica las restricciones de Apache: carpetas internas, archivos ocultos y scripts en uploads/.
 */

$path = rawurldecode((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH));

$forbidden = preg_match('#^/(app|config|database|storage|docs)(/|$)#i', $path)
    || preg_match('#/\.(?!well-known/)#', $path)
    || preg_match('#\.(sql|md|log|ini|env|lock|example|sh|bak|dist)$#i', $path)
    || preg_match('#^/router\.php$#i', $path)
    || (preg_match('#^/uploads/#i', $path) && !preg_match('#\.(jpe?g|png|webp|gif|mp4|webm|mov|mp3|m4a|wav)$#i', $path));

if ($forbidden) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo '403 · Acceso denegado';
    return true;
}

if (preg_match('#^/api/v1(/|$)#', $path)) {
    require __DIR__ . '/api/v1/index.php';
    return true;
}

if (preg_match('#^/(\.well-known/)?apple-app-site-association$#', $path)) {
    require __DIR__ . '/app-site-association.php';
    return true;
}

if ($path === '/.well-known/assetlinks.json') {
    require __DIR__ . '/asset-links.php';
    return true;
}

$file = __DIR__ . $path;

if ($path !== '/' && is_file($file)) {
    return false;
}

if (is_dir($file) && is_file(rtrim($file, '/') . '/index.php')) {
    return false;
}

if ($path === '/') {
    return false;
}

http_response_code(404);
require __DIR__ . '/app/bootstrap.php';
\Trevix\Core\Response::abort(404, 'La página que buscas no existe o fue movida.');
