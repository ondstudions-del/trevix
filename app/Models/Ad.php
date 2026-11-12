<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * OND-ADS: campañas pagadas (promocionar una publicación, una comunidad o un grupo propios, o un anuncio libre con
 * enlace) y las personas que vieron cada una por día de campaña. El día 0 son las primeras 24 horas desde que la
 * administración la aprobó; cada persona cuenta una sola vez por día.
 */
final class Ad extends Model
{
    public const KINDS = [
        'post'      => 'Publicación',
        'community' => 'Comunidad',
        'group'     => 'Grupo',
        'custom'    => 'Anuncio libre',
    ];

    public const STATUSES = [
        'pending'   => 'En revisión',
        'active'    => 'Activo',
        'finished'  => 'Terminado',
        'rejected'  => 'Rechazado',
        'cancelled' => 'Cancelado',
        'removed'   => 'Retirado',
    ];

    public const CTAS = [
        'learn_more' => 'Más información',
        'shop'       => 'Comprar',
        'visit'      => 'Visitar',
        'sign_up'    => 'Registrarse',
        'contact'    => 'Contactar',
    ];

    private const SELECT = 'SELECT a.*, u.username, u.display_name, u.avatar_path, u.is_verified,
            p.body AS post_body, cm.name AS community_name, cm.slug AS community_slug, g.title AS group_title,
            r.username AS reviewer_username
        FROM ad_campaigns a
        JOIN users u ON u.id = a.user_id
        LEFT JOIN posts p ON p.id = a.post_id
        LEFT JOIN communities cm ON cm.id = a.community_id
        LEFT JOIN conversations g ON g.id = a.conversation_id
        LEFT JOIN users r ON r.id = a.reviewed_by';

    /** Día de campaña en curso (null si aún no empezó). */
    private const DAY_SQL = 'FLOOR(TIMESTAMPDIFF(SECOND, a.starts_at, NOW()) / 86400)';

    public static function find(int $id): ?array
    {
        return self::fetchOne(self::SELECT . ' WHERE a.id = ? LIMIT 1', [$id]);
    }

    /** Fila bloqueada para cambiar su estado o su dinero. Llamar dentro de una transacción. */
    public static function lock(int $id): ?array
    {
        return self::fetchOne('SELECT * FROM ad_campaigns WHERE id = ? LIMIT 1 FOR UPDATE', [$id]);
    }

    /** @param array<string, mixed> $data */
    public static function create(array $data): int
    {
        self::execute(
            'INSERT INTO ad_campaigns (user_id, kind, post_id, community_id, conversation_id, title, body, image_path, link_url, cta,
                                       days, daily_cents, total_cents, reach_min, reach_max)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $data['user_id'], $data['kind'], $data['post_id'] ?? null, $data['community_id'] ?? null, $data['conversation_id'] ?? null,
                $data['title'] ?? null, $data['body'] ?? null, $data['image_path'] ?? null, $data['link_url'] ?? null, $data['cta'] ?? null,
                $data['days'], $data['daily_cents'], $data['total_cents'], $data['reach_min'], $data['reach_max'],
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function approve(int $id, int $staffId): void
    {
        self::execute(
            "UPDATE ad_campaigns SET status = 'active', reviewed_by = ?, reviewed_at = NOW(), starts_at = NOW(),
                    ends_at = NOW() + INTERVAL days DAY, review_note = NULL
             WHERE id = ? AND status = 'pending'",
            [$staffId, $id]
        );
    }

    /** Cierra la campaña con su estado final y lo devuelto. */
    public static function close(int $id, string $status, int $refundedCents, ?int $staffId, ?string $note): void
    {
        self::execute(
            'UPDATE ad_campaigns SET status = ?, refunded_cents = refunded_cents + ?, settled_at = NOW(),
                    ends_at = CASE WHEN ends_at IS NOT NULL AND ends_at > NOW() THEN NOW() ELSE ends_at END,
                    reviewed_by = COALESCE(?, reviewed_by), reviewed_at = CASE WHEN ? IS NULL THEN reviewed_at ELSE NOW() END,
                    review_note = COALESCE(?, review_note)
             WHERE id = ?',
            [$status, $refundedCents, $staffId, $staffId, $note, $id]
        );
    }

    /** Personas distintas que vio la campaña en cada día: [día => personas]. */
    public static function reachByDay(int $id): array
    {
        $out = [];
        foreach (self::fetchAll('SELECT day_index, COUNT(*) AS people FROM ad_impressions WHERE campaign_id = ? GROUP BY day_index', [$id]) as $row) {
            $out[(int) $row['day_index']] = (int) $row['people'];
        }
        return $out;
    }

    /** Campañas activas cuyo plazo terminó (se cierran y se liquidan). @return list<int> */
    public static function dueIds(int $limit = 5): array
    {
        return array_map('intval', array_column(self::fetchAll(
            "SELECT id FROM ad_campaigns WHERE status = 'active' AND ends_at <= NOW() ORDER BY ends_at LIMIT " . max(1, min(20, $limit))
        ), 'id'));
    }

    /**
     * Campañas que pueden mostrarse ahora a $viewerId: activas, de otra cuenta, sin bloqueo entre ambos, que esta
     * persona no vio hoy y que no llegaron al tope de personas del día. Primero las más atrasadas en su reparto.
     */
    public static function candidates(int $viewerId, int $limit = 6): array
    {
        $day = self::DAY_SQL;
        return self::fetchAll(
            "SELECT x.* FROM (
                SELECT a.*, $day AS day_index,
                       (SELECT COUNT(*) FROM ad_impressions i WHERE i.campaign_id = a.id AND i.day_index = $day) AS today
                FROM ad_campaigns a
                JOIN users u ON u.id = a.user_id AND u.status = 'active'
                WHERE a.status = 'active' AND a.starts_at <= NOW() AND a.ends_at > NOW() AND a.user_id <> ?
                  AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = a.user_id) OR (b.blocker_id = a.user_id AND b.blocked_id = ?))
                  AND NOT EXISTS (SELECT 1 FROM ad_impressions s WHERE s.campaign_id = a.id AND s.day_index = $day AND s.user_id = ?)
             ) x
             WHERE x.today < x.reach_max
             ORDER BY x.today / x.reach_max ASC, RAND()
             LIMIT " . max(1, min(20, $limit)),
            [$viewerId, $viewerId, $viewerId, $viewerId]
        );
    }

    /** Anota que $viewerId vio la campaña el día $day. Devuelve true si es la primera vez ese día. */
    public static function recordImpression(int $id, int $day, int $viewerId): bool
    {
        $added = self::execute('INSERT IGNORE INTO ad_impressions (campaign_id, day_index, user_id) VALUES (?, ?, ?)', [$id, $day, $viewerId]) > 0;
        if ($added) {
            self::execute('UPDATE ad_campaigns SET impressions = impressions + 1 WHERE id = ?', [$id]);
        }
        return $added;
    }

    /** Primer toque de $viewerId en el anuncio durante el día en curso (cada persona cuenta una vez por día). */
    public static function recordClick(int $id, int $viewerId): void
    {
        $updated = self::execute(
            'UPDATE ad_impressions i JOIN ad_campaigns a ON a.id = i.campaign_id
             SET i.clicked_at = NOW()
             WHERE i.campaign_id = ? AND i.user_id = ? AND i.clicked_at IS NULL AND i.day_index = ' . self::DAY_SQL,
            [$id, $viewerId]
        );
        if ($updated > 0) {
            self::execute('UPDATE ad_campaigns SET clicks = clicks + 1 WHERE id = ?', [$id]);
        }
    }

    /** Campañas de una persona, de la más reciente a la más antigua. */
    public static function forUser(int $userId, int $before, int $limit): array
    {
        $limit = max(1, min(50, $limit));
        $rows = self::fetchAll(
            self::SELECT . ' WHERE a.user_id = ?' . ($before > 0 ? ' AND a.id < ?' : '') . ' ORDER BY a.id DESC LIMIT ' . ($limit + 1),
            $before > 0 ? [$userId, $before] : [$userId]
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    public static function pendingCount(int $userId): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM ad_campaigns WHERE user_id = ? AND status = 'pending'", [$userId]);
    }

    /** Campañas esperando revisión (globo del panel). Sin la tabla (migración pendiente) cuenta 0. */
    public static function reviewCount(): int
    {
        try {
            return (int) self::fetchValue("SELECT COUNT(*) FROM ad_campaigns WHERE status = 'pending'");
        } catch (\Throwable) {
            return 0;
        }
    }

    /** Panel: campañas por estado (pending = las más antiguas primero, para revisarlas en orden). */
    public static function adminList(string $status, int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $order = $status === 'pending' ? 'a.id ASC' : 'a.id DESC';
        $where = match ($status) {
            'pending' => "a.status = 'pending'",
            'active'  => "a.status = 'active'",
            default   => "a.status IN ('finished', 'rejected', 'cancelled', 'removed')",
        };
        $rows = self::fetchAll(
            self::SELECT . " WHERE $where ORDER BY $order LIMIT " . ($limit + 1) . ' OFFSET ' . ((max(1, $page) - 1) * $limit)
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Totales del panel: pendientes, activas y lo cobrado (sin lo devuelto). */
    public static function totals(): array
    {
        $row = self::fetchOne(
            "SELECT SUM(status = 'pending') AS pending, SUM(status = 'active') AS active,
                    COALESCE(SUM(CASE WHEN status IN ('active', 'finished', 'cancelled', 'removed') THEN total_cents - refunded_cents ELSE 0 END), 0) AS revenue
             FROM ad_campaigns"
        ) ?? [];
        return ['pending' => (int) ($row['pending'] ?? 0), 'active' => (int) ($row['active'] ?? 0), 'revenue' => (int) ($row['revenue'] ?? 0)];
    }

    /** Publicaciones públicas propias (fuera de comunidades) que se pueden promocionar. */
    public static function promotablePosts(int $userId, int $limit = 30): array
    {
        return self::fetchAll(
            "SELECT p.id, p.body, p.created_at, p.likes_count, p.comments_count,
                    (SELECT CASE WHEN pm.type = 'video' THEN pm.poster_path ELSE pm.path END
                     FROM post_media pm WHERE pm.post_id = p.id ORDER BY pm.position LIMIT 1) AS thumb
             FROM posts p
             WHERE p.user_id = ? AND p.status = 'published' AND p.visibility = 'public' AND p.community_id IS NULL
             ORDER BY p.id DESC LIMIT " . max(1, min(60, $limit)),
            [$userId]
        );
    }

    /** Comunidades públicas y activas que administra la persona. */
    public static function promotableCommunities(int $userId): array
    {
        return self::fetchAll(
            "SELECT id, slug, name, avatar_path, members_count FROM communities
             WHERE owner_id = ? AND status = 'active' AND visibility = 'public' ORDER BY name LIMIT 50",
            [$userId]
        );
    }

    /** Grupos públicos en los que la persona es dueña o administradora. */
    public static function promotableGroups(int $userId): array
    {
        return self::fetchAll(
            "SELECT c.id, c.title, c.avatar_path, c.invite_code,
                    (SELECT COUNT(*) FROM conversation_participants gm WHERE gm.conversation_id = c.id AND gm.left_at IS NULL) AS members_count
             FROM conversations c
             JOIN conversation_participants me ON me.conversation_id = c.id AND me.user_id = ? AND me.left_at IS NULL AND me.role IN ('owner', 'admin')
             WHERE c.type = 'group' AND c.visibility = 'public' ORDER BY c.title LIMIT 50",
            [$userId]
        );
    }

    /** Grupo público para la tarjeta del anuncio, con si quien mira ya es miembro. */
    public static function publicGroup(int $groupId, int $viewerId): ?array
    {
        return self::fetchOne(
            "SELECT c.id, c.title, c.description, c.avatar_path, c.cover_path, c.invite_code,
                    (SELECT COUNT(*) FROM conversation_participants gm WHERE gm.conversation_id = c.id AND gm.left_at IS NULL) AS members_count,
                    EXISTS (SELECT 1 FROM conversation_participants me WHERE me.conversation_id = c.id AND me.user_id = ? AND me.left_at IS NULL) AS is_member
             FROM conversations c WHERE c.id = ? AND c.type = 'group' AND c.visibility = 'public' LIMIT 1",
            [$viewerId, $groupId]
        );
    }
}
