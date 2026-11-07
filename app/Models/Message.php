<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Services\MediaUpload;

/** Mensajes de una conversación (texto, una imagen o una canción). Borrar un mensaje lo vacía y deja la marca "Mensaje eliminado". */
final class Message extends Model
{
    private const COLUMNS = 'id, conversation_id, sender_id, body, media_path, media_mime, story_id, song_id, deleted_at, created_at';

    /** @param array{path:string, mime_type:string}|null $media */
    public static function create(int $conversationId, int $senderId, ?string $body, ?array $media, ?int $storyId = null, ?int $songId = null): int
    {
        self::execute(
            'INSERT INTO messages (conversation_id, sender_id, body, media_path, media_mime, story_id, song_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$conversationId, $senderId, $body, $media['path'] ?? null, $media['mime_type'] ?? null, $storyId, $songId]
        );
        $messageId = (int) self::db()->lastInsertId();
        if ($songId !== null) {
            Song::incrementUses($songId);
        }
        return $messageId;
    }

    /**
     * Añade a cada mensaje la historia a la que responde, si sigue activa (clave "story"), y la canción
     * adjunta (clave "song"). Un mensaje sin texto, imagen ni canción que no se eliminó es uno cuya
     * canción se borró: se muestra como «Canción no disponible».
     */
    public static function withAttachments(array $messages): array
    {
        $stories = Story::previewsFor(array_column($messages, 'story_id'));
        $songs = Song::cardsFor(array_column($messages, 'song_id'));
        foreach ($messages as &$message) {
            $message['story'] = $stories[(int) ($message['story_id'] ?? 0)] ?? null;
            $songId = (int) ($message['song_id'] ?? 0);
            $orphan = $message['deleted_at'] === null && ($message['body'] ?? null) === null && $message['media_path'] === null && $songId === 0;
            $message['song'] = $songId > 0 ? $songs[$songId] : ($orphan ? Song::unavailable(0) : null);
        }
        return $messages;
    }

    /** Mensaje listo para mostrar (con historia y canción). */
    public static function findFull(int $id): ?array
    {
        $message = self::find($id);
        return $message !== null ? self::withAttachments([$message])[0] : null;
    }

    /**
     * Últimos mensajes (o los anteriores a $beforeId), en orden cronológico.
     *
     * @return array{messages: list<array>, hasMore: bool}
     */
    public static function page(int $conversationId, ?int $beforeId, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages WHERE conversation_id = ?' . ($beforeId ? ' AND id < ?' : '')
            . ' ORDER BY id DESC LIMIT ' . ($limit + 1),
            $beforeId ? [$conversationId, $beforeId] : [$conversationId]
        );
        return [
            'messages' => self::withAttachments(array_reverse(array_slice($rows, 0, $limit))),
            'hasMore'  => count($rows) > $limit,
        ];
    }

    /** Mensajes nuevos posteriores a $afterId (sondeo periódico). */
    public static function since(int $conversationId, int $afterId, int $limit = 100): array
    {
        return self::withAttachments(self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM messages WHERE conversation_id = ? AND id > ? ORDER BY id ASC LIMIT ' . max(1, min(200, $limit)),
            [$conversationId, $afterId]
        ));
    }

    /** Ids de mensajes ya cargados (desde $fromId) que se eliminaron después. */
    public static function deletedSince(int $conversationId, int $fromId): array
    {
        return array_map('intval', array_column(self::fetchAll(
            'SELECT id FROM messages WHERE conversation_id = ? AND id >= ? AND deleted_at IS NOT NULL ORDER BY id DESC LIMIT 200',
            [$conversationId, $fromId]
        ), 'id'));
    }

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT ' . self::COLUMNS . ' FROM messages WHERE id = ? LIMIT 1', [$id]);
    }

    public static function hasFrom(int $conversationId, int $senderId): bool
    {
        return (bool) self::fetchValue(
            'SELECT 1 FROM messages WHERE conversation_id = ? AND sender_id = ? LIMIT 1',
            [$conversationId, $senderId]
        );
    }

    /** Solo quien lo envió puede eliminarlo. Devuelve false si no era suyo o ya estaba eliminado. */
    public static function deleteOwn(int $id, int $senderId): bool
    {
        $message = self::find($id);
        if ($message === null || (int) $message['sender_id'] !== $senderId || $message['deleted_at'] !== null) {
            return false;
        }
        $changed = self::execute(
            'UPDATE messages SET body = NULL, media_path = NULL, media_mime = NULL, song_id = NULL, deleted_at = NOW()
             WHERE id = ? AND sender_id = ? AND deleted_at IS NULL',
            [$id, $senderId]
        );
        if ($changed === 1) {
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
            'UPDATE messages SET body = NULL, media_path = NULL, media_mime = NULL, song_id = NULL, deleted_at = NOW() WHERE id = ? AND deleted_at IS NULL',
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
}
