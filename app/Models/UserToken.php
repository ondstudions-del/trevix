<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;

/**
 * Enlaces de un solo uso enviados por correo (verificación, recuperación y cambio de correo).
 * Solo se guarda el SHA-256 del token; el valor original viaja únicamente en el enlace.
 */
final class UserToken extends Model
{
    public const TYPES = ['email_verification', 'password_reset', 'email_change'];

    /** Crea un token nuevo e invalida los anteriores del mismo tipo para ese usuario. */
    public static function issue(int $userId, string $type, ?string $payload = null): string
    {
        $ttl = (int) Config::get('app.security.token_ttl.' . $type, 3600);
        $token = bin2hex(random_bytes(32));

        self::execute('DELETE FROM user_tokens WHERE user_id = ? AND type = ?', [$userId, $type]);
        self::execute(
            'INSERT INTO user_tokens (user_id, type, token_hash, payload, expires_at) VALUES (?, ?, ?, ?, NOW() + INTERVAL ? SECOND)',
            [$userId, $type, hash('sha256', $token), $payload, $ttl]
        );

        if (random_int(1, 20) === 1) {
            self::execute('DELETE FROM user_tokens WHERE expires_at < NOW() - INTERVAL 7 DAY');
        }

        return $token;
    }

    /**
     * Token vigente y sin usar de alguno de los tipos indicados.
     *
     * @param list<string> $types
     */
    public static function findValid(string $token, array $types): ?array
    {
        $types = array_values(array_intersect($types, self::TYPES));
        if ($types === [] || !preg_match('/^[a-f0-9]{64}$/', $token)) {
            return null;
        }

        $placeholders = implode(', ', array_fill(0, count($types), '?'));
        return self::fetchOne(
            "SELECT id, user_id, type, payload FROM user_tokens
             WHERE token_hash = ? AND type IN ($placeholders) AND used_at IS NULL AND expires_at > NOW() LIMIT 1",
            [hash('sha256', $token), ...$types]
        );
    }

    /** Marca el token como usado; devuelve false si otra petición lo consumió antes. */
    public static function consume(int $id): bool
    {
        return self::execute('UPDATE user_tokens SET used_at = NOW() WHERE id = ? AND used_at IS NULL AND expires_at > NOW()', [$id]) === 1;
    }

    public static function revoke(int $userId, string $type): void
    {
        self::execute('DELETE FROM user_tokens WHERE user_id = ? AND type = ?', [$userId, $type]);
    }
}
