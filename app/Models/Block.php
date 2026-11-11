<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Bloqueos entre usuarios. Bloquear rompe el seguimiento en ambos sentidos y las solicitudes pendientes;
 * las consultas de publicaciones, perfiles, comentarios y búsqueda ya excluyen a las cuentas bloqueadas.
 */
final class Block extends Model
{
    public static function exists(int $blockerId, int $blockedId): bool
    {
        return (bool) self::fetchValue(
            'SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ? LIMIT 1',
            [$blockerId, $blockedId]
        );
    }

    public static function block(int $blockerId, int $blockedId): void
    {
        Database::transaction(static function () use ($blockerId, $blockedId): void {
            self::execute('INSERT IGNORE INTO blocks (blocker_id, blocked_id) VALUES (?, ?)', [$blockerId, $blockedId]);
            Follow::severBetween($blockerId, $blockedId);
            Notification::removeBetween($blockerId, $blockedId);
            ProfileAlert::removeBetween($blockerId, $blockedId);
        });
    }

    public static function unblock(int $blockerId, int $blockedId): bool
    {
        return self::execute('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?', [$blockerId, $blockedId]) === 1;
    }

    /** Cuentas que bloqueó el usuario, de la más reciente a la más antigua. */
    public static function listFor(int $userId, int $limit = 100): array
    {
        return self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, b.created_at AS blocked_at
             FROM blocks b JOIN users u ON u.id = b.blocked_id
             WHERE b.blocker_id = ? AND u.status <> 'deleted'
             ORDER BY b.created_at DESC LIMIT " . max(1, min(500, $limit)),
            [$userId]
        );
    }
}
