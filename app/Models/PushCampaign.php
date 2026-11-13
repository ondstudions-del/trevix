<?php
declare(strict_types=1);

namespace Trevix\Models;

/** Avisos enviados desde el panel de administración (a una persona o masivos) con su avance y resultado. */
final class PushCampaign extends Model
{
    public const AUDIENCES = ['user', 'all', 'android', 'ios'];

    public static function create(int $adminId, string $title, string $body, ?string $link, string $audience, ?int $targetUserId, int $total): int
    {
        self::execute(
            'INSERT INTO push_campaigns (admin_id, title, body, link, audience, target_user_id, total) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$adminId, $title, $body, $link, $audience, $targetUserId, $total]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT * FROM push_campaigns WHERE id = ?', [$id]);
    }

    public static function progress(int $id, int $lastDeviceId, int $sent, int $failed): void
    {
        self::execute(
            'UPDATE push_campaigns SET last_device_id = ?, sent = sent + ?, failed = failed + ? WHERE id = ?',
            [$lastDeviceId, $sent, $failed, $id]
        );
    }

    public static function finish(int $id, string $status, ?string $error = null): void
    {
        self::execute(
            'UPDATE push_campaigns SET status = ?, error = ?, finished_at = NOW() WHERE id = ?',
            [$status, $error, $id]
        );
    }

    /** Envíos que llevan un rato sin terminar (el servidor cortó la tarea): el panel ofrece continuarlos. */
    public static function stalled(array $campaign): bool
    {
        return $campaign['status'] === 'sending' && strtotime((string) $campaign['created_at']) < time() - 600;
    }

    public static function recent(int $limit = 20): array
    {
        return self::fetchAll(
            'SELECT c.*, a.username AS admin_username, t.username AS target_username
             FROM push_campaigns c
             LEFT JOIN users a ON a.id = c.admin_id
             LEFT JOIN users t ON t.id = c.target_user_id
             ORDER BY c.id DESC LIMIT ' . max(1, min(100, $limit))
        );
    }
}
