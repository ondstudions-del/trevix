<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;

/**
 * Sesiones de la app móvil. El token en claro se entrega una sola vez al iniciar sesión; en la base
 * solo queda su SHA-256. Vence tras app.api.token_days sin uso (cada uso renueva el plazo) y deja de
 * valer si la cuenta deja de estar activa o si cambia el hash de la contraseña.
 */
final class ApiToken extends Model
{
    /** Prefijo visible para reconocer los tokens de TREVIX (p. ej. en un escáner de secretos). */
    private const PREFIX = 'trx_';

    /** @return array{token:string, id:int, expires_at:string} */
    public static function issue(int $userId, string $passwordHash, string $name): array
    {
        $plain = self::PREFIX . bin2hex(random_bytes(32));
        $days = self::days();
        self::execute(
            'INSERT INTO api_tokens (user_id, name, token_hash, password_fp, last_used_at, last_ip, expires_at)
             VALUES (?, ?, ?, ?, NOW(), ?, NOW() + INTERVAL ? DAY)',
            [$userId, self::cleanName($name), hash('sha256', $plain), Auth::fingerprint($passwordHash), self::ip(), $days]
        );
        $id = (int) self::db()->lastInsertId();
        self::prune($userId);
        return [
            'token'      => $plain,
            'id'         => $id,
            'expires_at' => (string) self::fetchValue('SELECT expires_at FROM api_tokens WHERE id = ?', [$id]),
        ];
    }

    /**
     * Valida un token Bearer y devuelve [token, usuario] o null. Los tokens vencidos, de cuentas que ya
     * no están activas o con una huella de contraseña antigua se borran al detectarlos.
     *
     * @return array{0: array, 1: array}|null
     */
    public static function resolve(string $plain): ?array
    {
        if (!preg_match('/^' . self::PREFIX . '[a-f0-9]{64}$/', $plain)) {
            return null;
        }
        $token = self::fetchOne(
            'SELECT id, user_id, name, password_fp, last_used_at, expires_at, expires_at <= NOW() AS expired
             FROM api_tokens WHERE token_hash = ? LIMIT 1',
            [hash('sha256', $plain)]
        );
        if ($token === null) {
            return null;
        }
        if ((int) $token['expired'] === 1) {
            self::revoke((int) $token['id']);
            return null;
        }
        $user = User::findForSession((int) $token['user_id']);
        if ($user === null || !hash_equals((string) $token['password_fp'], Auth::fingerprint($user['password_hash']))) {
            self::revoke((int) $token['id']);
            return null;
        }
        unset($user['password_hash']);

        // Renueva el plazo y la presencia como máximo cada 2 minutos.
        if ($token['last_used_at'] === null || time() - strtotime((string) $token['last_used_at']) > 120) {
            self::execute(
                'UPDATE api_tokens SET last_used_at = NOW(), last_ip = ?, expires_at = NOW() + INTERVAL ? DAY WHERE id = ?',
                [self::ip(), self::days(), (int) $token['id']]
            );
            User::touchLastSeen((int) $user['id']);
        }
        unset($token['password_fp'], $token['expired']);
        $token['id'] = (int) $token['id'];
        return [$token, $user];
    }

    /** Sesiones activas de la app de una cuenta, la más reciente primero. */
    public static function listFor(int $userId): array
    {
        $rows = self::fetchAll(
            'SELECT id, name, last_used_at, last_ip, expires_at, created_at FROM api_tokens
             WHERE user_id = ? AND expires_at > NOW() ORDER BY COALESCE(last_used_at, created_at) DESC',
            [$userId]
        );
        foreach ($rows as &$row) {
            $row['id'] = (int) $row['id'];
            $ip = $row['last_ip'] !== null ? @inet_ntop($row['last_ip']) : false;
            $row['last_ip'] = $ip !== false ? $ip : null;
        }
        return $rows;
    }

    public static function revoke(int $id): void
    {
        self::execute('DELETE FROM api_tokens WHERE id = ?', [$id]);
    }

    /** Cierra una sesión de la app de la propia cuenta. Devuelve false si no existe. */
    public static function revokeFor(int $userId, int $id): bool
    {
        return self::execute('DELETE FROM api_tokens WHERE id = ? AND user_id = ?', [$id, $userId]) === 1;
    }

    /** Cierra todas las sesiones de la app de una cuenta salvo, si se indica, la actual. */
    public static function revokeAllFor(int $userId, ?int $exceptId = null): int
    {
        return self::execute('DELETE FROM api_tokens WHERE user_id = ? AND id <> ?', [$userId, $exceptId ?? 0]);
    }

    /** Tras cambiar la contraseña desde la app, la sesión actual sigue valiendo con la nueva huella. */
    public static function refreshFingerprint(int $id, string $passwordHash): void
    {
        self::execute('UPDATE api_tokens SET password_fp = ? WHERE id = ?', [Auth::fingerprint($passwordHash), $id]);
    }

    private static function prune(int $userId): void
    {
        self::execute('DELETE FROM api_tokens WHERE user_id = ? AND expires_at <= NOW()', [$userId]);
        $max = max(1, (int) Config::get('app.api.max_tokens_per_user', 20));
        $keep = self::fetchAll(
            'SELECT id FROM api_tokens WHERE user_id = ? ORDER BY COALESCE(last_used_at, created_at) DESC, id DESC LIMIT ' . $max,
            [$userId]
        );
        if (count($keep) === $max) {
            $ids = array_map('intval', array_column($keep, 'id'));
            self::execute(
                'DELETE FROM api_tokens WHERE user_id = ? AND id NOT IN (' . implode(',', array_fill(0, count($ids), '?')) . ')',
                array_merge([$userId], $ids)
            );
        }
    }

    private static function cleanName(string $name): string
    {
        $name = trim((string) preg_replace('/[\p{C}\s]+/u', ' ', mb_check_encoding($name, 'UTF-8') ? $name : ''));
        return $name !== '' ? mb_substr($name, 0, 80) : 'App TREVIX';
    }

    private static function days(): int
    {
        return max(1, (int) Config::get('app.api.token_days', 90));
    }

    private static function ip(): ?string
    {
        $ip = @inet_pton(Request::ip());
        return $ip !== false ? $ip : null;
    }
}
