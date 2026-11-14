<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Lo nuevo para los avisos del teléfono (la app de Android lo consulta en segundo plano, sin Firebase): mensajes,
 * solicitudes de seguimiento y reacciones a tus mensajes posteriores a los cursores que guarda la app. Respeta los
 * chats silenciados, los bloqueos, «eliminar para ti», los mensajes temporales caducados y lo ya leído.
 */
final class Push extends Model
{
    /** Mensajes sin leer posteriores a $afterId en conversaciones no silenciadas, del más antiguo al más reciente. */
    public static function messages(int $userId, int $afterId, int $limit): array
    {
        return self::fetchAll(
            "SELECT m.id, m.conversation_id, m.sender_id, m.kind, m.context, m.body, m.e2ee_epoch, m.media_path, m.media_mime,
                    m.media_cleared_at, m.view_once, m.gif_kind, m.location_lat, m.story_id, m.shared_post_id, m.deleted_at, m.created_at, cp.nickname,
                    c.type AS conversation_type, c.title AS group_title, c.avatar_path AS group_avatar,
                    u.id AS user_id, u.username, u.display_name, u.avatar_path, u.is_verified
             FROM conversation_participants cp
             JOIN conversations c ON c.id = cp.conversation_id
             JOIN messages m ON m.conversation_id = cp.conversation_id AND m.id > ? AND m.id > COALESCE(cp.last_read_message_id, 0)
                  AND m.created_at >= cp.joined_at
             JOIN users u ON u.id = m.sender_id AND u.status = 'active'
             WHERE cp.user_id = ? AND cp.left_at IS NULL AND cp.is_muted = 0
               AND m.sender_id <> ? AND m.kind = 'message' AND m.deleted_at IS NULL
               AND (m.expires_at IS NULL OR m.expires_at > NOW())
               AND NOT EXISTS (SELECT 1 FROM message_hidden h WHERE h.message_id = m.id AND h.user_id = ?)
               AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = m.sender_id)
                                                        OR (b.blocker_id = m.sender_id AND b.blocked_id = ?))
             ORDER BY m.id ASC LIMIT " . max(1, min(50, $limit)),
            [$afterId, $userId, $userId, $userId, $userId, $userId]
        );
    }

    /** Solicitudes de seguimiento pendientes posteriores a $afterId (si la persona tiene activos los avisos de seguidores). */
    public static function followRequests(int $userId, int $afterId, int $limit): array
    {
        return self::fetchAll(
            "SELECT fr.id, u.id AS user_id, u.username, u.display_name, u.avatar_path, u.is_verified
             FROM follow_requests fr
             JOIN users me ON me.id = fr.target_id AND me.notify_follows = 1
             JOIN users u ON u.id = fr.requester_id AND u.status = 'active'
             WHERE fr.target_id = ? AND fr.status = 'pending' AND fr.id > ?
             ORDER BY fr.id ASC LIMIT " . max(1, min(20, $limit)),
            [$userId, $afterId]
        );
    }

    /**
     * Reacciones a mensajes propios entre $since (excluido) y $until (incluido), en chats no silenciados. Los
     * cursores son fechas de la base de datos: la app envía el `until` anterior como `since`.
     */
    public static function reactions(int $userId, string $since, string $until, int $limit): array
    {
        return self::fetchAll(
            "SELECT r.message_id, r.emoji, r.created_at, m.conversation_id, m.body, m.e2ee_epoch, m.media_path, m.media_mime,
                    m.media_cleared_at, m.view_once, m.gif_kind, m.location_lat, m.shared_post_id, m.context, m.deleted_at, cp.nickname,
                    u.id AS user_id, u.username, u.display_name, u.avatar_path, u.is_verified
             FROM message_reactions r
             JOIN messages m ON m.id = r.message_id AND m.sender_id = ? AND m.deleted_at IS NULL
             JOIN conversation_participants cp ON cp.conversation_id = m.conversation_id AND cp.user_id = ?
                  AND cp.left_at IS NULL AND cp.is_muted = 0
             JOIN users u ON u.id = r.user_id AND u.status = 'active'
             WHERE r.created_at > ? AND r.created_at <= ? AND r.user_id <> ?
               AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = r.user_id)
                                                        OR (b.blocker_id = r.user_id AND b.blocked_id = ?))
             ORDER BY r.created_at ASC LIMIT " . max(1, min(20, $limit)),
            [$userId, $userId, $since, $until, $userId, $userId, $userId]
        );
    }

    /** Cursores iniciales: lo más reciente que ya existe (la primera consulta no avisa de nada antiguo). */
    public static function cursors(int $userId): array
    {
        $row = self::fetchOne(
            'SELECT (SELECT COALESCE(MAX(id), 0) FROM notifications WHERE user_id = ?) AS n,
                    (SELECT COALESCE(MAX(id), 0) FROM messages) AS m,
                    (SELECT COALESCE(MAX(id), 0) FROM follow_requests WHERE target_id = ?) AS f,
                    DATE_SUB(NOW(), INTERVAL 1 SECOND) AS r',
            [$userId, $userId]
        ) ?? [];
        return ['n' => (int) ($row['n'] ?? 0), 'm' => (int) ($row['m'] ?? 0), 'f' => (int) ($row['f'] ?? 0), 'r' => (string) ($row['r'] ?? '')];
    }

    /** Fin de la ventana de reacciones de esta consulta (un segundo atrás, para no perder las del segundo en curso). */
    public static function until(): string
    {
        return (string) self::fetchValue('SELECT DATE_SUB(NOW(), INTERVAL 1 SECOND)');
    }
}
