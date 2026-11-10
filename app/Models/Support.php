<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;

/**
 * Atención al cliente: la cuenta de soporte (app.ix.username), los mensajes de su chat que necesita IX y las
 * solicitudes clasificadas (support_tickets) que revisa el equipo en el panel.
 */
final class Support extends Model
{
    public const CATEGORIES = [
        'pregunta'   => 'Pregunta',
        'saludo'     => 'Saludo',
        'error'      => 'Error',
        'sugerencia' => 'Sugerencia',
        'reporte'    => 'Reporte',
        'queja'      => 'Queja',
        'reclamo'    => 'Reclamo',
        'peticion'   => 'Petición',
        'otro'       => 'Otro',
    ];

    public const PRIORITIES = ['baja' => 'Baja', 'media' => 'Media', 'alta' => 'Alta'];

    public const STATUSES = ['open' => 'Abiertas', 'closed' => 'Cerradas'];

    /** Categorías que siempre abren una solicitud para el equipo. */
    public const TICKET_CATEGORIES = ['error', 'sugerencia', 'reporte', 'queja', 'reclamo', 'peticion'];

    private static array|false|null $account = null;

    /** La cuenta de soporte activa, o null si no existe. */
    public static function account(): ?array
    {
        if (self::$account === null) {
            $username = mb_strtolower(trim((string) Config::get('app.ix.username', '')));
            self::$account = $username !== ''
                ? (self::fetchOne("SELECT id, username, display_name FROM users WHERE username = ? AND status = 'active' LIMIT 1", [$username]) ?? false)
                : false;
        }
        return self::$account ?: null;
    }

    public static function accountId(): ?int
    {
        $account = self::account();
        return $account !== null ? (int) $account['id'] : null;
    }

    public static function isAccount(int $userId): bool
    {
        return $userId > 0 && self::accountId() === $userId;
    }

    /** Datos de la persona que IX puede usar para atenderla (nada privado: ni correo ni contraseña). */
    public static function userContext(int $userId): ?array
    {
        return self::fetchOne(
            "SELECT u.id, u.username, u.display_name, u.status, u.is_verified, u.is_private, u.account_type, u.created_at,
                    u.email_verified_at IS NOT NULL AS email_verified, u.followers_count, u.posts_count,
                    (SELECT COUNT(*) FROM user_warnings w WHERE w.user_id = u.id AND w.revoked_at IS NULL) AS warnings
             FROM users u WHERE u.id = ? LIMIT 1",
            [$userId]
        );
    }

    /** Último mensaje de la persona en el chat (para responder solo al más reciente de una ráfaga). */
    public static function lastMessageFrom(int $conversationId, int $userId): int
    {
        return (int) self::fetchValue(
            "SELECT COALESCE(MAX(id), 0) FROM messages WHERE conversation_id = ? AND sender_id = ? AND kind = 'message' AND deleted_at IS NULL",
            [$conversationId, $userId]
        );
    }

    /** Hay una respuesta de soporte (de IX o del equipo) posterior al mensaje. */
    public static function answeredAfter(int $conversationId, int $supportId, int $messageId): bool
    {
        return (bool) self::fetchValue(
            "SELECT 1 FROM messages WHERE conversation_id = ? AND sender_id = ? AND id > ? AND kind = 'message' LIMIT 1",
            [$conversationId, $supportId, $messageId]
        );
    }

    /** Alguien del equipo escribió en el chat desde la cuenta de soporte en las últimas $hours horas. */
    public static function humanActive(int $conversationId, int $supportId, int $hours): bool
    {
        return $hours > 0 && (bool) self::fetchValue(
            "SELECT 1 FROM messages WHERE conversation_id = ? AND sender_id = ? AND sent_by_ix = 0 AND kind = 'message'
               AND created_at > NOW() - INTERVAL ? HOUR LIMIT 1",
            [$conversationId, $supportId, $hours]
        );
    }

    /** Últimos $limit mensajes del chat, del más antiguo al más reciente. */
    public static function history(int $conversationId, int $limit): array
    {
        $rows = self::fetchAll(
            "SELECT id, sender_id, body, context, e2ee_epoch, media_path, media_mime, media_cleared_at, view_once, gif_kind,
                    gif_title, location_lat, location_name, song_id, story_id, sent_by_ix, created_at
             FROM messages
             WHERE conversation_id = ? AND kind = 'message' AND deleted_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())
             ORDER BY id DESC LIMIT " . max(1, min(60, $limit)),
            [$conversationId]
        );
        return array_reverse($rows);
    }

    public static function markIx(int $messageId): void
    {
        self::execute('UPDATE messages SET sent_by_ix = 1 WHERE id = ?', [$messageId]);
    }

    /**
     * Registra la solicitud: si la persona ya tiene una abierta de la misma categoría actualizada en las últimas
     * 24 horas, la actualiza (sube la prioridad, nunca la baja); si no, crea una nueva. Devuelve su id.
     */
    public static function saveTicket(int $userId, ?int $conversationId, ?int $messageId, string $category, string $priority, string $summary, string $excerpt, bool $needsHuman): int
    {
        $category = isset(self::CATEGORIES[$category]) ? $category : 'otro';
        $priority = isset(self::PRIORITIES[$priority]) ? $priority : 'media';
        $summary = mb_substr(trim((string) preg_replace('/\s+/u', ' ', $summary)), 0, 255);
        $excerpt = mb_substr(trim((string) preg_replace('/\s+/u', ' ', $excerpt)), 0, 500);

        $open = self::fetchOne(
            "SELECT id, priority FROM support_tickets
             WHERE user_id = ? AND category = ? AND status = 'open' AND updated_at > NOW() - INTERVAL 24 HOUR
             ORDER BY id DESC LIMIT 1",
            [$userId, $category]
        );
        if ($open !== null) {
            $order = array_keys(self::PRIORITIES);
            if (array_search($open['priority'], $order, true) > array_search($priority, $order, true)) {
                $priority = (string) $open['priority'];
            }
            self::execute(
                'UPDATE support_tickets SET message_id = COALESCE(?, message_id), priority = ?, summary = ?, excerpt = ?,
                        needs_human = GREATEST(needs_human, ?), updated_at = NOW()
                 WHERE id = ?',
                [$messageId, $priority, $summary, $excerpt, $needsHuman ? 1 : 0, (int) $open['id']]
            );
            return (int) $open['id'];
        }
        self::execute(
            'INSERT INTO support_tickets (user_id, conversation_id, message_id, category, priority, summary, excerpt, needs_human)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [$userId, $conversationId, $messageId, $category, $priority, $summary, $excerpt, $needsHuman ? 1 : 0]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function findTicket(int $id): ?array
    {
        return self::fetchOne(
            'SELECT t.*, u.username, u.display_name FROM support_tickets t JOIN users u ON u.id = t.user_id WHERE t.id = ? LIMIT 1',
            [$id]
        );
    }

    public static function openCount(): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM support_tickets WHERE status = 'open'");
    }

    /** Cuántas hay abiertas y cerradas (pestañas del panel). */
    public static function counts(): array
    {
        $counts = array_fill_keys(array_keys(self::STATUSES), 0);
        foreach (self::fetchAll('SELECT status, COUNT(*) AS n FROM support_tickets GROUP BY status') as $row) {
            $counts[$row['status']] = (int) $row['n'];
        }
        return $counts;
    }

    /**
     * Solicitudes para el panel: las abiertas primero las que piden a una persona y las de prioridad alta.
     *
     * @return array{tickets: list<array>, hasMore: bool}
     */
    public static function adminList(string $status, ?string $category, int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $params = [$status];
        $where = 't.status = ?';
        if ($category !== null) {
            $where .= ' AND t.category = ?';
            $params[] = $category;
        }
        $order = $status === 'open'
            ? "t.needs_human DESC, FIELD(t.priority, 'alta', 'media', 'baja'), t.updated_at DESC"
            : 't.closed_at DESC';
        $rows = self::fetchAll(
            "SELECT t.*, u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS user_status, c.username AS closer_username
             FROM support_tickets t
             JOIN users u ON u.id = t.user_id
             LEFT JOIN users c ON c.id = t.closed_by
             WHERE $where
             ORDER BY $order, t.id DESC
             LIMIT " . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return ['tickets' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    public static function close(int $id, int $staffId): bool
    {
        return self::execute(
            "UPDATE support_tickets SET status = 'closed', closed_by = ?, closed_at = NOW() WHERE id = ? AND status = 'open'",
            [$staffId, $id]
        ) > 0;
    }

    public static function reopen(int $id): bool
    {
        return self::execute(
            "UPDATE support_tickets SET status = 'open', closed_by = NULL, closed_at = NULL, updated_at = NOW() WHERE id = ? AND status = 'closed'",
            [$id]
        ) > 0;
    }
}
