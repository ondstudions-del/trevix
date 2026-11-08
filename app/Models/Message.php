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
 */
final class Message extends Model
{
    private const COLUMNS = 'm.id, m.conversation_id, m.sender_id, m.kind, m.reply_to_id, m.forwarded, m.body, m.media_path,
        m.media_mime, m.media_duration, m.story_id, m.song_id, m.gif_id, m.gif_kind, m.gif_url, m.gif_width, m.gif_height,
        m.gif_title, m.location_lat, m.location_lng, m.location_name, m.pinned_at, m.pinned_by, m.expires_at, m.deleted_at,
        m.created_at';

    private const CLEAR = 'body = NULL, media_path = NULL, media_mime = NULL, media_duration = NULL, song_id = NULL,
        gif_id = NULL, gif_kind = NULL, gif_url = NULL, gif_width = NULL, gif_height = NULL, gif_title = NULL,
        location_lat = NULL, location_lng = NULL, location_name = NULL, pinned_at = NULL, pinned_by = NULL, deleted_at = NOW()';

    /** Visible: no caducado ni oculto para quien mira (el ? es su id). */
    private const VISIBLE = '(m.expires_at IS NULL OR m.expires_at > NOW())
        AND NOT EXISTS (SELECT 1 FROM message_hidden h WHERE h.message_id = m.id AND h.user_id = ?)';

    /**
     * @param array{path:string, mime_type:string, duration?:int}|null $media imagen o nota de voz
     * @param array|null $gif campos gif_* de Giphy::resolve
     * @param array{kind?:string, reply_to_id?:int|null, forwarded?:bool, location?:array{lat:float, lng:float, name:?string}|null, expires_seconds?:int|null} $extra
     */
    public static function create(int $conversationId, int $senderId, ?string $body, ?array $media, ?int $storyId = null, ?int $songId = null, ?array $gif = null, array $extra = []): int
    {
        $location = $extra['location'] ?? null;
        $expires = (int) ($extra['expires_seconds'] ?? 0);
        self::execute(
            'INSERT INTO messages (conversation_id, sender_id, kind, reply_to_id, forwarded, body, media_path, media_mime, media_duration,
                                   story_id, song_id, gif_id, gif_kind, gif_url, gif_width, gif_height, gif_title,
                                   location_lat, location_lng, location_name, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, IF(? > 0, NOW() + INTERVAL ? SECOND, NULL))',
            [
                $conversationId, $senderId, $extra['kind'] ?? 'message', $extra['reply_to_id'] ?? null, !empty($extra['forwarded']) ? 1 : 0,
                $body, $media['path'] ?? null, $media['mime_type'] ?? null, $media['duration'] ?? null,
                $storyId, $songId, $gif['gif_id'] ?? null, $gif['gif_kind'] ?? null, $gif['gif_url'] ?? null,
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
     */
    public static function withAttachments(array $messages, int $viewerId = 0): array
    {
        if ($messages === []) {
            return [];
        }
        $stories = Story::previewsFor(array_column($messages, 'story_id'));
        $songs = Song::cardsFor(array_column($messages, 'song_id'));
        $replies = self::replyPreviews(array_column($messages, 'reply_to_id'), $viewerId);
        $reactions = self::reactionsFor(array_map('intval', array_column($messages, 'id')), $viewerId);
        foreach ($messages as &$message) {
            $message['story'] = $stories[(int) ($message['story_id'] ?? 0)] ?? null;
            $message['gif'] = Giphy::fromRow($message);
            $songId = (int) ($message['song_id'] ?? 0);
            $orphan = $message['deleted_at'] === null && ($message['kind'] ?? 'message') === 'message'
                && ($message['body'] ?? null) === null && $message['media_path'] === null
                && $message['gif'] === null && $songId === 0 && ($message['location_lat'] ?? null) === null;
            $message['song'] = $songId > 0 ? $songs[$songId] : ($orphan ? Song::unavailable(0) : null);
            $message['reply'] = $replies[(int) ($message['reply_to_id'] ?? 0)] ?? null;
            $message['reactions'] = $reactions[(int) $message['id']] ?? ['list' => [], 'mine' => null];
        }
        return $messages;
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
               AND m.kind = 'message' AND m.deleted_at IS NULL AND m.body LIKE ?
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
        $rows = self::fetchAll(
            'SELECT id, media_path FROM messages WHERE conversation_id = ? AND expires_at IS NOT NULL AND expires_at <= NOW()
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
        }
        return $changed === 1;
    }

    /** Antes de eliminar una cuenta: borra sus mensajes y devuelve las imágenes que hay que quitar del disco. */
    public static function deleteAllFrom(int $userId): array
    {
        $paths = array_column(self::fetchAll(
            'SELECT media_path FROM messages WHERE sender_id = ? AND media_path IS NOT NULL',
            [$userId]
        ), 'media_path');
        self::execute('DELETE FROM messages WHERE sender_id = ?', [$userId]);
        return $paths;
    }

    /** Texto corto de un mensaje para vistas previas (respuestas, bandeja). */
    public static function summary(array $m): string
    {
        return match (true) {
            $m['deleted_at'] !== null                                   => 'Mensaje eliminado',
            ($m['body'] ?? null) !== null && $m['body'] !== ''          => mb_strimwidth((string) preg_replace('/\s+/u', ' ', (string) $m['body']), 0, 100, '…'),
            ($m['location_lat'] ?? null) !== null                       => 'Ubicación',
            !empty($m['media_path']) && str_starts_with((string) ($m['media_mime'] ?? ''), 'audio/') => 'Nota de voz',
            !empty($m['media_path'])                                    => 'Foto',
            ($m['gif_kind'] ?? null) === 'sticker'                      => 'Sticker',
            ($m['gif_kind'] ?? null) !== null                           => 'GIF',
            default                                                     => 'Canción',
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
            'SELECT m.id, m.sender_id, m.body, m.media_path, m.media_mime, m.gif_kind, m.location_lat, m.deleted_at,
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
                'sender_name'  => $r['display_name'] ?? 'Cuenta no disponible',
                'is_mine'      => $r['sender_id'] !== null && (int) $r['sender_id'] === $viewerId,
                'text'         => $gone ? 'Mensaje no disponible' : self::summary($r),
                'available'    => !$gone && $r['deleted_at'] === null,
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
