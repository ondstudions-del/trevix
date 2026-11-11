<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Services\Giphy;
use Trevix\Services\MediaUpload;

/**
 * Mensajes de una conversación: texto con una imagen, una nota de voz (media_mime audio/*), un GIF o sticker o una
 * ubicación. Pueden responder a otro mensaje (reply_to_id), venir reenviados, tener reacciones y estar fijados.
 * Los mensajes antiguos pueden llevar una canción (ya no se envían canciones por chat, pero se siguen mostrando).
 * Borrar un mensaje lo vacía y deja la marca "Mensaje eliminado"; «eliminar para ti» solo lo oculta a quien lo pide.
 * Con los mensajes temporales activados, cada mensaje caduca (expires_at): se vacía y deja de mostrarse.
 * Cifrados de extremo a extremo (e2ee_epoch): body es el texto cifrado y el archivo está cifrado; el servidor no
 * puede leer ninguno de los dos. Fotos de visualización única (view_once): el archivo se borra cuando lo abren todos.
 * En los grupos, cada participante ve los mensajes desde que entró.
 */
final class Message extends Model
{
    private const COLUMNS = 'm.id, m.conversation_id, m.sender_id, m.kind, m.context, m.reply_to_id, m.forwarded, m.body, m.e2ee_epoch,
        m.media_path, m.media_mime, m.media_duration, m.media_size, m.media_width, m.media_height, m.media_poster,
        m.media_cleared_at, m.view_once, m.view_seconds, m.story_id,
        m.note_text, m.song_id, m.gif_id, m.gif_kind, m.gif_url, m.gif_width, m.gif_height, m.gif_title, m.location_lat,
        m.location_lng, m.location_name, m.pinned_at, m.pinned_by, m.expires_at, m.deleted_at, m.created_at';

    private const CLEAR = 'body = NULL, e2ee_epoch = NULL, note_text = NULL, media_path = NULL, media_mime = NULL, media_duration = NULL,
        media_size = NULL, media_width = NULL, media_height = NULL, media_poster = NULL, song_id = NULL, gif_id = NULL, gif_kind = NULL, gif_url = NULL, gif_width = NULL, gif_height = NULL,
        gif_title = NULL, location_lat = NULL, location_lng = NULL, location_name = NULL, pinned_at = NULL, pinned_by = NULL,
        deleted_at = NOW()';

    /**
     * Visible: no caducado, no oculto para quien mira (el ? es su id), posterior a «vaciar chat» y enviado después de
     * que entrara a la conversación (en los chats de dos los participantes se crean antes del primer mensaje).
     */
    private const VISIBLE = '(m.expires_at IS NULL OR m.expires_at > NOW())
        AND NOT EXISTS (SELECT 1 FROM conversation_participants vp WHERE vp.conversation_id = m.conversation_id AND vp.user_id = ?
            AND (m.created_at < vp.joined_at OR m.id <= COALESCE(vp.cleared_until_id, 0)
                 OR EXISTS (SELECT 1 FROM message_hidden h WHERE h.message_id = m.id AND h.user_id = vp.user_id)))';

    /**
     * @param array{path:string, mime_type:string, duration?:int, duration_seconds?:?int, size_bytes?:int, width?:?int, height?:?int, poster_path?:?string}|null $media
     *        imagen, video (con su miniatura), nota de voz o archivo cifrado
     * @param array|null $gif campos gif_* de Giphy::resolve
     * @param array{kind?:string, context?:string|null, note_text?:string|null, reply_to_id?:int|null, forwarded?:bool, location?:array{lat:float, lng:float, name:?string}|null, expires_seconds?:int|null, e2ee_epoch?:int|null, view_once?:bool, view_seconds?:int|null} $extra
     */
    public static function create(int $conversationId, int $senderId, ?string $body, ?array $media, ?int $storyId = null, ?int $songId = null, ?array $gif = null, array $extra = []): int
    {
        $location = $extra['location'] ?? null;
        $expires = (int) ($extra['expires_seconds'] ?? 0);
        $size = null;
        if ($media !== null) {
            $size = (int) ($media['size_bytes'] ?? (@filesize(BASE_PATH . '/' . $media['path']) ?: 0));
        }
        $viewOnce = !empty($extra['view_once']) && $media !== null;
        self::execute(
            'INSERT INTO messages (conversation_id, sender_id, kind, context, reply_to_id, forwarded, body, e2ee_epoch, media_path, media_mime,
                                   media_duration, media_size, media_width, media_height, media_poster, view_once, view_seconds, story_id,
                                   note_text, song_id, gif_id, gif_kind, gif_url, gif_width, gif_height, gif_title, location_lat,
                                   location_lng, location_name, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, IF(? > 0, NOW() + INTERVAL ? SECOND, NULL))',
            [
                $conversationId, $senderId, $extra['kind'] ?? 'message', $extra['context'] ?? null, $extra['reply_to_id'] ?? null,
                !empty($extra['forwarded']) ? 1 : 0,
                $body, $extra['e2ee_epoch'] ?? null, $media['path'] ?? null, $media['mime_type'] ?? null,
                $media['duration'] ?? $media['duration_seconds'] ?? null, $size,
                $media['width'] ?? null, $media['height'] ?? null, $media['poster_path'] ?? null,
                $viewOnce ? 1 : 0, $viewOnce && !empty($extra['view_seconds']) ? (int) $extra['view_seconds'] : null,
                $storyId, $extra['note_text'] ?? null, $songId, $gif['gif_id'] ?? null, $gif['gif_kind'] ?? null, $gif['gif_url'] ?? null,
                $gif['gif_width'] ?? null, $gif['gif_height'] ?? null, $gif['gif_title'] ?? null,
                $location['lat'] ?? null, $location['lng'] ?? null, $location['name'] ?? null, $expires, $expires,
            ]
        );
        $messageId = (int) self::db()->lastInsertId();
        if ($songId !== null) {
            Song::incrementUses($songId);
        }
        return $messageId;
    }

    /**
     * Añade a cada mensaje la historia a la que responde (clave "story"), la canción (clave "song"), el GIF
     * (clave "gif"), el mensaje al que responde (clave "reply") y las reacciones (clave "reactions", con la de
     * quien mira). Un mensaje sin texto, imagen, GIF, ubicación ni canción que no se eliminó es uno cuya canción
     * se borró: se muestra como «Canción no disponible».
     * También añade quién lo envió (clave "sender", para los grupos), el nombre de la persona a la que se refiere un
     * aviso del grupo ("target_name" / "target_me") y, en las fotos de visualización única, si quien mira ya la abrió
     * ("viewed") y cuántas personas la abrieron ("views").
     */
    public static function withAttachments(array $messages, int $viewerId = 0): array
    {
        if ($messages === []) {
            return [];
        }
        $stories = Story::previewsFor(array_column($messages, 'story_id'));
        $songs = Song::cardsFor(array_column($messages, 'song_id'));
        $replies = self::replyPreviews(array_column($messages, 'reply_to_id'), $viewerId);
        $ids = array_map('intval', array_column($messages, 'id'));
        $reactions = self::reactionsFor($ids, $viewerId);
        $targets = [];
        foreach ($messages as $message) {
            if (($message['kind'] ?? 'message') === 'system' && preg_match('/:(\d+)$/', (string) $message['body'], $mt)) {
                $targets[] = (int) $mt[1];
            }
        }
        $people = self::people(array_merge(array_column($messages, 'sender_id'), $targets));
        $views = self::viewsFor(array_values(array_map(
            static fn (array $m) => (int) $m['id'],
            array_filter($messages, static fn (array $m) => !empty($m['view_once']))
        )), $viewerId);
        foreach ($messages as &$message) {
            $message['story'] = $stories[(int) ($message['story_id'] ?? 0)] ?? null;
            $message['gif'] = Giphy::fromRow($message);
            $songId = (int) ($message['song_id'] ?? 0);
            $orphan = $message['deleted_at'] === null && ($message['kind'] ?? 'message') === 'message'
                && ($message['body'] ?? null) === null && $message['media_path'] === null && ($message['media_cleared_at'] ?? null) === null
                && $message['gif'] === null && $songId === 0 && ($message['location_lat'] ?? null) === null;
            $message['song'] = $songId > 0 ? $songs[$songId] : ($orphan ? Song::unavailable(0) : null);
            $message['reply'] = $replies[(int) ($message['reply_to_id'] ?? 0)] ?? null;
            $message['reactions'] = $reactions[(int) $message['id']] ?? ['list' => [], 'mine' => null];
            $message['sender'] = $people[(int) ($message['sender_id'] ?? 0)] ?? null;
            $message['sender_name'] = $message['sender']['display_name'] ?? '';
            if (($message['kind'] ?? 'message') === 'system' && preg_match('/:(\d+)$/', (string) $message['body'], $mt)) {
                $message['target_me'] = (int) $mt[1] === $viewerId;
                $message['target_name'] = $people[(int) $mt[1]]['display_name'] ?? t('una cuenta no disponible');
            }
            if (!empty($message['view_once'])) {
                $seen = $views[(int) $message['id']] ?? ['count' => 0, 'hidden' => 0, 'mine' => false];
                $receipts = $viewerId > 0 && User::readReceipts($viewerId);
                $message['viewed'] = $seen['mine'];
                $message['views'] = $receipts ? $seen['count'] : 0;
                // Para quien la envió, «Abierta» solo si la abrieron todos y todos comparten la confirmación de lectura.
                if ((int) ($message['sender_id'] ?? 0) === $viewerId) {
                    $message['opened'] = $receipts && $message['media_path'] === null && $seen['count'] > 0 && $seen['hidden'] === 0;
                }
            }
        }
        return $messages;
    }

    /** Cuentas activas por id (para el remitente de cada mensaje y los avisos de los grupos). */
    private static function people(array $ids): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids))));
        if ($ids === []) {
            return [];
        }
        $rows = self::fetchAll(
            "SELECT id, username, display_name, avatar_path, is_verified FROM users
             WHERE status = 'active' AND id IN (" . implode(',', array_fill(0, count($ids), '?')) . ')',
            $ids
        );
        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r['id']] = $r;
        }
        return $out;
    }

    /**
     * Aperturas de cada mensaje de visualización única: las de quienes comparten la confirmación de lectura (count),
     * las de quienes la desactivaron (hidden) y si quien mira ya lo abrió.
     *
     * @return array<int, array{count:int, hidden:int, mine:bool}>
     */
    private static function viewsFor(array $ids, int $viewerId): array
    {
        if ($ids === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT v.message_id, SUM(u.read_receipts = 1) AS shown, SUM(u.read_receipts <> 1) AS hidden, MAX(v.user_id = ?) AS mine
             FROM message_views v JOIN users u ON u.id = v.user_id
             WHERE v.message_id IN (' . implode(',', array_fill(0, count($ids), '?')) . ') GROUP BY v.message_id',
            array_merge([$viewerId], $ids)
        );
        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r['message_id']] = ['count' => (int) $r['shown'], 'hidden' => (int) $r['hidden'], 'mine' => (bool) $r['mine']];
        }
        return $out;
    }

    /**
     * Abre una foto de visualización única: devuelve false si quien mira ya la había abierto. Cuando la abrieron
     * todos los demás participantes (los que estaban cuando se envió), el archivo se borra del servidor.
     */
    public static function markViewed(array $message, int $userId): bool
    {
        $added = self::execute('INSERT IGNORE INTO message_views (message_id, user_id) VALUES (?, ?)', [(int) $message['id'], $userId]) === 1;
        if ($added) {
            self::execute('UPDATE messages SET updated_at = NOW() WHERE id = ?', [(int) $message['id']]);
        }
        return $added;
    }

    /** Tras abrirla: si ya no queda nadie por verla, borra el archivo (el mensaje queda como «Abierta»). */
    public static function purgeIfAllViewed(array $message): void
    {
        $pending = (int) self::fetchValue(
            'SELECT COUNT(*) FROM conversation_participants cp
             WHERE cp.conversation_id = ? AND cp.left_at IS NULL AND cp.user_id <> ? AND cp.joined_at <= ?
               AND NOT EXISTS (SELECT 1 FROM message_views v WHERE v.message_id = ? AND v.user_id = cp.user_id)',
            [(int) $message['conversation_id'], (int) ($message['sender_id'] ?? 0), $message['created_at'], (int) $message['id']]
        );
        if ($pending === 0) {
            self::clearMedia((int) $message['id'], (string) $message['media_path']);
        }
    }

    /** Borra el archivo de un mensaje y deja la marca media_cleared_at (el mensaje sigue en el chat). */
    public static function clearMedia(int $id, ?string $path): void
    {
        $poster = self::fetchValue('SELECT media_poster FROM messages WHERE id = ?', [$id]);
        self::execute('UPDATE messages SET media_path = NULL, media_poster = NULL, media_cleared_at = NOW() WHERE id = ? AND media_path IS NOT NULL', [$id]);
        MediaUpload::delete($path);
        MediaUpload::delete(is_string($poster) ? $poster : null);
    }

    /** Mensaje listo para mostrar. */
    public static function findFull(int $id, int $viewerId = 0): ?array
    {
        $message = self::find($id);
        return $message !== null ? self::withAttachments([$message], $viewerId)[0] : null;
    }

    /**
     * Últimos mensajes visibles para $viewerId (o los anteriores a $beforeId), en orden cronológico.
     *
     * @return array{messages: list<array>, hasMore: bool}
     */
    public static function page(int $conversationId, ?int $beforeId, int $limit, int $viewerId = 0): array
    {
        if ($beforeId === null) {
            self::purgeExpired($conversationId);
        }
        $limit = max(1, min(100, $limit));
        $params = [$conversationId, $viewerId];
        if ($beforeId) {
            $params[] = $beforeId;
        }
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.conversation_id = ? AND ' . self::VISIBLE
            . ($beforeId ? ' AND m.id < ?' : '') . ' ORDER BY m.id DESC LIMIT ' . ($limit + 1),
            $params
        );
        return [
            'messages' => self::withAttachments(array_reverse(array_slice($rows, 0, $limit)), $viewerId),
            'hasMore'  => count($rows) > $limit,
        ];
    }

    /**
     * Mensajes alrededor de $messageId (para saltar a un resultado de la búsqueda): $half antes, él y $half después.
     *
     * @return array{messages: list<array>, hasMore: bool}
     */
    public static function around(int $conversationId, int $messageId, int $half, int $viewerId): array
    {
        $half = max(1, min(50, $half));
        $before = self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.conversation_id = ? AND ' . self::VISIBLE
            . ' AND m.id < ? ORDER BY m.id DESC LIMIT ' . ($half + 1),
            [$conversationId, $viewerId, $messageId]
        );
        $after = self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.conversation_id = ? AND ' . self::VISIBLE
            . ' AND m.id >= ? ORDER BY m.id ASC LIMIT ' . ($half + 1),
            [$conversationId, $viewerId, $messageId]
        );
        return [
            'messages' => self::withAttachments(array_merge(array_reverse(array_slice($before, 0, $half)), $after), $viewerId),
            'hasMore'  => count($before) > $half,
        ];
    }

    /** Mensajes nuevos posteriores a $afterId (sondeo periódico). */
    public static function since(int $conversationId, int $afterId, int $limit = 100, int $viewerId = 0): array
    {
        return self::withAttachments(self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.conversation_id = ? AND ' . self::VISIBLE
            . ' AND m.id > ? ORDER BY m.id ASC LIMIT ' . max(1, min(200, $limit)),
            [$conversationId, $viewerId, $afterId]
        ), $viewerId);
    }

    /** Mensajes ya cargados (ids entre $fromId y $toId) que cambiaron desde $since: reacciones, fijados o borrados. */
    public static function updatedSince(int $conversationId, int $fromId, int $toId, string $since, int $viewerId): array
    {
        if ($fromId < 1 || $toId < $fromId) {
            return [];
        }
        return self::withAttachments(self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.conversation_id = ? AND ' . self::VISIBLE
            . ' AND m.id BETWEEN ? AND ? AND m.updated_at >= ? ORDER BY m.id ASC LIMIT 200',
            [$conversationId, $viewerId, $fromId, $toId, $since]
        ), $viewerId);
    }

    /** Ids de mensajes ya cargados (desde $fromId) que se eliminaron después. */
    public static function deletedSince(int $conversationId, int $fromId): array
    {
        return array_map('intval', array_column(self::fetchAll(
            'SELECT id FROM messages WHERE conversation_id = ? AND id >= ? AND deleted_at IS NOT NULL ORDER BY id DESC LIMIT 200',
            [$conversationId, $fromId]
        ), 'id'));
    }

    /** Buscar texto en la conversación (lo visible para quien busca), del más reciente al más antiguo. */
    public static function search(int $conversationId, int $viewerId, string $term, int $limit): array
    {
        return self::withAttachments(self::fetchAll(
            'SELECT ' . self::COLUMNS . " FROM messages m WHERE m.conversation_id = ? AND " . self::VISIBLE . "
               AND m.kind = 'message' AND m.deleted_at IS NULL AND m.e2ee_epoch IS NULL AND m.body LIKE ?
             ORDER BY m.id DESC LIMIT " . max(1, min(100, $limit)),
            [$conversationId, $viewerId, '%' . self::likeEscape($term) . '%']
        ), $viewerId);
    }

    /** Mensajes fijados de la conversación (los más recientes primero). */
    public static function pinned(int $conversationId, int $viewerId): array
    {
        return self::withAttachments(self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.conversation_id = ? AND ' . self::VISIBLE . '
               AND m.pinned_at IS NOT NULL AND m.deleted_at IS NULL ORDER BY m.pinned_at DESC LIMIT 10',
            [$conversationId, $viewerId]
        ), $viewerId);
    }

    /**
     * Contenido enviado en la conversación, del más reciente al más antiguo: $type «media» (fotos, notas de voz,
     * archivos cifrados y GIF) o «links» (mensajes sin cifrar con enlaces; los cifrados los busca la app).
     *
     * @return array{messages: list<array>, hasMore: bool}
     */
    public static function shared(int $conversationId, int $viewerId, string $type, ?int $beforeId, int $limit): array
    {
        $limit = max(1, min(60, $limit));
        $params = [$conversationId, $viewerId];
        if ($beforeId) {
            $params[] = $beforeId;
        }
        $filter = $type === 'links'
            ? "m.e2ee_epoch IS NULL AND (m.body LIKE '%http://%' OR m.body LIKE '%https://%')"
            : 'm.view_once = 0 AND (m.media_path IS NOT NULL OR m.gif_id IS NOT NULL)';
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.conversation_id = ? AND ' . self::VISIBLE . "
               AND m.kind = 'message' AND m.deleted_at IS NULL AND $filter" . ($beforeId ? ' AND m.id < ?' : '') . '
             ORDER BY m.id DESC LIMIT ' . ($limit + 1),
            $params
        );
        return ['messages' => self::withAttachments(array_slice($rows, 0, $limit), $viewerId), 'hasMore' => count($rows) > $limit];
    }

    public static function pinnedCount(int $conversationId): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM messages WHERE conversation_id = ? AND pinned_at IS NOT NULL AND deleted_at IS NULL
               AND (expires_at IS NULL OR expires_at > NOW())',
            [$conversationId]
        );
    }

    public static function setPinned(int $id, ?int $userId): bool
    {
        return self::execute(
            $userId !== null
                ? 'UPDATE messages SET pinned_at = NOW(), pinned_by = ? WHERE id = ? AND pinned_at IS NULL AND deleted_at IS NULL'
                : 'UPDATE messages SET pinned_at = NULL, pinned_by = NULL WHERE id = ? AND pinned_at IS NOT NULL',
            $userId !== null ? [$userId, $id] : [$id]
        ) === 1;
    }

    /** Reacción de una persona (una por mensaje; otra la reemplaza). null la quita. */
    public static function react(int $id, int $userId, ?string $emoji): void
    {
        if ($emoji === null) {
            self::execute('DELETE FROM message_reactions WHERE message_id = ? AND user_id = ?', [$id, $userId]);
        } else {
            self::execute(
                'INSERT INTO message_reactions (message_id, user_id, emoji) VALUES (?, ?, ?)
                 ON DUPLICATE KEY UPDATE emoji = VALUES(emoji), created_at = NOW()',
                [$id, $userId, $emoji]
            );
        }
        self::execute('UPDATE messages SET updated_at = NOW() WHERE id = ?', [$id]);
    }

    /** «Eliminar para ti». */
    public static function hideFor(int $id, int $userId): void
    {
        self::execute('INSERT IGNORE INTO message_hidden (user_id, message_id) VALUES (?, ?)', [$userId, $id]);
    }

    /** Mensaje visible para quien mira (no caducado ni oculto). */
    public static function findVisible(int $id, int $viewerId): ?array
    {
        return self::fetchOne('SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.id = ? AND ' . self::VISIBLE . ' LIMIT 1', [$id, $viewerId]);
    }

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT ' . self::COLUMNS . ' FROM messages m WHERE m.id = ? LIMIT 1', [$id]);
    }

    /** Hora de la base de datos (referencia del sondeo de cambios). */
    public static function now(): string
    {
        return (string) self::fetchValue('SELECT NOW()');
    }

    public static function hasFrom(int $conversationId, int $senderId): bool
    {
        return (bool) self::fetchValue(
            "SELECT 1 FROM messages WHERE conversation_id = ? AND sender_id = ? AND kind = 'message' LIMIT 1",
            [$conversationId, $senderId]
        );
    }

    /**
     * Mensajes temporales caducados: se vacían (texto, adjuntos y archivos) y quedan ocultos por expires_at. La fila
     * se conserva para no mover el «leído hasta» de nadie.
     */
    public static function purgeExpired(int $conversationId): void
    {
        $stale = self::fetchAll(
            'SELECT id, media_path FROM messages WHERE conversation_id = ? AND view_once = 1 AND media_path IS NOT NULL
               AND created_at < NOW() - INTERVAL ? DAY LIMIT 200',
            [$conversationId, (int) \Trevix\Core\Config::get('app.chat.view_once_days', 14)]
        );
        foreach ($stale as $row) {
            self::clearMedia((int) $row['id'], $row['media_path']);
        }
        $rows = self::fetchAll(
            'SELECT id, media_path, media_poster FROM messages WHERE conversation_id = ? AND expires_at IS NOT NULL AND expires_at <= NOW()
               AND deleted_at IS NULL LIMIT 500',
            [$conversationId]
        );
        if ($rows === []) {
            return;
        }
        $ids = array_map('intval', array_column($rows, 'id'));
        self::execute('UPDATE messages SET ' . self::CLEAR . ' WHERE id IN (' . implode(',', $ids) . ')');
        self::execute('DELETE FROM message_reactions WHERE message_id IN (' . implode(',', $ids) . ')');
        foreach ($rows as $row) {
            MediaUpload::delete($row['media_path']);
            MediaUpload::delete($row['media_poster']);
        }
    }

    /** Solo quien lo envió puede eliminarlo. Devuelve false si no era suyo o ya estaba eliminado. */
    public static function deleteOwn(int $id, int $senderId): bool
    {
        $message = self::find($id);
        if ($message === null || (int) $message['sender_id'] !== $senderId || $message['deleted_at'] !== null || $message['kind'] !== 'message') {
            return false;
        }
        $changed = self::execute(
            'UPDATE messages SET ' . self::CLEAR . ' WHERE id = ? AND sender_id = ? AND deleted_at IS NULL',
            [$id, $senderId]
        );
        if ($changed === 1) {
            self::execute('DELETE FROM message_reactions WHERE message_id = ?', [$id]);
            MediaUpload::delete($message['media_path']);
            MediaUpload::delete($message['media_poster']);
        }
        return $changed === 1;
    }

    /** Moderación: vacía un mensaje reportado igual que si lo hubiera eliminado quien lo envió. */
    public static function deleteByModerator(int $id): bool
    {
        $message = self::find($id);
        if ($message === null || $message['deleted_at'] !== null) {
            return false;
        }
        $changed = self::execute(
            'UPDATE messages SET ' . self::CLEAR . ' WHERE id = ? AND deleted_at IS NULL',
            [$id]
        );
        if ($changed === 1) {
            MediaUpload::delete($message['media_path']);
            MediaUpload::delete($message['media_poster']);
        }
        return $changed === 1;
    }

    /** Antes de eliminar una cuenta: borra sus mensajes y devuelve los archivos que hay que quitar del disco. */
    public static function deleteAllFrom(int $userId): array
    {
        $rows = self::fetchAll(
            'SELECT media_path, media_poster FROM messages WHERE sender_id = ? AND (media_path IS NOT NULL OR media_poster IS NOT NULL)',
            [$userId]
        );
        self::execute('DELETE FROM messages WHERE sender_id = ?', [$userId]);
        return array_values(array_filter(array_merge(array_column($rows, 'media_path'), array_column($rows, 'media_poster'))));
    }

    /** Texto corto de un mensaje para vistas previas (respuestas, bandeja). */
    public static function summary(array $m): string
    {
        return match (true) {
            $m['deleted_at'] !== null                                   => t('Mensaje eliminado'),
            !empty($m['view_once']) && str_starts_with((string) ($m['media_mime'] ?? ''), 'video/') => t('Video de visualización única'),
            !empty($m['view_once'])                                     => t('Foto de visualización única'),
            ($m['e2ee_epoch'] ?? null) !== null                         => t('Mensaje cifrado'),
            ($m['context'] ?? null) === 'story_reaction'                => t('Reaccionó a una historia: {emoji}', ['emoji' => $m['body']]),
            ($m['body'] ?? null) !== null && $m['body'] !== ''          => mb_strimwidth((string) preg_replace('/\s+/u', ' ', (string) $m['body']), 0, 100, '…'),
            ($m['location_lat'] ?? null) !== null                       => t('Ubicación'),
            !empty($m['media_path']) && str_starts_with((string) ($m['media_mime'] ?? ''), 'audio/') => t('Nota de voz'),
            !empty($m['media_path']) && str_starts_with((string) ($m['media_mime'] ?? ''), 'video/') => t('Video'),
            !empty($m['media_path'])                                    => t('Foto'),
            ($m['media_cleared_at'] ?? null) !== null                   => t('Archivo eliminado'),
            ($m['gif_kind'] ?? null) === 'sticker'                      => t('Sticker'),
            ($m['gif_kind'] ?? null) !== null                           => 'GIF',
            default                                                     => t('Canción'),
        };
    }

    /** Vista previa de los mensajes a los que responden otros: quién lo envió y un resumen. */
    private static function replyPreviews(array $ids, int $viewerId): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids))));
        if ($ids === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT m.id, m.sender_id, m.body, m.e2ee_epoch, m.media_path, m.media_mime, m.media_cleared_at, m.view_once, m.gif_kind,
                    m.location_lat, m.deleted_at,
                    (m.expires_at IS NOT NULL AND m.expires_at <= NOW()) AS expired, (SELECT 1 FROM message_hidden h WHERE h.message_id = m.id AND h.user_id = ?) AS hidden,
                    u.display_name, u.username
             FROM messages m LEFT JOIN users u ON u.id = m.sender_id
             WHERE m.id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')',
            array_merge([$viewerId], $ids)
        );
        $out = [];
        foreach ($rows as $r) {
            $gone = $r['hidden'] !== null || (int) $r['expired'] === 1;
            $out[(int) $r['id']] = [
                'id'           => (int) $r['id'],
                'sender_id'    => $r['sender_id'] !== null ? (int) $r['sender_id'] : null,
                'sender_name'  => $r['display_name'] ?? t('Cuenta no disponible'),
                'is_mine'      => $r['sender_id'] !== null && (int) $r['sender_id'] === $viewerId,
                'text'         => $gone ? t('Mensaje no disponible') : self::summary($r),
                'available'    => !$gone && $r['deleted_at'] === null,
                // La app descifra la vista previa con la clave del chat.
                'e2ee'         => !$gone && $r['deleted_at'] === null && $r['e2ee_epoch'] !== null && empty($r['view_once'])
                    ? ['epoch' => (int) $r['e2ee_epoch'], 'ciphertext' => (string) $r['body']] : null,
            ];
        }
        return $out;
    }

    /** Reacciones agrupadas por emoji y la de quien mira. @return array<int, array{list: list<array>, mine: ?string}> */
    private static function reactionsFor(array $ids, int $viewerId): array
    {
        $ids = array_values(array_filter($ids));
        if ($ids === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT message_id, user_id, emoji FROM message_reactions
             WHERE message_id IN (' . implode(',', array_fill(0, count($ids), '?')) . ') ORDER BY created_at ASC',
            $ids
        );
        $out = [];
        foreach ($rows as $r) {
            $mid = (int) $r['message_id'];
            $out[$mid] ??= ['list' => [], 'mine' => null];
            $emoji = (string) $r['emoji'];
            $out[$mid]['list'][$emoji] = ($out[$mid]['list'][$emoji] ?? 0) + 1;
            if ((int) $r['user_id'] === $viewerId) {
                $out[$mid]['mine'] = $emoji;
            }
        }
        foreach ($out as &$entry) {
            $list = [];
            foreach ($entry['list'] as $emoji => $count) {
                $list[] = ['emoji' => (string) $emoji, 'count' => $count];
            }
            $entry['list'] = $list;
        }
        return $out;
    }
}
