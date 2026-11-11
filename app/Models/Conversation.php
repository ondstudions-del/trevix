<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;
use Trevix\Core\Database;

/**
 * Conversaciones: directas entre dos personas y grupos. En las directas, direct_key ("menorId:mayorId") garantiza
 * una sola conversación por pareja y se crea al enviar el primer mensaje (o al preparar el cifrado), no al abrir el
 * chat. Los grupos tienen nombre, foto, portada, descripción, estilo, roles y enlace de invitación (ver Group).
 * Lo no leído se calcula con el último mensaje leído de cada participante.
 */
final class Conversation extends Model
{
    /** Mensajes de otras personas posteriores al último leído (alias cp = participante que mira). */
    private const UNREAD_SQL = "SELECT COUNT(*) FROM messages um WHERE um.conversation_id = cp.conversation_id
        AND um.id > COALESCE(cp.last_read_message_id, 0) AND (um.sender_id IS NULL OR um.sender_id <> cp.user_id)
        AND um.deleted_at IS NULL AND um.kind = 'message' AND (um.expires_at IS NULL OR um.expires_at > NOW())
        AND um.created_at >= cp.joined_at AND um.id > COALESCE(cp.cleared_until_id, 0)";

    /** Último mensaje que ve el participante cp (sin caducados, ocultos o vaciados para él ni anteriores a su entrada). */
    private const LAST_VISIBLE_SQL = 'SELECT MAX(lm.id) FROM messages lm WHERE lm.conversation_id = c.id
        AND (lm.expires_at IS NULL OR lm.expires_at > NOW()) AND lm.created_at >= cp.joined_at AND lm.id > COALESCE(cp.cleared_until_id, 0)
        AND NOT EXISTS (SELECT 1 FROM message_hidden lh WHERE lh.message_id = lm.id AND lh.user_id = cp.user_id)';

    /** Hay un bloqueo entre quien mira (cp) y la otra persona (u) de un chat directo. */
    private const BLOCKED_SQL = 'SELECT COUNT(*) FROM blocks b WHERE (b.blocker_id = cp.user_id AND b.blocked_id = u.id)
        OR (b.blocker_id = u.id AND b.blocked_id = cp.user_id)';

    /** Alguien más del chat escribió en los últimos segundos (alias cp = participante que mira). */
    private const TYPING_SQL = 'SELECT COUNT(*) FROM conversation_participants tp WHERE tp.conversation_id = cp.conversation_id
        AND tp.user_id <> cp.user_id AND tp.left_at IS NULL AND tp.typing_at > NOW() - INTERVAL 6 SECOND';

    private const MEMBERS_SQL = 'SELECT COUNT(*) FROM conversation_participants gm WHERE gm.conversation_id = c.id AND gm.left_at IS NULL';

    /** Columnas comunes de la bandeja y de una conversación. */
    private const FIELDS = 'c.id, c.type, c.title, c.description, c.avatar_path AS group_avatar, c.cover_path AS group_cover, c.theme,
        c.wallpaper, c.visibility, c.invite_code, c.e2ee, c.key_epoch, c.last_message_at, c.disappear_seconds, cp.role, cp.is_muted,
        cp.nickname, cp.pinned_at, cp.is_favorite, u.id AS partner_id, u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS partner_status,
        u.show_activity, u.last_seen_at';

    /** Chats con mensajes sin leer (los silenciados no cuentan). */
    public static function unreadCount(int $userId): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM conversation_participants cp
             WHERE cp.user_id = ? AND cp.is_muted = 0 AND cp.left_at IS NULL AND (' . self::UNREAD_SQL . ') > 0',
            [$userId]
        );
    }

    public static function directKey(int $a, int $b): string
    {
        return min($a, $b) . ':' . max($a, $b);
    }

    /** Id de la conversación directa entre dos personas, si existe. */
    public static function findDirectId(int $a, int $b): ?int
    {
        $id = self::fetchValue('SELECT id FROM conversations WHERE direct_key = ? LIMIT 1', [self::directKey($a, $b)]);
        return $id !== false ? (int) $id : null;
    }

    /** Crea (o recupera) la conversación directa. Debe llamarse dentro de una transacción. */
    public static function openDirect(int $senderId, int $recipientId): int
    {
        self::execute(
            "INSERT IGNORE INTO conversations (type, direct_key, created_by) VALUES ('direct', ?, ?)",
            [self::directKey($senderId, $recipientId), $senderId]
        );
        $id = (int) self::findDirectId($senderId, $recipientId);
        self::execute(
            'INSERT IGNORE INTO conversation_participants (conversation_id, user_id) VALUES (?, ?), (?, ?)',
            [$id, $senderId, $id, $recipientId]
        );
        return $id;
    }

    /**
     * Bandeja de entrada: primero los chats fijados y después de la más reciente a la más antigua, con la otra
     * persona o los datos del grupo, el último mensaje, cuántos sin leer y si alguien está escribiendo. Incluye los
     * chats con mensajes, los grupos y los vaciados; los eliminados vuelven cuando llega un mensaje nuevo.
     */
    public static function inbox(int $userId, int $limit = 100, string $term = ''): array
    {
        $params = [$userId];
        $where = '';
        $match = 'NULL';
        if ($term !== '') {
            $like = '%' . self::likeEscape(mb_strtolower($term)) . '%';
            $bodyMatch = "FROM messages sm WHERE sm.conversation_id = c.id AND sm.kind = 'message' AND sm.deleted_at IS NULL
                AND sm.e2ee_epoch IS NULL AND (sm.expires_at IS NULL OR sm.expires_at > NOW()) AND sm.created_at >= cp.joined_at
                AND sm.id > COALESCE(cp.cleared_until_id, 0) AND sm.body LIKE ?
                AND NOT EXISTS (SELECT 1 FROM message_hidden sh WHERE sh.message_id = sm.id AND sh.user_id = cp.user_id)";
            $match = "(SELECT sm.body $bodyMatch ORDER BY sm.id DESC LIMIT 1)";
            $where = " AND (u.username LIKE ? OR u.display_name LIKE ? OR cp.nickname LIKE ? OR c.title LIKE ? OR EXISTS (SELECT 1 $bodyMatch))";
            array_unshift($params, $like);
            array_push($params, $like, $like, $like, $like, $like);
        }
        $rows = self::fetchAll(
            'SELECT ' . self::FIELDS . ', (' . self::UNREAD_SQL . ') AS unread, (' . self::BLOCKED_SQL . ') AS blocked,
                    ' . $match . ' AS search_match, IF(c.type = \'group\', (' . self::MEMBERS_SQL . '), 2) AS members_count,
                    m.id AS last_id, m.sender_id AS last_sender, m.kind AS last_kind, m.body AS last_body, m.media_path AS last_media,
                    m.media_mime AS last_mime, m.gif_kind AS last_gif, m.location_lat AS last_location, m.deleted_at AS last_deleted,
                    m.song_id AS last_song, m.context AS last_context, m.e2ee_epoch AS last_e2ee, m.view_once AS last_view_once,
                    m.media_cleared_at AS last_cleared, ms.display_name AS last_sender_name, (' . self::TYPING_SQL . ') AS typing
             FROM conversation_participants cp
             JOIN conversations c ON c.id = cp.conversation_id
             LEFT JOIN conversation_participants op ON c.type = \'direct\' AND op.conversation_id = c.id AND op.user_id <> cp.user_id
             LEFT JOIN users u ON u.id = op.user_id
             LEFT JOIN messages m ON m.id = (' . self::LAST_VISIBLE_SQL . ')
             LEFT JOIN users ms ON ms.id = m.sender_id
             WHERE cp.user_id = ? AND cp.left_at IS NULL AND (m.id IS NOT NULL OR c.type = \'group\' OR cp.cleared_until_id IS NOT NULL)
               AND (cp.hidden_at IS NULL OR COALESCE(c.last_message_id, 0) > COALESCE(cp.cleared_until_id, 0))' . $where . '
             ORDER BY cp.pinned_at IS NULL, cp.pinned_at DESC, COALESCE(c.last_message_at, c.created_at) DESC, c.id DESC
             LIMIT ' . max(1, min(200, $limit)),
            $params
        );
        $viewerShows = self::viewerShowsActivity($userId);
        return array_map(static fn (array $r): array => self::present($r, $userId, $viewerShows), $rows);
    }

    /** Conversación en la que participa el usuario, con los datos de la otra persona o del grupo. */
    public static function findFor(int $conversationId, int $userId): ?array
    {
        $row = self::fetchOne(
            'SELECT ' . self::FIELDS . ', cp.last_read_message_id, u.message_privacy, 0 AS unread,
                    (' . self::BLOCKED_SQL . ') AS blocked, IF(c.type = \'group\', (' . self::MEMBERS_SQL . '), 2) AS members_count,
                    (SELECT COALESCE(MAX(rp.last_read_message_id), 0) FROM conversation_participants rp
                      JOIN users ru ON ru.id = rp.user_id AND ru.read_receipts = 1
                      WHERE rp.conversation_id = c.id AND rp.user_id <> cp.user_id AND rp.left_at IS NULL) AS partner_last_read,
                    NULL AS last_id, NULL AS search_match, 0 AS typing
             FROM conversation_participants cp
             JOIN conversations c ON c.id = cp.conversation_id
             LEFT JOIN conversation_participants op ON c.type = \'direct\' AND op.conversation_id = c.id AND op.user_id <> cp.user_id
             LEFT JOIN users u ON u.id = op.user_id
             WHERE cp.conversation_id = ? AND cp.user_id = ? AND cp.left_at IS NULL
             LIMIT 1',
            [$conversationId, $userId]
        );
        if ($row === null) {
            return null;
        }
        $conversation = self::present($row, $userId, self::viewerShowsActivity($userId));
        $conversation['partner_last_read'] = User::readReceipts($userId) ? (int) ($row['partner_last_read'] ?? 0) : 0;
        $conversation['last_read'] = (int) ($row['last_read_message_id'] ?? 0);
        $conversation['invite_code'] = $row['invite_code'];
        return $conversation;
    }

    /**
     * Motivo por el que $senderId no puede escribir a $recipient, o null si puede.
     * La privacidad de mensajes decide quién puede iniciar una conversación: si la otra persona
     * ya escribió en ella, se le puede responder. También decide quién puede añadirte a un grupo.
     */
    public static function cannotMessage(int $senderId, ?array $recipient, ?int $conversationId): ?string
    {
        if ($recipient === null || ($recipient['status'] ?? '') !== 'active') {
            return 'Esta cuenta no está disponible.';
        }
        $recipientId = (int) $recipient['id'];
        if ($recipientId === $senderId) {
            return 'No puedes enviarte mensajes a ti mismo.';
        }
        if (User::blockedBetween($senderId, $recipientId)) {
            return 'No puedes enviar mensajes a esta cuenta.';
        }
        $privacy = $recipient['message_privacy'] ?? 'everyone';
        if ($privacy === 'everyone' || Support::isAccount($recipientId)) {
            return null;
        }
        if ($conversationId !== null && Message::hasFrom($conversationId, $recipientId)) {
            return null;
        }
        if ($privacy === 'following' && User::follows($recipientId, $senderId)) {
            return null;
        }
        return $privacy === 'nobody'
            ? '@' . $recipient['username'] . ' no recibe mensajes nuevos.'
            : '@' . $recipient['username'] . ' solo recibe mensajes de las personas que sigue.';
    }

    /** Marca como leído hasta $messageId (nunca retrocede). */
    public static function markRead(int $conversationId, int $userId, int $messageId): void
    {
        if ($messageId < 1) {
            return;
        }
        self::execute(
            'UPDATE conversation_participants SET last_read_message_id = ?
             WHERE conversation_id = ? AND user_id = ? AND (last_read_message_id IS NULL OR last_read_message_id < ?)',
            [$messageId, $conversationId, $userId, $messageId]
        );
    }

    public static function setMuted(int $conversationId, int $userId, bool $muted): void
    {
        self::execute(
            'UPDATE conversation_participants SET is_muted = ? WHERE conversation_id = ? AND user_id = ?',
            [$muted ? 1 : 0, $conversationId, $userId]
        );
    }

    /** Apodo de la otra persona para este participante (null = quitarlo). */
    public static function setPreference(int $conversationId, int $userId, string $column, ?string $value): void
    {
        if ($column !== 'nickname') {
            throw new \InvalidArgumentException('Preferencia desconocida.');
        }
        self::execute(
            "UPDATE conversation_participants SET $column = ? WHERE conversation_id = ? AND user_id = ?",
            [$value, $conversationId, $userId]
        );
    }

    /**
     * Aviso dentro del chat (body = código, ver systemText): «activó los mensajes temporales», «añadió a…», etc.
     * Lo deja como último mensaje y leído para quien lo hizo. Debe llamarse dentro de una transacción.
     */
    public static function notice(int $conversationId, int $actorId, string $code): int
    {
        $messageId = Message::create($conversationId, $actorId, $code, null, null, null, null, ['kind' => 'system']);
        self::execute('UPDATE conversations SET last_message_id = ?, last_message_at = NOW() WHERE id = ?', [$messageId, $conversationId]);
        self::markRead($conversationId, $actorId, $messageId);
        return $messageId;
    }

    /**
     * Activa (segundos) o desactiva (0) los mensajes temporales y deja el aviso en el chat. Devuelve false si no
     * cambiaba nada.
     */
    public static function setDisappear(int $conversationId, int $actorId, int $seconds): bool
    {
        return Database::transaction(static function () use ($conversationId, $actorId, $seconds): bool {
            $changed = self::execute(
                'UPDATE conversations SET disappear_seconds = ? WHERE id = ? AND NOT (COALESCE(disappear_seconds, 0) <=> ?)',
                [$seconds > 0 ? $seconds : null, $conversationId, $seconds]
            );
            if ($changed !== 1) {
                return false;
            }
            self::notice($conversationId, $actorId, 'disappear:' . $seconds);
            return true;
        });
    }

    /** Estilo del chat (lo ven todos los participantes). Devuelve false si no cambiaba nada. */
    public static function setTheme(int $conversationId, int $actorId, string $theme): bool
    {
        return Database::transaction(static function () use ($conversationId, $actorId, $theme): bool {
            $value = $theme !== 'trevix' ? $theme : null;
            $changed = self::execute('UPDATE conversations SET theme = ? WHERE id = ? AND NOT (theme <=> ?)', [$value, $conversationId, $value]);
            if ($changed !== 1) {
                return false;
            }
            self::notice($conversationId, $actorId, 'theme');
            return true;
        });
    }

    /** Fondo del chat (lo ven todos los participantes). Devuelve false si no cambiaba nada. */
    public static function setWallpaper(int $conversationId, int $actorId, string $wallpaper): bool
    {
        return Database::transaction(static function () use ($conversationId, $actorId, $wallpaper): bool {
            $value = $wallpaper !== 'default' ? $wallpaper : null;
            $changed = self::execute('UPDATE conversations SET wallpaper = ? WHERE id = ? AND NOT (wallpaper <=> ?)', [$value, $conversationId, $value]);
            if ($changed !== 1) {
                return false;
            }
            self::notice($conversationId, $actorId, 'wallpaper');
            return true;
        });
    }

    /** Chats fijados de una persona. */
    public static function pinnedCount(int $userId): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM conversation_participants WHERE user_id = ? AND left_at IS NULL AND pinned_at IS NOT NULL',
            [$userId]
        );
    }

    /** Fija o desfija los chats indicados (ya validados) para esta persona. */
    public static function setPinned(array $conversationIds, int $userId, bool $pinned): void
    {
        foreach ($conversationIds as $id) {
            self::execute(
                $pinned
                    ? 'UPDATE conversation_participants SET pinned_at = NOW(), hidden_at = NULL WHERE conversation_id = ? AND user_id = ? AND pinned_at IS NULL'
                    : 'UPDATE conversation_participants SET pinned_at = NULL WHERE conversation_id = ? AND user_id = ?',
                [(int) $id, $userId]
            );
        }
    }

    public static function setFavorite(array $conversationIds, int $userId, bool $favorite): void
    {
        foreach ($conversationIds as $id) {
            self::execute(
                'UPDATE conversation_participants SET is_favorite = ? WHERE conversation_id = ? AND user_id = ?',
                [$favorite ? 1 : 0, (int) $id, $userId]
            );
        }
    }

    /**
     * Vaciar chat: esta persona deja de ver los mensajes que existen ahora (los demás los siguen viendo) y quedan
     * leídos. $hide (eliminar chat): además sale de la bandeja, sin fijar ni favorito, hasta que llegue uno nuevo.
     */
    public static function clearFor(int $conversationId, int $userId, bool $hide): void
    {
        $last = (int) self::fetchValue('SELECT COALESCE(MAX(id), 0) FROM messages WHERE conversation_id = ?', [$conversationId]);
        self::execute(
            'UPDATE conversation_participants
             SET cleared_until_id = IF(? > 0, ?, cleared_until_id),
                 last_read_message_id = IF(? > COALESCE(last_read_message_id, 0), ?, last_read_message_id),
                 hidden_at = IF(?, NOW(), NULL), pinned_at = IF(?, NULL, pinned_at), is_favorite = IF(?, 0, is_favorite)
             WHERE conversation_id = ? AND user_id = ?',
            [$last, $last, $last, $last, $hide ? 1 : 0, $hide ? 1 : 0, $hide ? 1 : 0, $conversationId, $userId]
        );
        if ($hide && $last === 0) {
            self::execute('UPDATE conversation_participants SET cleared_until_id = 0 WHERE conversation_id = ? AND user_id = ?', [$conversationId, $userId]);
        }
    }

    /** Señal de «escribiendo…» (como mucho una escritura cada 2 segundos) o null para quitarla. */
    public static function setTyping(int $conversationId, int $userId, bool $typing): void
    {
        self::execute(
            $typing
                ? 'UPDATE conversation_participants SET typing_at = NOW()
                   WHERE conversation_id = ? AND user_id = ? AND (typing_at IS NULL OR typing_at < NOW() - INTERVAL 2 SECOND)'
                : 'UPDATE conversation_participants SET typing_at = NULL WHERE conversation_id = ? AND user_id = ? AND typing_at IS NOT NULL',
            [$conversationId, $userId]
        );
    }

    /** Quienes están escribiendo ahora en el chat, sin contar a quien mira. */
    public static function typingNames(int $conversationId, int $userId): array
    {
        return array_map('strval', array_column(self::fetchAll(
            "SELECT u.display_name FROM conversation_participants cp
             JOIN users u ON u.id = cp.user_id AND u.status = 'active'
             WHERE cp.conversation_id = ? AND cp.user_id <> ? AND cp.left_at IS NULL AND cp.typing_at > NOW() - INTERVAL 6 SECOND
             ORDER BY cp.typing_at DESC LIMIT 3",
            [$conversationId, $userId]
        ), 'display_name'));
    }

    /** Segundos de los mensajes temporales de la conversación (0 = desactivados). */
    public static function disappearSeconds(int $conversationId): int
    {
        return (int) self::fetchValue('SELECT COALESCE(disappear_seconds, 0) FROM conversations WHERE id = ?', [$conversationId]);
    }

    /**
     * Último mensaje leído por la otra persona (en los grupos, por cualquiera), para mostrar "Visto". La confirmación
     * de lectura es recíproca: 0 si quien mira la desactivó, y no cuentan quienes la desactivaron.
     */
    public static function partnerLastRead(int $conversationId, int $userId): int
    {
        if (!User::readReceipts($userId)) {
            return 0;
        }
        return (int) self::fetchValue(
            'SELECT COALESCE(MAX(cp.last_read_message_id), 0) FROM conversation_participants cp
             JOIN users u ON u.id = cp.user_id AND u.read_receipts = 1
             WHERE cp.conversation_id = ? AND cp.user_id <> ? AND cp.left_at IS NULL',
            [$conversationId, $userId]
        );
    }

    /** Hasta dónde leyó cada participante de un grupo (las fotos pequeñas de «Visto por»), con la misma regla. */
    public static function readStates(int $conversationId, int $userId): array
    {
        if (!User::readReceipts($userId)) {
            return [];
        }
        return array_map(static fn (array $r): array => [
            'user_id'      => (int) $r['id'],
            'display_name' => (string) $r['display_name'],
            'avatar_path'  => $r['avatar_path'],
            'last_read_id' => (int) $r['last_read_message_id'],
        ], self::fetchAll(
            "SELECT u.id, u.display_name, u.avatar_path, cp.last_read_message_id FROM conversation_participants cp
             JOIN users u ON u.id = cp.user_id AND u.status = 'active' AND u.read_receipts = 1
             WHERE cp.conversation_id = ? AND cp.user_id <> ? AND cp.left_at IS NULL AND cp.last_read_message_id IS NOT NULL
             ORDER BY cp.last_read_message_id DESC LIMIT 50",
            [$conversationId, $userId]
        ));
    }

    /**
     * Marca como entregados a $userId los mensajes que ya existen en sus chats (o solo en $conversationId): se llama
     * cuando su app o la web consultan la bandeja, los avisos o una conversación. Nunca retrocede.
     */
    public static function markDelivered(int $userId, ?int $conversationId = null): void
    {
        self::execute(
            'UPDATE conversation_participants cp
             JOIN conversations c ON c.id = cp.conversation_id
             SET cp.last_delivered_message_id = c.last_message_id
             WHERE cp.user_id = ? AND cp.left_at IS NULL AND c.last_message_id IS NOT NULL
               AND (cp.last_delivered_message_id IS NULL OR cp.last_delivered_message_id < c.last_message_id)'
               . ($conversationId !== null ? ' AND cp.conversation_id = ?' : ''),
            $conversationId !== null ? [$userId, $conversationId] : [$userId]
        );
    }

    /**
     * Info de un mensaje propio: a quién se le entregó, quién lo leyó y, si es de visualización única, quién lo abrió.
     * Cuenta solo a quienes estaban en el chat cuando se envió. La lectura y la apertura respetan la confirmación de
     * lectura (si quien pregunta la desactivó, o la persona la desactivó, solo se sabe si se le entregó).
     *
     * @return array{receipts:bool, people: list<array{user:array, status:string, opened:?bool, read_hidden:bool}>}
     */
    public static function deliveryInfo(array $message, int $viewerId): array
    {
        $receipts = User::readReceipts($viewerId);
        $rows = self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, u.read_receipts,
                    cp.last_read_message_id, cp.last_delivered_message_id,
                    (SELECT 1 FROM message_views v WHERE v.message_id = ? AND v.user_id = cp.user_id) AS opened
             FROM conversation_participants cp
             JOIN users u ON u.id = cp.user_id AND u.status = 'active'
             WHERE cp.conversation_id = ? AND cp.user_id <> ? AND cp.left_at IS NULL AND cp.joined_at <= ?
             ORDER BY u.display_name ASC LIMIT 300",
            [(int) $message['id'], (int) $message['conversation_id'], $viewerId, $message['created_at']]
        );
        $id = (int) $message['id'];
        $viewOnce = !empty($message['view_once']);
        $people = [];
        foreach ($rows as $r) {
            $visible = $receipts && (int) $r['read_receipts'] === 1;
            $read = (int) ($r['last_read_message_id'] ?? 0) >= $id;
            $delivered = $read || (int) ($r['last_delivered_message_id'] ?? 0) >= $id || $r['opened'] !== null;
            $people[] = [
                'user'        => $r,
                'status'      => $read && $visible ? 'read' : ($delivered ? 'delivered' : 'sent'),
                'opened'      => $viewOnce && $visible ? $r['opened'] !== null : null,
                'read_hidden' => !$visible,
            ];
        }
        return ['receipts' => $receipts, 'people' => $people];
    }

    /**
     * Envía un mensaje, creando la conversación directa si es el primero. Devuelve [conversación, mensaje].
     * En los grupos (y en directas ya creadas) $recipientId no se usa.
     *
     * Con los mensajes temporales activados, el mensaje caduca a los segundos configurados.
     *
     * @param array|null $gif campos gif_* de Giphy::resolve
     * @param array $extra reply_to_id, forwarded, location, e2ee_epoch, view_once, view_seconds (ver Message::create)
     */
    public static function send(int $senderId, ?int $recipientId, ?int $conversationId, ?string $body, ?array $media, ?int $storyId = null, ?int $songId = null, ?array $gif = null, array $extra = []): array
    {
        return Database::transaction(static function () use ($senderId, $recipientId, $conversationId, $body, $media, $storyId, $songId, $gif, $extra): array {
            $conversationId ??= self::openDirect($senderId, (int) $recipientId);
            $extra['expires_seconds'] = self::disappearSeconds($conversationId);
            $messageId = Message::create($conversationId, $senderId, $body, $media, $storyId, $songId, $gif, $extra);
            self::execute(
                'UPDATE conversations SET last_message_id = ?, last_message_at = NOW() WHERE id = ?',
                [$messageId, $conversationId]
            );
            self::markRead($conversationId, $senderId, $messageId);
            self::setTyping($conversationId, $senderId, false);
            return [$conversationId, $messageId];
        });
    }

    /**
     * Tras eliminar una cuenta: borra las conversaciones en las que ya no queda nadie y da un nuevo dueño a los
     * grupos que se quedaron sin él.
     */
    public static function deleteOrphans(): void
    {
        self::execute('DELETE FROM conversations WHERE NOT EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = conversations.id AND cp.left_at IS NULL)');
        foreach (self::fetchAll(
            "SELECT c.id FROM conversations c WHERE c.type = 'group'
               AND NOT EXISTS (SELECT 1 FROM conversation_participants o WHERE o.conversation_id = c.id AND o.role = 'owner' AND o.left_at IS NULL)"
        ) as $row) {
            Group::promoteSuccessor((int) $row['id']);
        }
    }

    private static function viewerShowsActivity(int $userId): bool
    {
        return (bool) self::fetchValue('SELECT show_activity FROM users WHERE id = ?', [$userId]);
    }

    /**
     * Quien oculta su actividad tampoco ve la de los demás. Las cuentas eliminadas o no disponibles
     * se muestran sin enlace al perfil. Un grupo se presenta con «user» = el grupo (nombre y foto), para que
     * las vistas de la bandeja funcionen igual, y con «group» = sus datos.
     */
    private static function present(array $r, int $viewerId, bool $viewerShows): array
    {
        $isGroup = ($r['type'] ?? 'direct') === 'group';
        $available = $isGroup || ($r['partner_id'] !== null && $r['partner_status'] === 'active');
        if ($isGroup) {
            $partner = [
                'id'           => 0,
                'username'     => '',
                'display_name' => (string) $r['title'],
                'avatar_path'  => $r['group_avatar'],
                'is_verified'  => 0,
                'status'       => 'active',
            ];
        } elseif ($available) {
            $partner = [
                'id'           => (int) $r['partner_id'],
                'username'     => $r['username'],
                'display_name' => $r['display_name'],
                'avatar_path'  => $r['avatar_path'],
                'is_verified'  => (int) $r['is_verified'],
                'status'       => $r['partner_status'],
                'message_privacy' => $r['message_privacy'] ?? 'everyone',
            ];
        } else {
            $partner = [
                'id'           => $r['partner_id'] !== null ? (int) $r['partner_id'] : 0,
                'username'     => '',
                'display_name' => 'Cuenta no disponible',
                'avatar_path'  => null,
                'is_verified'  => 0,
                'status'       => 'unavailable',
            ];
        }

        $blocked = !$isGroup && (int) $r['blocked'] > 0;
        $preview = null;
        if ($r['last_id'] !== null) {
            $mine = $r['last_sender'] !== null && (int) $r['last_sender'] === $viewerId;
            if (($r['last_kind'] ?? 'message') === 'system') {
                $actor = $isGroup ? (string) ($r['last_sender_name'] ?? '') : (string) ($r['nickname'] ?: $partner['display_name']);
                $preview = self::systemText((string) $r['last_body'], $mine, $actor, null, false, $isGroup);
            } else {
                $text = Message::summary([
                    'deleted_at' => $r['last_deleted'], 'body' => $r['last_body'], 'location_lat' => $r['last_location'] ?? null,
                    'media_path' => $r['last_media'], 'media_mime' => $r['last_mime'], 'gif_kind' => $r['last_gif'],
                    'song_id' => $r['last_song'] ?? null, 'context' => $r['last_context'] ?? null,
                    'e2ee_epoch' => $r['last_e2ee'] ?? null, 'view_once' => $r['last_view_once'] ?? 0,
                    'media_cleared_at' => $r['last_cleared'] ?? null,
                ]);
                $who = $mine ? 'Tú: ' : ($isGroup && ($r['last_sender_name'] ?? '') !== '' ? self::firstName((string) $r['last_sender_name']) . ': ' : '');
                $preview = $who . mb_strimwidth($text, 0, 80, '…');
            }
        } elseif ($isGroup) {
            $preview = 'Grupo creado';
        }
        $match = $r['search_match'] ?? null;
        $out = [
            'id'                => (int) $r['id'],
            'type'              => $isGroup ? 'group' : 'direct',
            'user'              => $partner,
            'available'         => $available,
            'blocked'           => $blocked,
            'online'            => !$isGroup && $available && !$blocked && $viewerShows && User::isOnline($r),
            'unread'            => (int) $r['unread'],
            'muted'             => (bool) $r['is_muted'],
            'pinned'            => ($r['pinned_at'] ?? null) !== null,
            'favorite'          => (bool) ($r['is_favorite'] ?? false),
            'typing'            => !$blocked && (int) ($r['typing'] ?? 0) > 0,
            'preview'           => $preview,
            'search_match'      => $match !== null ? mb_strimwidth((string) preg_replace('/\s+/u', ' ', (string) $match), 0, 100, '…') : null,
            'nickname'          => !$isGroup ? (($r['nickname'] ?? null) ?: null) : null,
            'wallpaper'         => ($r['wallpaper'] ?? null) ?: 'default',
            'theme'             => ($r['theme'] ?? null) ?: 'trevix',
            'e2ee'              => (bool) ($r['e2ee'] ?? false),
            'key_epoch'         => (int) ($r['key_epoch'] ?? 0),
            'disappear_seconds' => (int) ($r['disappear_seconds'] ?? 0),
            'last_message_at'   => $r['last_message_at'],
        ];
        if ($isGroup) {
            $out['group'] = [
                'title'         => (string) $r['title'],
                'description'   => (string) ($r['description'] ?? ''),
                'avatar_path'   => $r['group_avatar'],
                'cover_path'    => $r['group_cover'],
                'visibility'    => $r['visibility'] ?: 'private',
                'role'          => $r['role'] ?? 'member',
                'members_count' => (int) ($r['members_count'] ?? 0),
            ];
        }
        return $out;
    }

    private static function firstName(string $name): string
    {
        $first = trim((string) strtok(trim($name), ' '));
        return $first !== '' ? $first : $name;
    }

    /**
     * Texto de un aviso del chat para quien mira. $mine: lo hizo quien mira; $name: nombre (o apodo) de quien lo
     * hizo; $target: nombre de la persona a la que se refiere (añadir, quitar, nombrar administrador); $targetMe:
     * esa persona es quien mira. Códigos: «disappear:N», «theme», «wallpaper», «e2ee:on», «key:ID» (cambió la clave de cifrado de
     * alguien) y los de los grupos «group:create|join|leave|title|description|avatar|cover|link|visibility:public|
     * visibility:private|add:ID|remove:ID|approve:ID|admin:ID|unadmin:ID».
     */
    public static function systemText(string $code, bool $mine, string $name, ?string $target = null, bool $targetMe = false, bool $group = false): string
    {
        $name = trim($name) !== '' ? $name : ($group ? 'Alguien' : 'La otra persona');
        $target = $targetMe ? 'ti' : (trim((string) $target) !== '' ? (string) $target : 'una persona');
        if (str_starts_with($code, 'disappear:')) {
            $seconds = (int) substr($code, 10);
            $who = $mine ? 'Activaste' : $name . ' activó';
            if ($seconds <= 0) {
                return ($mine ? 'Desactivaste' : $name . ' desactivó') . ' los mensajes temporales.';
            }
            $label = mb_strtolower((string) (((array) Config::get('app.chat.disappear_options', []))[$seconds] ?? round($seconds / 3600) . ' horas'));
            return $who . ' los mensajes temporales: los nuevos mensajes desaparecerán ' . (str_contains($label, 'hora') ? 'a las ' : 'a los ') . $label . '.';
        }
        if ($code === 'theme') {
            return ($mine ? 'Cambiaste' : $name . ' cambió') . ' el estilo del chat.';
        }
        if ($code === 'wallpaper') {
            return ($mine ? 'Cambiaste' : $name . ' cambió') . ' el fondo del chat.';
        }
        if ($code === 'e2ee:on') {
            return 'Los mensajes de este chat están cifrados de extremo a extremo: nadie fuera del chat, ni siquiera TREVIX, puede leerlos.';
        }
        if (str_starts_with($code, 'key:')) {
            return $targetMe ? 'Tu código de seguridad cambió.' : 'Cambió el código de seguridad de ' . $target . '.';
        }
        $did = static fn (string $yo, string $el): string => $mine ? $yo : $name . ' ' . $el;
        [$kind, $arg] = array_pad(explode(':', substr($code, 6), 2), 2, '');
        if (!str_starts_with($code, 'group:')) {
            return 'Aviso de la conversación.';
        }
        return match ($kind) {
            'create'      => $did('Creaste el grupo.', 'creó el grupo.'),
            'join'        => $mine ? 'Te uniste al grupo con el enlace.' : $name . ' se unió con el enlace.',
            'leave'       => $mine ? 'Saliste del grupo.' : $name . ' salió del grupo.',
            'title'       => $did('Cambiaste el nombre del grupo.', 'cambió el nombre del grupo.'),
            'description' => $did('Cambiaste la descripción del grupo.', 'cambió la descripción del grupo.'),
            'avatar'      => $did('Cambiaste la foto del grupo.', 'cambió la foto del grupo.'),
            'cover'       => $did('Cambiaste la portada del grupo.', 'cambió la portada del grupo.'),
            'link'        => $did('Restableciste el enlace de invitación.', 'restableció el enlace de invitación.'),
            'visibility'  => $did('Hiciste el grupo ', 'hizo el grupo ') . ($arg === 'public' ? 'público: cualquiera con el enlace puede unirse.' : 'privado: para unirse con el enlace hay que pedirlo.'),
            'add'         => $targetMe ? $name . ' te añadió al grupo.' : $did('Añadiste a ' . $target . '.', 'añadió a ' . $target . '.'),
            'remove'      => $targetMe ? $name . ' te quitó del grupo.' : $did('Quitaste a ' . $target . ' del grupo.', 'quitó a ' . $target . ' del grupo.'),
            'approve'     => $targetMe ? $name . ' aceptó tu solicitud para unirte.' : $did('Aceptaste a ' . $target . '.', 'aceptó a ' . $target . '.'),
            'admin'       => $targetMe ? $name . ' te nombró administrador del grupo.' : $did('Nombraste administrador a ' . $target . '.', 'nombró administrador a ' . $target . '.'),
            'unadmin'     => $targetMe ? 'Ya no eres administrador del grupo.' : $did('Quitaste a ' . $target . ' como administrador.', 'quitó a ' . $target . ' como administrador.'),
            default       => 'Aviso del grupo.',
        };
    }
}
