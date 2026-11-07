<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Grafo social: seguir, solicitudes para cuentas privadas, listas de conexiones y sugerencias.
 * Los contadores followers_count / following_count solo cambian cuando la fila de follows realmente
 * se insertó o se borró, así no se desincronizan con dobles clics ni peticiones repetidas.
 */
final class Follow extends Model
{
    /** Columnas de usuario para listas (alias u). */
    public const USER_COLUMNS = 'u.id, u.username, u.display_name, u.avatar_path, u.bio, u.is_private, u.is_verified,
        u.followers_count, u.created_at';

    /** Cuenta activa y sin bloqueo con el usuario que mira (alias u). Usa 2 parámetros: el id del que mira. */
    public const VISIBLE_USER = "u.status = 'active' AND NOT EXISTS (SELECT 1 FROM blocks bk
        WHERE (bk.blocker_id = ? AND bk.blocked_id = u.id) OR (bk.blocker_id = u.id AND bk.blocked_id = ?))";

    // -------------------------------------------------------------------------
    // Relaciones
    // -------------------------------------------------------------------------

    /**
     * Relación del usuario que mira con cada persona de la lista.
     *
     * @return array<int, array{following: bool, requested: bool, follows_you: bool}>
     */
    public static function relationsFor(int $viewerId, array $userIds): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $userIds))));
        $out = [];
        foreach ($ids as $id) {
            $out[$id] = ['following' => false, 'requested' => false, 'follows_you' => false];
        }
        if ($ids === []) {
            return $out;
        }
        $marks = implode(',', array_fill(0, count($ids), '?'));
        $queries = [
            'following'   => "SELECT following_id FROM follows WHERE follower_id = ? AND following_id IN ($marks)",
            'follows_you' => "SELECT follower_id FROM follows WHERE following_id = ? AND follower_id IN ($marks)",
            'requested'   => "SELECT target_id FROM follow_requests WHERE requester_id = ? AND status = 'pending' AND target_id IN ($marks)",
        ];
        foreach ($queries as $key => $sql) {
            $stmt = self::db()->prepare($sql);
            $stmt->execute(array_merge([$viewerId], $ids));
            foreach ($stmt->fetchAll(\PDO::FETCH_COLUMN) as $id) {
                $out[(int) $id][$key] = true;
            }
        }
        return $out;
    }

    public static function relation(int $viewerId, int $userId): array
    {
        return self::relationsFor($viewerId, [$userId])[$userId];
    }

    /** Añade a cada usuario la clave "relation" para dibujar sus botones. */
    public static function withRelations(int $viewerId, array $users): array
    {
        $relations = self::relationsFor($viewerId, array_column($users, 'id'));
        foreach ($users as &$user) {
            $user['relation'] = $relations[(int) $user['id']] ?? ['following' => false, 'requested' => false, 'follows_you' => false];
        }
        return $users;
    }

    // -------------------------------------------------------------------------
    // Escritura
    // -------------------------------------------------------------------------

    /**
     * Seguir: en cuentas públicas crea la relación; en privadas deja una solicitud pendiente.
     *
     * @param array{id:int|string, is_private:int|string|bool} $target
     * @return string 'following' | 'requested'
     */
    public static function follow(int $followerId, array $target): string
    {
        $targetId = (int) $target['id'];
        return Database::transaction(static function () use ($followerId, $targetId, $target): string {
            if (User::follows($followerId, $targetId)) {
                return 'following';
            }
            if (!empty($target['is_private'])) {
                // Las asignaciones se evalúan en orden: created_at se calcula antes de cambiar status.
                self::execute(
                    "INSERT INTO follow_requests (requester_id, target_id) VALUES (?, ?)
                     ON DUPLICATE KEY UPDATE created_at = IF(status = 'pending', created_at, NOW()),
                         status = 'pending', responded_at = NULL",
                    [$followerId, $targetId]
                );
                return 'requested';
            }
            if (self::link($followerId, $targetId)) {
                Notification::notify($targetId, $followerId, 'follow');
            }
            self::execute('DELETE FROM follow_requests WHERE requester_id = ? AND target_id = ?', [$followerId, $targetId]);
            return 'following';
        });
    }

    /** Dejar de seguir o cancelar una solicitud pendiente. */
    public static function unfollow(int $followerId, int $targetId): void
    {
        Database::transaction(static function () use ($followerId, $targetId): void {
            self::unlink($followerId, $targetId);
            self::execute('DELETE FROM follow_requests WHERE requester_id = ? AND target_id = ?', [$followerId, $targetId]);
            Notification::remove($targetId, $followerId, 'follow');
        });
    }

    /** El dueño de la cuenta aprueba una solicitud. Devuelve false si ya no estaba pendiente. */
    public static function accept(int $targetId, int $requesterId): bool
    {
        return Database::transaction(static function () use ($targetId, $requesterId): bool {
            $deleted = self::execute(
                "DELETE FROM follow_requests WHERE requester_id = ? AND target_id = ? AND status = 'pending'",
                [$requesterId, $targetId]
            );
            if ($deleted !== 1) {
                return false;
            }
            if (self::link($requesterId, $targetId)) {
                Notification::notify($requesterId, $targetId, 'follow_accepted');
            }
            return true;
        });
    }

    public static function reject(int $targetId, int $requesterId): bool
    {
        return self::execute(
            "DELETE FROM follow_requests WHERE requester_id = ? AND target_id = ? AND status = 'pending'",
            [$requesterId, $targetId]
        ) === 1;
    }

    /** Al pasar la cuenta a pública se aprueban todas las solicitudes pendientes. Devuelve cuántas. */
    public static function acceptAll(int $targetId): int
    {
        return Database::transaction(static function () use ($targetId): int {
            $requesters = self::db()->prepare(
                "SELECT requester_id FROM follow_requests WHERE target_id = ? AND status = 'pending' FOR UPDATE"
            );
            $requesters->execute([$targetId]);
            $accepted = 0;
            foreach ($requesters->fetchAll(\PDO::FETCH_COLUMN) as $requesterId) {
                if (self::link((int) $requesterId, $targetId)) {
                    Notification::notify((int) $requesterId, $targetId, 'follow_accepted');
                    $accepted++;
                }
            }
            self::execute("DELETE FROM follow_requests WHERE target_id = ? AND status = 'pending'", [$targetId]);
            return $accepted;
        });
    }

    /** El dueño de la cuenta quita a alguien de sus seguidores. */
    public static function removeFollower(int $ownerId, int $followerId): bool
    {
        return Database::transaction(static function () use ($ownerId, $followerId): bool {
            Notification::remove($ownerId, $followerId, 'follow');
            return self::unlink($followerId, $ownerId);
        });
    }

    /** Rompe toda relación entre dos cuentas (al bloquear). Debe llamarse dentro de una transacción. */
    public static function severBetween(int $a, int $b): void
    {
        self::unlink($a, $b);
        self::unlink($b, $a);
        self::execute(
            'DELETE FROM follow_requests WHERE (requester_id = ? AND target_id = ?) OR (requester_id = ? AND target_id = ?)',
            [$a, $b, $b, $a]
        );
    }

    /**
     * Antes de borrar una cuenta: descuenta de los contadores ajenos las relaciones que se eliminarán en cascada.
     * Cada pareja es única, así que cada fila resta exactamente 1.
     */
    public static function releaseCountersForUser(int $userId): void
    {
        self::execute(
            'UPDATE users u JOIN follows f ON f.following_id = u.id AND f.follower_id = ?
             SET u.followers_count = GREATEST(CAST(u.followers_count AS SIGNED) - 1, 0)',
            [$userId]
        );
        self::execute(
            'UPDATE users u JOIN follows f ON f.follower_id = u.id AND f.following_id = ?
             SET u.following_count = GREATEST(CAST(u.following_count AS SIGNED) - 1, 0)',
            [$userId]
        );
    }

    private static function link(int $followerId, int $followingId): bool
    {
        if (self::execute('INSERT IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)', [$followerId, $followingId]) !== 1) {
            return false;
        }
        self::execute('UPDATE users SET following_count = following_count + 1 WHERE id = ?', [$followerId]);
        self::execute('UPDATE users SET followers_count = followers_count + 1 WHERE id = ?', [$followingId]);
        return true;
    }

    private static function unlink(int $followerId, int $followingId): bool
    {
        if (self::execute('DELETE FROM follows WHERE follower_id = ? AND following_id = ?', [$followerId, $followingId]) !== 1) {
            return false;
        }
        self::execute('UPDATE users SET following_count = following_count - (following_count > 0) WHERE id = ?', [$followerId]);
        self::execute('UPDATE users SET followers_count = followers_count - (followers_count > 0) WHERE id = ?', [$followingId]);
        return true;
    }

    // -------------------------------------------------------------------------
    // Listas
    // -------------------------------------------------------------------------

    /**
     * Seguidores ('followers') o seguidos ('following') de un perfil, del más reciente al más antiguo,
     * sin cuentas inactivas ni bloqueadas respecto de quien mira.
     *
     * @return array{users: list<array>, hasMore: bool}
     */
    public static function connections(string $type, int $profileId, int $viewerId, int $page, int $limit): array
    {
        $join = $type === 'followers'
            ? 'JOIN follows f ON f.follower_id = u.id AND f.following_id = ?'
            : 'JOIN follows f ON f.following_id = u.id AND f.follower_id = ?';
        return self::page(
            'SELECT ' . self::USER_COLUMNS . " FROM users u $join WHERE " . self::VISIBLE_USER . ' ORDER BY f.created_at DESC, u.id DESC',
            [$profileId, $viewerId, $viewerId],
            $viewerId,
            $page,
            $limit
        );
    }

    /** @return array{users: list<array>, hasMore: bool} solicitudes pendientes recibidas, más recientes primero. */
    public static function pendingRequests(int $userId, int $page, int $limit): array
    {
        return self::page(
            'SELECT ' . self::USER_COLUMNS . ", fr.created_at AS requested_at
             FROM follow_requests fr JOIN users u ON u.id = fr.requester_id
             WHERE fr.target_id = ? AND fr.status = 'pending' AND " . self::VISIBLE_USER . '
             ORDER BY fr.created_at DESC, fr.id DESC',
            [$userId, $userId, $userId],
            $userId,
            $page,
            $limit
        );
    }

    /**
     * Personas que el usuario aún no sigue: primero quienes lo siguen, luego las seguidas por sus seguidos
     * (amigos de amigos), y por último cuentas populares y nuevas. Cada una trae el motivo de la sugerencia.
     */
    public static function suggestions(int $viewerId, int $limit = 3): array
    {
        $limit = max(1, min(30, $limit));
        $rows = self::fetchAll(
            'SELECT ' . self::USER_COLUMNS . ", c.mutuals, c.follows_you
             FROM (
                SELECT id, SUM(mutual) AS mutuals, MAX(follows_you) AS follows_you FROM (
                    SELECT f2.following_id AS id, 1 AS mutual, 0 AS follows_you
                      FROM follows f1 JOIN follows f2 ON f2.follower_id = f1.following_id
                     WHERE f1.follower_id = ?
                    UNION ALL
                    SELECT follower_id, 0, 1 FROM follows WHERE following_id = ?
                    UNION ALL
                    (SELECT id, 0, 0 FROM users WHERE status = 'active' ORDER BY followers_count DESC, id DESC LIMIT 40)
                    UNION ALL
                    (SELECT id, 0, 0 FROM users WHERE status = 'active' ORDER BY id DESC LIMIT 40)
                ) candidates GROUP BY id
             ) c
             JOIN users u ON u.id = c.id
             WHERE u.id <> ? AND " . self::VISIBLE_USER . "
               AND NOT EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id)
               AND NOT EXISTS (SELECT 1 FROM follow_requests r WHERE r.requester_id = ? AND r.target_id = u.id AND r.status = 'pending')
             ORDER BY c.follows_you DESC, c.mutuals DESC, u.followers_count DESC, u.id DESC
             LIMIT " . $limit,
            [$viewerId, $viewerId, $viewerId, $viewerId, $viewerId, $viewerId, $viewerId]
        );

        $recent = strtotime('-14 days');
        foreach ($rows as &$row) {
            $mutuals = (int) $row['mutuals'];
            $row['reason'] = match (true) {
                (bool) $row['follows_you'] => 'Te sigue',
                $mutuals > 0 => 'Seguido por ' . self::mutualName($viewerId, (int) $row['id'])
                    . ($mutuals > 1 ? ' y ' . ($mutuals - 1) . ' más' : ''),
                strtotime($row['created_at']) > $recent => 'Nuevo en TREVIX',
                default => 'Popular en TREVIX',
            };
            $row['relation'] = ['following' => false, 'requested' => false, 'follows_you' => (bool) $row['follows_you']];
            unset($row['mutuals'], $row['follows_you']);
        }
        return $rows;
    }

    /** Nombre de una persona que el usuario sigue y que a su vez sigue a $userId (la más popular). */
    private static function mutualName(int $viewerId, int $userId): string
    {
        $name = self::fetchValue(
            "SELECT mu.display_name FROM follows a
             JOIN follows b ON b.follower_id = a.following_id AND b.following_id = ?
             JOIN users mu ON mu.id = a.following_id AND mu.status = 'active'
             WHERE a.follower_id = ? ORDER BY mu.followers_count DESC LIMIT 1",
            [$userId, $viewerId]
        );
        return is_string($name) ? $name : 'personas que sigues';
    }

    /** Ejecuta una consulta de usuarios paginada y le añade la relación con quien mira. */
    private static function page(string $sql, array $params, int $viewerId, int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll($sql . ' LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit), $params);
        return [
            'users'   => self::withRelations($viewerId, array_slice($rows, 0, $limit)),
            'hasMore' => count($rows) > $limit,
        ];
    }
}
