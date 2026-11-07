<?php
declare(strict_types=1);

namespace Trevix\Api;

use Trevix\Core\ActionError;

/**
 * Enrutador de la API v1. Cada ruta: [método, patrón, [Controlador, método, ...argumentos fijos], acceso];
 * el controlador recibe primero los parámetros del patrón y después los argumentos fijos.
 * Parámetros del patrón: {id} número, {username} usuario, {key} slug o número, {tag} hashtag, {type} palabra.
 * Acceso: guest (sin token), user (token válido), moderator o admin (rol mínimo).
 */
final class Router
{
    private const PARAMS = [
        'id'       => '(\d{1,18})',
        'id2'      => '(\d{1,18})',
        'username' => '([A-Za-z0-9_.]{1,30})',
        'key'      => '([a-z0-9-]{1,60})',
        'tag'      => '([^/]{1,100})',
        'type'     => '([a-z_]{1,20})',
    ];

    /** @return array{handler: list<string>, access: string, params: list<string>} */
    public static function match(string $method, string $path, array $routes): array
    {
        $allowed = [];
        foreach ($routes as [$verb, $pattern, $handler, $access]) {
            $regex = '#^' . preg_replace_callback('/\{(\w+)\}/', static fn (array $m) => self::PARAMS[$m[1]], $pattern) . '$#';
            if (!preg_match($regex, $path, $matches)) {
                continue;
            }
            if ($verb !== $method) {
                $allowed[] = $verb;
                continue;
            }
            return [
                'handler' => $handler,
                'access'  => $access,
                'params'  => array_map('rawurldecode', array_slice($matches, 1)),
            ];
        }
        if ($allowed !== []) {
            header('Allow: ' . implode(', ', array_unique($allowed)));
            throw new ActionError('Método no permitido para esta ruta.', 405);
        }
        throw new ActionError('Esta ruta de la API no existe.', 404);
    }
}
