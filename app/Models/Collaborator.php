<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Colaboradores: plan de suscripción (precio en USD por N días), suscripciones compradas desde el monedero y
 * cifras para los requisitos. Una suscripción da acceso mientras expires_at sea futuro.
 */
final class Collaborator extends Model
{
    public static function plan(int $userId): ?array
    {
        return self::fetchOne(
            'SELECT user_id, price_cents, period_days, description, is_active, activated_at, updated_at FROM collaborator_plans WHERE user_id = ?',
            [$userId]
        );
    }

    /** @return array<int, array> planes activos indexados por id de la cuenta */
    public static function activePlans(array $userIds): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $userIds))));
        if ($ids === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT user_id, price_cents, period_days, description FROM collaborator_plans
             WHERE is_active = 1 AND user_id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')',
            $ids
        );
        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r['user_id']] = $r;
        }
        return $out;
    }

    public static function savePlan(int $userId, int $priceCents, int $days, ?string $description, bool $active): void
    {
        self::execute(
            'INSERT INTO collaborator_plans (user_id, price_cents, period_days, description, is_active) VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE price_cents = VALUES(price_cents), period_days = VALUES(period_days),
                                     description = VALUES(description), is_active = VALUES(is_active)',
            [$userId, $priceCents, $days, $description, $active ? 1 : 0]
        );
    }

    public static function setActive(int $userId, bool $active): bool
    {
        return self::execute('UPDATE collaborator_plans SET is_active = ? WHERE user_id = ?', [$active ? 1 : 0, $userId]) > 0;
    }

    /** Fin del acceso vigente de $subscriberId a $collaboratorId, o null si no tiene. */
    public static function accessUntil(int $subscriberId, int $collaboratorId, bool $forUpdate = false): ?string
    {
        $value = self::fetchValue(
            'SELECT MAX(expires_at) FROM collaborator_subscriptions WHERE subscriber_id = ? AND collaborator_id = ? AND expires_at > NOW()'
            . ($forUpdate ? ' FOR UPDATE' : ''),
            [$subscriberId, $collaboratorId]
        );
        return $value !== null && $value !== false ? (string) $value : null;
    }

    public static function createSubscription(int $collaboratorId, int $subscriberId, int $price, int $commission, int $days, string $startsAt): int
    {
        self::execute(
            'INSERT INTO collaborator_subscriptions (collaborator_id, subscriber_id, price_cents, commission_cents, earning_cents, period_days, starts_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ? + INTERVAL ? DAY)',
            [$collaboratorId, $subscriberId, $price, $commission, $price - $commission, $days, $startsAt, $startsAt, $days]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function subscription(int $id): ?array
    {
        return self::fetchOne('SELECT id, collaborator_id, subscriber_id, price_cents, commission_cents, earning_cents, period_days, starts_at, expires_at, created_at
             FROM collaborator_subscriptions WHERE id = ?', [$id]);
    }

    /** Suscriptores con acceso vigente. */
    public static function activeSubscribers(int $collaboratorId): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(DISTINCT subscriber_id) FROM collaborator_subscriptions WHERE collaborator_id = ? AND expires_at > NOW()',
            [$collaboratorId]
        );
    }

    /** Lo recibido por suscripciones (ya sin la comisión) y cuántas se vendieron. */
    public static function earnings(int $collaboratorId): array
    {
        $row = self::fetchOne(
            'SELECT COUNT(*) AS sales, COALESCE(SUM(earning_cents), 0) AS earned, COALESCE(SUM(commission_cents), 0) AS commission
             FROM collaborator_subscriptions WHERE collaborator_id = ?',
            [$collaboratorId]
        );
        return array_map('intval', $row ?? ['sales' => 0, 'earned' => 0, 'commission' => 0]);
    }

    /** Suscriptores (vigentes primero), con su acceso más largo. */
    public static function subscribers(int $collaboratorId, int $page, int $limit): array
    {
        $limit = max(1, min(50, $limit));
        $rows = self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, MAX(s.expires_at) AS expires_at,
                    MIN(s.created_at) AS since, COUNT(*) AS purchases
             FROM collaborator_subscriptions s JOIN users u ON u.id = s.subscriber_id AND u.status = 'active'
             WHERE s.collaborator_id = ?
             GROUP BY u.id, u.username, u.display_name, u.avatar_path, u.is_verified
             ORDER BY (MAX(s.expires_at) > NOW()) DESC, MAX(s.expires_at) DESC
             LIMIT " . ($limit + 1) . ' OFFSET ' . ((max(1, $page) - 1) * $limit),
            [$collaboratorId]
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Colaboradores a los que está suscrita la persona (vigentes primero). */
    public static function subscriptionsOf(int $subscriberId, int $page, int $limit): array
    {
        $limit = max(1, min(50, $limit));
        $rows = self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, MAX(s.expires_at) AS expires_at,
                    p.price_cents, p.period_days, p.is_active AS plan_active
             FROM collaborator_subscriptions s
             JOIN users u ON u.id = s.collaborator_id AND u.status = 'active'
             LEFT JOIN collaborator_plans p ON p.user_id = s.collaborator_id
             WHERE s.subscriber_id = ?
             GROUP BY u.id, u.username, u.display_name, u.avatar_path, u.is_verified, p.price_cents, p.period_days, p.is_active
             ORDER BY (MAX(s.expires_at) > NOW()) DESC, MAX(s.expires_at) DESC
             LIMIT " . ($limit + 1) . ' OFFSET ' . ((max(1, $page) - 1) * $limit),
            [$subscriberId]
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Publicaciones solo para suscriptores que tiene publicadas la cuenta. */
    public static function exclusivePosts(int $userId): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM posts WHERE user_id = ? AND visibility = 'subscribers' AND status = 'published'",
            [$userId]
        );
    }

    /**
     * Visualizaciones únicas promedio de las publicaciones propias (sin compartidos ni comunidades) de los
     * últimos $days días.
     */
    public static function viewStats(int $userId, int $days): array
    {
        $row = self::fetchOne(
            "SELECT COUNT(*) AS posts, COALESCE(AVG(v.views), 0) AS avg_views FROM (
                SELECT (SELECT COUNT(*) FROM post_views pv WHERE pv.post_id = p.id) AS views
                FROM posts p
                WHERE p.user_id = ? AND p.status = 'published' AND p.shared_post_id IS NULL AND p.community_id IS NULL
                  AND p.created_at > (NOW() - INTERVAL ? DAY)
             ) v",
            [$userId, max(1, $days)]
        );
        return ['posts' => (int) ($row['posts'] ?? 0), 'avg_views' => (int) floor((float) ($row['avg_views'] ?? 0))];
    }

    /** Colaboradores para el panel: plan, suscriptores vigentes, ventas, lo ganado y la comisión. */
    public static function adminList(int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $rows = self::fetchAll(
            'SELECT p.user_id, p.price_cents, p.period_days, p.is_active, p.activated_at, u.username, u.display_name, u.avatar_path,
                    u.is_verified, u.followers_count, u.status AS user_status,
                    (SELECT COUNT(DISTINCT s.subscriber_id) FROM collaborator_subscriptions s WHERE s.collaborator_id = p.user_id AND s.expires_at > NOW()) AS subscribers,
                    (SELECT COUNT(*) FROM collaborator_subscriptions s WHERE s.collaborator_id = p.user_id) AS sales,
                    (SELECT COALESCE(SUM(s.earning_cents), 0) FROM collaborator_subscriptions s WHERE s.collaborator_id = p.user_id) AS earned,
                    (SELECT COALESCE(SUM(s.commission_cents), 0) FROM collaborator_subscriptions s WHERE s.collaborator_id = p.user_id) AS commission
             FROM collaborator_plans p JOIN users u ON u.id = p.user_id
             ORDER BY p.is_active DESC, earned DESC, p.activated_at DESC
             LIMIT ' . ($limit + 1) . ' OFFSET ' . ((max(1, $page) - 1) * $limit)
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }
}
