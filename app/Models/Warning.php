<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Advertencias que el equipo de moderación da a una cuenta. Son vigentes mientras no se retiren; las de los
 * últimos N días (app.verification.warning_days) impiden pedir el verificado.
 */
final class Warning extends Model
{
    /** Lo que pudo motivar una advertencia (además de la cuenta en general). */
    public const TARGET_TYPES = ['post', 'comment', 'message', 'story', 'user', 'community'];

    public static function create(int $userId, int $issuedBy, string $reason, ?string $targetType, ?int $targetId): int
    {
        self::execute(
            'INSERT INTO user_warnings (user_id, issued_by, reason, target_type, target_id) VALUES (?, ?, ?, ?, ?)',
            [$userId, $issuedBy, $reason, in_array($targetType, self::TARGET_TYPES, true) ? $targetType : null, $targetId]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT id, user_id, issued_by, reason, target_type, target_id, created_at, revoked_at FROM user_warnings WHERE id = ?', [$id]);
    }

    /**
     * Advertencias de una cuenta, la más reciente primero. $withStaff añade quién la dio y quién la retiró
     * (solo para el equipo).
     */
    public static function forUser(int $userId, bool $withStaff = false, int $limit = 50): array
    {
        $rows = self::fetchAll(
            'SELECT w.id, w.reason, w.target_type, w.target_id, w.created_at, w.revoked_at,
                    i.username AS issued_by_username, r.username AS revoked_by_username
             FROM user_warnings w
             LEFT JOIN users i ON i.id = w.issued_by
             LEFT JOIN users r ON r.id = w.revoked_by
             WHERE w.user_id = ?
             ORDER BY w.created_at DESC, w.id DESC
             LIMIT ' . max(1, min(200, $limit)),
            [$userId]
        );
        foreach ($rows as &$row) {
            $row['id'] = (int) $row['id'];
            $row['target_id'] = $row['target_id'] !== null ? (int) $row['target_id'] : null;
            $row['revoked'] = $row['revoked_at'] !== null;
            if (!$withStaff) {
                unset($row['issued_by_username'], $row['revoked_by_username']);
            }
        }
        unset($row);
        return $rows;
    }

    /** Fecha de la advertencia vigente más reciente dentro de los últimos $days días (null si no hay). */
    public static function latestActiveSince(int $userId, int $days): ?string
    {
        $value = self::fetchValue(
            'SELECT MAX(created_at) FROM user_warnings WHERE user_id = ? AND revoked_at IS NULL AND created_at > (NOW() - INTERVAL ? DAY)',
            [$userId, $days]
        );
        return is_string($value) ? $value : null;
    }

    public static function activeCountSince(int $userId, int $days): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM user_warnings WHERE user_id = ? AND revoked_at IS NULL AND created_at > (NOW() - INTERVAL ? DAY)',
            [$userId, $days]
        );
    }

    /** Retira una advertencia vigente. Devuelve false si ya estaba retirada. */
    public static function revoke(int $id, int $revokedBy): bool
    {
        return self::execute(
            'UPDATE user_warnings SET revoked_at = NOW(), revoked_by = ? WHERE id = ? AND revoked_at IS NULL',
            [$revokedBy, $id]
        ) > 0;
    }
}
