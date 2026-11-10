<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;

/**
 * Notas de 6 horas: un texto corto que se muestra como una nube sobre el avatar (perfil, barra de historias y
 * visor). Cada persona tiene como mucho una activa; publicar otra la reemplaza. La ve quien la publica y,
 * si la cuenta está activa y no hay bloqueo entre ambas, según su público: seguidores (te sigue), amigos
 * (se siguen mutuamente) o mejores amigos (estás en su lista close_friends).
 */
final class Note extends Model
{
    public const AUDIENCES = [
        'followers'     => 'Seguidores',
        'friends'       => 'Amigos',
        'close_friends' => 'Mejores amigos',
    ];

    private const USER_COLUMNS = 'u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS user_status, u.message_privacy';

    /** Nota visible para quien mira (alias n y autor u). Usa 7 parámetros: el id de quien mira. */
    private const VISIBLE = "n.expires_at > NOW() AND u.status = 'active' AND (n.user_id = ? OR (
            NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = n.user_id) OR (b.blocker_id = n.user_id AND b.blocked_id = ?))
            AND CASE n.audience
                WHEN 'close_friends' THEN EXISTS (SELECT 1 FROM close_friends cf WHERE cf.user_id = n.user_id AND cf.friend_id = ?)
                WHEN 'friends' THEN EXISTS (SELECT 1 FROM follows f1 WHERE f1.follower_id = ? AND f1.following_id = n.user_id)
                    AND EXISTS (SELECT 1 FROM follows f2 WHERE f2.follower_id = n.user_id AND f2.following_id = ?)
                ELSE EXISTS (SELECT 1 FROM follows f3 WHERE f3.follower_id = ? AND f3.following_id = n.user_id)
            END
        ))";

    /** Nota activa de una persona (la propia, con su público). */
    public static function current(int $userId): ?array
    {
        return self::fetchOne(
            'SELECT n.id, n.user_id, n.body, n.audience, n.created_at, n.expires_at, ' . self::USER_COLUMNS . '
             FROM user_notes n JOIN users u ON u.id = n.user_id
             WHERE n.user_id = ? AND n.expires_at > NOW() ORDER BY n.id DESC LIMIT 1',
            [$userId]
        );
    }

    /** Nota visible por su id. */
    public static function findVisible(int $id, int $viewerId): ?array
    {
        return self::fetchOne(
            'SELECT n.id, n.user_id, n.body, n.audience, n.created_at, n.expires_at, ' . self::USER_COLUMNS . '
             FROM user_notes n JOIN users u ON u.id = n.user_id
             WHERE n.id = ? AND ' . self::VISIBLE . ' LIMIT 1',
            array_merge([$id], array_fill(0, 7, $viewerId))
        );
    }

    /**
     * Notas activas visibles de varias cuentas, por id de autor.
     *
     * @return array<int, array>
     */
    public static function forAuthors(array $authorIds, int $viewerId): array
    {
        $authorIds = array_values(array_unique(array_filter(array_map('intval', $authorIds))));
        if ($authorIds === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT n.id, n.user_id, n.body, n.audience, n.created_at, n.expires_at, ' . self::USER_COLUMNS . '
             FROM user_notes n JOIN users u ON u.id = n.user_id
             WHERE n.user_id IN (' . implode(',', array_fill(0, count($authorIds), '?')) . ') AND ' . self::VISIBLE . '
             ORDER BY n.id ASC',
            array_merge($authorIds, array_fill(0, 7, $viewerId))
        );
        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r['user_id']] = $r;
        }
        return $out;
    }

    /**
     * Barra de notas: la propia primero y luego las visibles de las cuentas que sigue o que la tienen en su lista
     * de mejores amigos, de la más reciente a la más antigua.
     *
     * @return list<array>
     */
    public static function tray(int $viewerId, int $limit = 60): array
    {
        return self::fetchAll(
            'SELECT n.id, n.user_id, n.body, n.audience, n.created_at, n.expires_at, ' . self::USER_COLUMNS . '
             FROM user_notes n JOIN users u ON u.id = n.user_id
             WHERE (n.user_id = ? OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = n.user_id)
                    OR EXISTS (SELECT 1 FROM close_friends c WHERE c.user_id = n.user_id AND c.friend_id = ?))
               AND ' . self::VISIBLE . '
             ORDER BY (n.user_id = ?) DESC, n.created_at DESC
             LIMIT ' . max(1, min(100, $limit)),
            array_merge([$viewerId, $viewerId, $viewerId], array_fill(0, 7, $viewerId), [$viewerId])
        );
    }

    /** Publica la nota (reemplaza la anterior). Devuelve su id. */
    public static function publish(int $userId, string $body, string $audience): int
    {
        self::execute('DELETE FROM user_notes WHERE user_id = ?', [$userId]);
        self::execute(
            'INSERT INTO user_notes (user_id, body, audience, expires_at) VALUES (?, ?, ?, NOW() + INTERVAL ? SECOND)',
            [$userId, $body, $audience, (int) Config::get('app.notes.ttl', 21600)]
        );
        return (int) self::db()->lastInsertId();
    }

    /** Borra la nota de una persona. Devuelve true si tenía una activa. */
    public static function remove(int $userId): bool
    {
        $active = (int) self::fetchValue('SELECT COUNT(*) FROM user_notes WHERE user_id = ? AND expires_at > NOW()', [$userId]);
        self::execute('DELETE FROM user_notes WHERE user_id = ?', [$userId]);
        return $active > 0;
    }

    /** Borra las notas caducadas (sin tareas programadas en el hosting: se llama al leer la barra). */
    public static function purgeExpired(int $limit = 200): void
    {
        self::execute('DELETE FROM user_notes WHERE expires_at <= NOW() LIMIT ' . max(1, min(1000, $limit)));
    }

    // -------------------------------------------------------------------------
    // Mejores amigos
    // -------------------------------------------------------------------------

    /** @return list<array> personas de la lista (cuentas activas), la más reciente primero */
    public static function closeFriends(int $userId): array
    {
        return self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified
             FROM close_friends c JOIN users u ON u.id = c.friend_id
             WHERE c.user_id = ? AND u.status = 'active'
             ORDER BY c.created_at DESC, u.id DESC",
            [$userId]
        );
    }

    public static function closeFriendsCount(int $userId): int
    {
        return (int) self::fetchValue('SELECT COUNT(*) FROM close_friends WHERE user_id = ?', [$userId]);
    }

    public static function isCloseFriend(int $userId, int $friendId): bool
    {
        return (bool) self::fetchValue('SELECT 1 FROM close_friends WHERE user_id = ? AND friend_id = ?', [$userId, $friendId]);
    }

    /**
     * Candidatos para la lista: tus seguidores y las cuentas que sigues (activas y sin bloqueo), con la marca
     * «selected» si ya están; filtra por usuario o nombre con $query.
     *
     * @return list<array>
     */
    public static function candidates(int $userId, string $query, int $limit = 50): array
    {
        $params = array_fill(0, 6, $userId);
        $where = '';
        if ($query !== '') {
            $like = '%' . self::likeEscape($query) . '%';
            $where = ' AND (u.username LIKE ? OR u.display_name LIKE ?)';
            $params[] = $like;
            $params[] = $like;
        }
        return self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified,
                    EXISTS (SELECT 1 FROM close_friends c WHERE c.user_id = ? AND c.friend_id = u.id) AS selected
             FROM users u
             WHERE u.status = 'active' AND u.id <> ?
               AND (EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = u.id AND f.following_id = ?)
                    OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id))
               AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = ?))"
            . $where . '
             ORDER BY selected DESC, u.display_name ASC
             LIMIT ' . max(1, min(100, $limit)),
            $params
        );
    }

    public static function addCloseFriend(int $userId, int $friendId): void
    {
        self::execute('INSERT IGNORE INTO close_friends (user_id, friend_id) VALUES (?, ?)', [$userId, $friendId]);
    }

    public static function removeCloseFriend(int $userId, int $friendId): void
    {
        self::execute('DELETE FROM close_friends WHERE user_id = ? AND friend_id = ?', [$userId, $friendId]);
    }
}
