<?php
declare(strict_types=1);

namespace Trevix\Api;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Request;
use Trevix\Models\ApiToken;
use Trevix\Models\AppSetting;

/** Punto de entrada de la API v1 (api/v1/index.php): ruta, token, mantenimiento y errores en JSON. */
final class Kernel
{
    /** Token de la petición actual (null en rutas públicas sin token). */
    private static ?array $token = null;

    public static function token(): ?array
    {
        return self::$token;
    }

    public static function run(): never
    {
        header('Cache-Control: no-store');
        header('X-Robots-Tag: noindex');

        try {
            $method = Request::method();
            if ($method === 'OPTIONS') {
                http_response_code(204);
                exit;
            }
            if ($method === 'HEAD') {
                $method = 'GET';
            }

            $route = Router::match($method, self::path(), require APP_PATH . '/Api/routes.php');
            Input::boot($method);
            self::authenticate($route['access']);
            self::maintenance($route['access']);

            [$class, $action] = $route['handler'];
            (new $class())->$action(...$route['params'], ...array_slice($route['handler'], 2));
            Reply::ok();
        } catch (ActionError $e) {
            if ($e->retryAfter !== null) {
                header('Retry-After: ' . max(1, $e->retryAfter));
            }
            Reply::error($e->status, $e->getMessage(), $e->fields);
        } catch (DomainException $e) {
            Reply::error(422, $e->getMessage());
        }
    }

    /** Parte de la ruta tras /api/v1 (funciona también si el sitio vive en una subcarpeta). */
    private static function path(): string
    {
        $uri = (string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH);
        $pos = strpos($uri, '/api/v1');
        $path = $pos === false ? '' : substr($uri, $pos + strlen('/api/v1'));
        $path = (string) preg_replace('#^/index\.php#', '', $path);
        return trim($path, '/');
    }

    private static function authenticate(string $access): void
    {
        $header = self::authorizationHeader();
        if ($header === null) {
            if ($access !== 'guest') {
                throw new ActionError('Inicia sesión para continuar.', 401);
            }
            Auth::actingAs(null);
            return;
        }
        if (!preg_match('/^Bearer\s+(\S+)$/i', $header, $m)) {
            throw new ActionError('Cabecera Authorization no válida. Usa «Bearer <token>».', 401);
        }
        $resolved = ApiToken::resolve($m[1]);
        if ($resolved === null) {
            // Un token viejo no impide iniciar sesión ni leer la configuración pública.
            if ($access === 'guest') {
                Auth::actingAs(null);
                return;
            }
            throw new ActionError('Tu sesión expiró o se cerró. Vuelve a iniciar sesión.', 401);
        }
        [self::$token, $user] = $resolved;
        Auth::actingAs($user);

        if (in_array($access, ['moderator', 'admin'], true) && !Auth::hasRole($access, $user)) {
            throw new ActionError('No tienes permisos para esta acción.', 403);
        }
    }

    /** En mantenimiento solo el equipo (moderadores y administradores) puede usar la API; el resto recibe 503. */
    private static function maintenance(string $access): void
    {
        if (!AppSetting::flag('maintenance_mode') || $access === 'guest' || Auth::hasRole('moderator')) {
            return;
        }
        throw new ActionError('TREVIX está en mantenimiento. Vuelve a intentarlo en unos minutos.', 503);
    }

    private static function authorizationHeader(): ?string
    {
        $value = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null;
        if ($value === null && function_exists('getallheaders')) {
            foreach ((array) getallheaders() as $name => $header) {
                if (strcasecmp((string) $name, 'Authorization') === 0) {
                    $value = $header;
                    break;
                }
            }
        }
        $value = is_string($value) ? trim($value) : '';
        return $value !== '' ? $value : null;
    }
}
