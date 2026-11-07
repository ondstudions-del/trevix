<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;

/**
 * Límite de intentos por acción y clave (IP, IP + usuario…), configurado en
 * app.security.rate_limits. Solo se guarda el hash de la clave.
 */
final class RateLimit extends Model
{
    public static function tooManyAttempts(string $action, string $key): bool
    {
        [$max, $window] = self::limits($action);
        return self::attempts($action, $key, $window) >= $max;
    }

    /** Segundos que faltan para poder intentarlo de nuevo. */
    public static function availableIn(string $action, string $key): int
    {
        [, $window] = self::limits($action);
        $oldest = self::fetchValue(
            'SELECT MIN(created_at) FROM rate_limits WHERE action = ? AND key_hash = ? AND created_at > (NOW() - INTERVAL ? SECOND)',
            [$action, self::hashKey($key), $window]
        );
        if (!$oldest) {
            return 0;
        }
        return max(0, (strtotime((string) $oldest) + $window) - time());
    }

    public static function hit(string $action, string $key): void
    {
        self::execute('INSERT INTO rate_limits (action, key_hash) VALUES (?, ?)', [$action, self::hashKey($key)]);

        if (random_int(1, 50) === 1) {
            self::execute('DELETE FROM rate_limits WHERE created_at < (NOW() - INTERVAL 1 DAY)');
        }
    }

    public static function clear(string $action, string $key): void
    {
        self::execute('DELETE FROM rate_limits WHERE action = ? AND key_hash = ?', [$action, self::hashKey($key)]);
    }

    private static function attempts(string $action, string $key, int $window): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM rate_limits WHERE action = ? AND key_hash = ? AND created_at > (NOW() - INTERVAL ? SECOND)',
            [$action, self::hashKey($key), $window]
        );
    }

    /** @return array{0:int, 1:int} */
    private static function limits(string $action): array
    {
        $limit = Config::get('app.security.rate_limits.' . $action);
        if (!is_array($limit)) {
            throw new \LogicException('Límite no configurado: ' . $action);
        }
        return [(int) $limit['max'], (int) $limit['window']];
    }

    private static function hashKey(string $key): string
    {
        return hash('sha256', $key);
    }
}
