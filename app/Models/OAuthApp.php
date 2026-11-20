<?php
declare(strict_types=1);

namespace Trevix\Models;

final class OAuthApp extends Model
{
    public const PLATFORMS = ['android' => 'Android', 'ios' => 'iOS', 'web' => 'Web'];
    public const STATUSES = [
        'pending'  => 'En revisión',
        'approved' => 'Aprobada',
        'rejected' => 'Rechazada',
        'revoked'  => 'Revocada',
    ];

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT * FROM oauth_apps WHERE id = ?', [$id]);
    }

    public static function byClientId(string $clientId): ?array
    {
        return self::fetchOne('SELECT * FROM oauth_apps WHERE client_id = ? LIMIT 1', [$clientId]);
    }

    public static function forOwner(int $ownerId): array
    {
        return self::fetchAll(
            'SELECT a.*,
                    (SELECT COUNT(DISTINCT t.user_id) FROM oauth_access_tokens t WHERE t.app_id = a.id) AS logins_count,
                    (SELECT COUNT(*) FROM oauth_access_tokens t WHERE t.app_id = a.id) AS tokens_count
             FROM oauth_apps a
             WHERE a.owner_id = ?
             ORDER BY a.id DESC',
            [$ownerId]
        );
    }

    /** Usuarios distintos que han iniciado sesión en la app (tokens emitidos). */
    public static function loginsCount(int $appId): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(DISTINCT user_id) FROM oauth_access_tokens WHERE app_id = ?',
            [$appId]
        );
    }

    public static function pendingCount(): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM oauth_apps WHERE status = 'pending'");
    }

    public static function pending(int $page, int $limit): array
    {
        return self::adminList('pending', $page, $limit);
    }

    /** @param 'pending'|'approved'|'rejected'|'all' $status */
    public static function adminList(string $status, int $page, int $limit): array
    {
        $limit = max(1, min(50, $limit));
        $where = match ($status) {
            'approved' => "a.status = 'approved'",
            'rejected' => "a.status = 'rejected'",
            'all'      => '1=1',
            default    => "a.status = 'pending'",
        };
        $order = $status === 'pending' ? 'a.created_at ASC' : 'a.id DESC';
        $rows = self::fetchAll(
            "SELECT a.*, u.username, u.display_name, u.avatar_path, u.is_verified,
                    (SELECT COUNT(DISTINCT t.user_id) FROM oauth_access_tokens t WHERE t.app_id = a.id) AS logins_count
             FROM oauth_apps a
             JOIN users u ON u.id = a.owner_id
             WHERE $where
             ORDER BY $order
             LIMIT " . ($limit + 1) . ' OFFSET ' . ((max(1, $page) - 1) * $limit)
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    public static function create(array $data): int
    {
        self::execute(
            'INSERT INTO oauth_apps (owner_id, name, description, icon_path, platform, package_name, website_url, redirect_uris, client_id, client_secret_hash, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $data['owner_id'], $data['name'], $data['description'], $data['icon_path'],
                $data['platform'], $data['package_name'], $data['website_url'], $data['redirect_uris'],
                $data['client_id'], $data['client_secret_hash'], $data['status'] ?? 'pending',
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function review(int $id, string $status, int $reviewerId, ?string $note): bool
    {
        return self::execute(
            'UPDATE oauth_apps SET status = ?, reviewed_by = ?, reviewed_at = NOW(), review_note = ? WHERE id = ? AND status = ?',
            [$status, $reviewerId, $note, $id, 'pending']
        ) > 0;
    }

    public static function storeCode(int $appId, int $userId, string $code, string $redirectUri, int $ttlSeconds = 600): void
    {
        self::execute(
            'INSERT INTO oauth_authorization_codes (app_id, user_id, code, redirect_uri, expires_at) VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))',
            [$appId, $userId, $code, $redirectUri, $ttlSeconds]
        );
    }

    public static function consumeCode(string $code): ?array
    {
        $row = self::fetchOne(
            'SELECT * FROM oauth_authorization_codes WHERE code = ? AND used_at IS NULL AND expires_at > NOW() FOR UPDATE',
            [$code]
        );
        if ($row === null) {
            return null;
        }
        self::execute('UPDATE oauth_authorization_codes SET used_at = NOW() WHERE id = ?', [(int) $row['id']]);
        return $row;
    }

    public static function storeToken(int $appId, int $userId, string $tokenHash, int $ttlSeconds = 86400 * 30): void
    {
        self::execute(
            'INSERT INTO oauth_access_tokens (app_id, user_id, token_hash, expires_at) VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))',
            [$appId, $userId, $tokenHash, $ttlSeconds]
        );
    }

    public static function findToken(string $tokenHash): ?array
    {
        return self::fetchOne(
            'SELECT t.*, a.client_id, a.name AS app_name, a.status AS app_status
             FROM oauth_access_tokens t
             JOIN oauth_apps a ON a.id = t.app_id
             WHERE t.token_hash = ? AND t.revoked_at IS NULL AND t.expires_at > NOW() AND a.status = ?',
            [$tokenHash, 'approved']
        );
    }
}
