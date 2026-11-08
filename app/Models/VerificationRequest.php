<?php
declare(strict_types=1);

namespace Trevix\Models;

/** Solicitudes de verificado: las pide la persona desde la app y las decide un administrador. */
final class VerificationRequest extends Model
{
    public const CATEGORIES = [
        'creator'       => 'Creador de contenido',
        'artist'        => 'Artista o músico',
        'public_figure' => 'Figura pública',
        'brand'         => 'Marca, empresa u organización',
        'journalist'    => 'Periodista o medio',
        'athlete'       => 'Deportista',
        'other'         => 'Otro',
    ];

    public const STATUSES = [
        'pending'   => 'En revisión',
        'approved'  => 'Aprobada',
        'rejected'  => 'Rechazada',
        'cancelled' => 'Cancelada',
    ];

    private const COLUMNS = 'v.id, v.user_id, v.category, v.full_name, v.note, v.followers_count, v.avg_likes, v.posts_counted,
        v.status, v.reviewed_at, v.decision_note, v.created_at';

    /** Promedio de «Me gusta» de las últimas $recent publicaciones propias publicadas (sin contar las compartidas). */
    public static function likeStats(int $userId, int $recent): array
    {
        $row = self::fetchOne(
            "SELECT COUNT(*) AS posts, COALESCE(AVG(likes_count), 0) AS avg_likes FROM (
                SELECT likes_count FROM posts
                WHERE user_id = ? AND status = 'published' AND shared_post_id IS NULL
                ORDER BY created_at DESC, id DESC LIMIT " . max(1, min(50, $recent)) . '
             ) recent',
            [$userId]
        );
        return ['posts' => (int) ($row['posts'] ?? 0), 'avg_likes' => (int) floor((float) ($row['avg_likes'] ?? 0))];
    }

    public static function create(int $userId, string $category, string $fullName, ?string $note, int $followers, int $avgLikes, int $posts): int
    {
        self::execute(
            'INSERT INTO verification_requests (user_id, category, full_name, note, followers_count, avg_likes, posts_counted)
             VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$userId, $category, $fullName, $note, $followers, $avgLikes, $posts]
        );
        return (int) self::db()->lastInsertId();
    }

    /** La solicitud más reciente de una cuenta. */
    public static function latestFor(int $userId): ?array
    {
        return self::fetchOne('SELECT ' . self::COLUMNS . ' FROM verification_requests v WHERE v.user_id = ? ORDER BY v.id DESC LIMIT 1', [$userId]);
    }

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT ' . self::COLUMNS . ' FROM verification_requests v WHERE v.id = ?', [$id]);
    }

    /** Cancela la solicitud pendiente de una cuenta. Devuelve false si no había ninguna. */
    public static function cancel(int $userId): bool
    {
        return self::execute(
            "UPDATE verification_requests SET status = 'cancelled' WHERE user_id = ? AND status = 'pending'",
            [$userId]
        ) > 0;
    }

    /** Aprueba o rechaza una solicitud pendiente. Devuelve false si ya no estaba pendiente. */
    public static function decide(int $id, string $status, int $reviewerId, ?string $note): bool
    {
        return self::execute(
            "UPDATE verification_requests SET status = ?, reviewed_by = ?, reviewed_at = NOW(), decision_note = ?
             WHERE id = ? AND status = 'pending'",
            [$status, $reviewerId, $note, $id]
        ) > 0;
    }

    public static function pendingCount(): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM verification_requests v JOIN users u ON u.id = v.user_id WHERE v.status = 'pending' AND u.status = 'active'"
        );
    }

    /**
     * Solicitudes para el panel, con la cuenta y sus cifras actuales (seguidores y advertencias recientes).
     *
     * @return array{requests: list<array>, hasMore: bool}
     */
    public static function adminList(string $status, int $page, int $limit, int $warningDays): array
    {
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ', u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS user_status,
                    u.followers_count AS current_followers, u.posts_count, u.created_at AS user_created_at, u.email_verified_at,
                    r.username AS reviewer_username,
                    (SELECT COUNT(*) FROM user_warnings w WHERE w.user_id = v.user_id AND w.revoked_at IS NULL
                       AND w.created_at > (NOW() - INTERVAL ? DAY)) AS recent_warnings
             FROM verification_requests v
             JOIN users u ON u.id = v.user_id
             LEFT JOIN users r ON r.id = v.reviewed_by
             WHERE v.status = ?
             ORDER BY ' . ($status === 'pending' ? 'v.created_at ASC' : 'v.reviewed_at DESC') . ', v.id DESC
             LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            [$warningDays, $status]
        );
        $hasMore = count($rows) > $limit;
        return ['requests' => array_slice($rows, 0, $limit), 'hasMore' => $hasMore];
    }

    /** Cuántas solicitudes hay en cada estado (pestañas del panel). */
    public static function counts(): array
    {
        $counts = array_fill_keys(array_keys(self::STATUSES), 0);
        foreach (self::fetchAll('SELECT status, COUNT(*) AS n FROM verification_requests GROUP BY status') as $row) {
            $counts[$row['status']] = (int) $row['n'];
        }
        return $counts;
    }
}
