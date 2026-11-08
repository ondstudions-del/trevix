<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Conversaciones directas entre dos personas. direct_key ("menorId:mayorId") garantiza una sola
 * conversación por pareja. Se crea al enviar el primer mensaje, no al abrir el chat.
 * Lo no leído se calcula con el último mensaje leído de cada participante.
 */
final class Conversation extends Model
{
    /** Mensajes de la otra persona posteriores al último leído (alias cp = participante que mira). */
    private const UNREAD_SQL = "SELECT COUNT(*) FROM messages um WHERE um.conversation_id = cp.conversation_id
        AND um.id > COALESCE(cp.last_read_message_id, 0) AND (um.sender_id IS NULL OR um.sender_id <> cp.user_id)
        AND um.deleted_at IS NULL AND um.kind = 'message' AND (um.expires_at IS NULL OR um.expires_at > NOW())";

    /** Último mensaje que ve el participante cp (sin caducados ni ocultos para él). */
    private const LAST_VISIBLE_SQL = 'SELECT MAX(lm.id) FROM messages lm WHERE lm.conversation_id = c.id
        AND (lm.expires_at IS NULL OR lm.expires_at > NOW())
        AND NOT EXISTS (SELECT 1 FROM message_hidden lh WHERE lh.message_id = lm.id AND lh.user_id = cp.user_id)';

    /** Hay un bloqueo entre quien mira (cp) y la otra persona (u). */
    private const BLOCKED_SQL = 'SELECT COUNT(*) FROM blocks b WHERE (b.blocker_id = cp.user_id AND b.blocked_id = u.id)
        OR (b.blocker_id = u.id AND b.blocked_id = cp.user_id)';

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
     * Bandeja de entrada: conversaciones con mensajes, de la más reciente a la más antigua,
     * con la otra persona, el último mensaje y cuántos sin leer.
     */
    public static function inbox(int $userId, int $limit = 100, string $term = ''): array
    {
        $params = [$userId];
        $where = '';
        $match = 'NULL';
        if ($term !== '') {
            $like = '%' . self::likeEscape(mb_strtolower($term)) . '%';
            $bodyMatch = "FROM messages sm WHERE sm.conversation_id = c.id AND sm.kind = 'message' AND sm.deleted_at IS NULL
                AND (sm.expires_at IS NULL OR sm.expires_at > NOW()) AND sm.body LIKE ?
                AND NOT EXISTS (SELECT 1 FROM message_hidden sh WHERE sh.message_id = sm.id AND sh.user_id = cp.user_id)";
            $match = "(SELECT sm.body $bodyMatch ORDER BY sm.id DESC LIMIT 1)";
            $where = " AND (u.username LIKE ? OR u.display_name LIKE ? OR cp.nickname LIKE ? OR EXISTS (SELECT 1 $bodyMatch))";
            array_unshift($params, $like);
            array_push($params, $like, $like, $like, $like);
        }
        $rows = self::fetchAll(
            'SELECT c.id, c.last_message_at, c.disappear_seconds, cp.is_muted, cp.nickname, cp.wallpaper,
                    (' . self::UNREAD_SQL . ') AS unread, (' . self::BLOCKED_SQL . ') AS blocked, ' . $match . ' AS search_match,
                    u.id AS partner_id, u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS partner_status,
                    u.show_activity, u.last_seen_at,
                    m.id AS last_id, m.sender_id AS last_sender, m.kind AS last_kind, m.body AS last_body, m.media_path AS last_media,
                    m.media_mime AS last_mime, m.gif_kind AS last_gif, m.location_lat AS last_location, m.deleted_at AS last_deleted,
                    m.song_id AS last_song
             FROM conversation_participants cp
             JOIN conversations c ON c.id = cp.conversation_id AND c.type = \'direct\'
             LEFT JOIN conversation_participants op ON op.conversation_id = c.id AND op.user_id <> cp.user_id
             LEFT JOIN users u ON u.id = op.user_id
             LEFT JOIN messages m ON m.id = (' . self::LAST_VISIBLE_SQL . ')
             WHERE cp.user_id = ? AND cp.left_at IS NULL AND m.id IS NOT NULL' . $where . '
             ORDER BY c.last_message_at DESC, c.id DESC
             LIMIT ' . max(1, min(200, $limit)),
            $params
        );
        $viewerShows = self::viewerShowsActivity($userId);
        return array_map(static fn (array $r): array => self::present($r, $userId, $viewerShows), $rows);
    }

    /** Conversación en la que participa el usuario, con los datos de la otra persona. */
    public static function findFor(int $conversationId, int $userId): ?array
    {
        $row = self::fetchOne(
            'SELECT c.id, c.last_message_at, c.disappear_seconds, cp.is_muted, cp.nickname, cp.wallpaper, cp.last_read_message_id,
                    op.last_read_message_id AS partner_last_read,
                    u.id AS partner_id, u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS partner_status,
                    u.show_activity, u.last_seen_at, u.message_privacy, 0 AS unread, (' . self::BLOCKED_SQL . ') AS blocked,
                    NULL AS last_id, NULL AS search_match
             FROM conversation_participants cp
             JOIN conversations c ON c.id = cp.conversation_id AND c.type = \'direct\'
             LEFT JOIN conversation_participants op ON op.conversation_id = c.id AND op.user_id <> cp.user_id
             LEFT JOIN users u ON u.id = op.user_id
             WHERE cp.conversation_id = ? AND cp.user_id = ? AND cp.left_at IS NULL
             LIMIT 1',
            [$conversationId, $userId]
        );
        if ($row === null) {
            return null;
        }
        $conversation = self::present($row, $userId, self::viewerShowsActivity($userId));
        $conversation['partner_last_read'] = (int) ($row['partner_last_read'] ?? 0);
        $conversation['last_read'] = (int) ($row['last_read_message_id'] ?? 0);
        return $conversation;
    }

    /**
     * Motivo por el que $senderId no puede escribir a $recipient, o null si puede.
     * La privacidad de mensajes decide quién puede iniciar una conversación: si la otra persona
     * ya escribió en ella, se le puede responder.
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
        if ($privacy === 'everyone') {
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

    /** Apodo de la otra persona o fondo del chat de este participante (null = quitarlo). */
    public static function setPreference(int $conversationId, int $userId, string $column, ?string $value): void
    {
        if (!in_array($column, ['nickname', 'wallpaper'], true)) {
            throw new \InvalidArgumentException('Preferencia desconocida.');
        }
        self::execute(
            "UPDATE conversation_participants SET $column = ? WHERE conversation_id = ? AND user_id = ?",
            [$value, $conversationId, $userId]
        );
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
            $messageId = Message::create($conversationId, $actorId, 'disappear:' . $seconds, null, null, null, null, ['kind' => 'system']);
            self::execute('UPDATE conversations SET last_message_id = ?, last_message_at = NOW() WHERE id = ?', [$messageId, $conversationId]);
            self::markRead($conversationId, $actorId, $messageId);
            return true;
        });
    }

    /** Segundos de los mensajes temporales de la conversación (0 = desactivados). */
    public static function disappearSeconds(int $conversationId): int
    {
        return (int) self::fetchValue('SELECT COALESCE(disappear_seconds, 0) FROM conversations WHERE id = ?', [$conversationId]);
    }

    /** Último mensaje leído por la otra persona, para mostrar "Visto". */
    public static function partnerLastRead(int $conversationId, int $userId): int
    {
        return (int) self::fetchValue(
            'SELECT COALESCE(MAX(last_read_message_id), 0) FROM conversation_participants WHERE conversation_id = ? AND user_id <> ?',
            [$conversationId, $userId]
        );
    }

    /**
     * Envía un mensaje, creando la conversación si es el primero. Devuelve [conversación, mensaje].
     *
     * Con los mensajes temporales activados, el mensaje caduca a los segundos configurados.
     *
     * @param array|null $gif campos gif_* de Giphy::resolve
     * @param array $extra reply_to_id, forwarded, location (ver Message::create)
     */
    public static function send(int $senderId, int $recipientId, ?int $conversationId, ?string $body, ?array $media, ?int $storyId = null, ?int $songId = null, ?array $gif = null, array $extra = []): array
    {
        return Database::transaction(static function () use ($senderId, $recipientId, $conversationId, $body, $media, $storyId, $songId, $gif, $extra): array {
            $conversationId ??= self::openDirect($senderId, $recipientId);
            $extra['expires_seconds'] = self::disappearSeconds($conversationId);
            $messageId = Message::create($conversationId, $senderId, $body, $media, $storyId, $songId, $gif, $extra);
            self::execute(
                'UPDATE conversations SET last_message_id = ?, last_message_at = NOW() WHERE id = ?',
                [$messageId, $conversationId]
            );
            self::markRead($conversationId, $senderId, $messageId);
            return [$conversationId, $messageId];
        });
    }

    /** Tras eliminar una cuenta: borra las conversaciones en las que ya no queda nadie. */
    public static function deleteOrphans(): void
    {
        self::execute('DELETE FROM conversations WHERE NOT EXISTS (SELECT 1 FROM conversation_participants cp WHERE cp.conversation_id = conversations.id)');
    }

    private static function viewerShowsActivity(int $userId): bool
    {
        return (bool) self::fetchValue('SELECT show_activity FROM users WHERE id = ?', [$userId]);
    }

    /**
     * Quien oculta su actividad tampoco ve la de los demás. Las cuentas eliminadas o no disponibles
     * se muestran sin enlace al perfil.
     */
    private static function present(array $r, int $viewerId, bool $viewerShows): array
    {
        $available = $r['partner_id'] !== null && $r['partner_status'] === 'active';
        $partner = $available
            ? [
                'id'           => (int) $r['partner_id'],
                'username'     => $r['username'],
                'display_name' => $r['display_name'],
                'avatar_path'  => $r['avatar_path'],
                'is_verified'  => (int) $r['is_verified'],
                'status'       => $r['partner_status'],
                'message_privacy' => $r['message_privacy'] ?? 'everyone',
            ]
            : [
                'id'           => $r['partner_id'] !== null ? (int) $r['partner_id'] : 0,
                'username'     => '',
                'display_name' => 'Cuenta no disponible',
                'avatar_path'  => null,
                'is_verified'  => 0,
                'status'       => 'unavailable',
            ];

        $preview = null;
        if ($r['last_id'] !== null) {
            $mine = $r['last_sender'] !== null && (int) $r['last_sender'] === $viewerId;
            if (($r['last_kind'] ?? 'message') === 'system') {
                $preview = self::systemText((string) $r['last_body'], $mine, (string) ($r['nickname'] ?: $partner['display_name']));
            } else {
                $text = Message::summary([
                    'deleted_at' => $r['last_deleted'], 'body' => $r['last_body'], 'location_lat' => $r['last_location'] ?? null,
                    'media_path' => $r['last_media'], 'media_mime' => $r['last_mime'], 'gif_kind' => $r['last_gif'],
                    'song_id' => $r['last_song'] ?? null,
                ]);
                $preview = ($mine ? 'Tú: ' : '') . mb_strimwidth($text, 0, 80, '…');
            }
        }
        $match = $r['search_match'] ?? null;

        $blocked = (int) $r['blocked'] > 0;
        return [
            'id'                => (int) $r['id'],
            'user'              => $partner,
            'available'         => $available,
            'blocked'           => $blocked,
            'online'            => $available && !$blocked && $viewerShows && User::isOnline($r),
            'unread'            => (int) $r['unread'],
            'muted'             => (bool) $r['is_muted'],
            'preview'           => $preview,
            'search_match'      => $match !== null ? mb_strimwidth((string) preg_replace('/\s+/u', ' ', (string) $match), 0, 100, '…') : null,
            'nickname'          => ($r['nickname'] ?? null) ?: null,
            'wallpaper'         => ($r['wallpaper'] ?? null) ?: 'default',
            'disappear_seconds' => (int) ($r['disappear_seconds'] ?? 0),
            'last_message_at'   => $r['last_message_at'],
        ];
    }

    /**
     * Texto de un aviso del chat para quien mira. $code: «disappear:N» (mensajes temporales). $mine: lo hizo quien
     * mira; $name: nombre (o apodo) de la otra persona.
     */
    public static function systemText(string $code, bool $mine, string $name): string
    {
        $name = trim($name) !== '' ? $name : 'La otra persona';
        if (str_starts_with($code, 'disappear:')) {
            $seconds = (int) substr($code, 10);
            $who = $mine ? 'Activaste' : $name . ' activó';
            if ($seconds <= 0) {
                return ($mine ? 'Desactivaste' : $name . ' desactivó') . ' los mensajes temporales.';
            }
            $label = mb_strtolower((string) (((array) \Trevix\Core\Config::get('app.chat.disappear_options', []))[$seconds] ?? round($seconds / 3600) . ' horas'));
            return $who . ' los mensajes temporales: los nuevos mensajes desaparecerán ' . (str_contains($label, 'hora') ? 'a las ' : 'a los ') . $label . '.';
        }
        return 'Aviso de la conversación.';
    }
}
