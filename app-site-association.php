<?php
declare(strict_types=1);

/*
 * /.well-known/apple-app-site-association (reescrito en .htaccess).
 * Solo se publica con el Team ID de Apple configurado (app.ios.team_id); sin él no hay app firmada a la que asociar el dominio.
 */
require __DIR__ . '/app/bootstrap.php';

use Trevix\Core\Config;

$ios = (array) Config::get('app.ios', []);
$team = (string) ($ios['team_id'] ?? '');
$bundle = (string) ($ios['bundle_id'] ?? '');

if (!preg_match('/^[A-Z0-9]{10}$/', $team) || $bundle === '') {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Universal Links no configurados.';
    exit;
}

$components = array_map(
    static fn (string $page): array => ['/' => '/' . $page],
    array_values(array_filter((array) ($ios['pages'] ?? []), 'is_string'))
);

header('Content-Type: application/json');
header('Cache-Control: public, max-age=3600');
echo json_encode([
    'applinks' => [
        'details' => [[
            'appIDs'     => [$team . '.' . $bundle],
            'components' => $components,
        ]],
    ],
], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
