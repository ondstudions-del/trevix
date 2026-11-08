<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Services\Mentions;

/**
 * Notificaciones de actividad. Nunca se avisa a uno mismo, ni a cuentas inactivas, ni entre cuentas
 * bloqueadas, ni de tipos que la persona desactivó en Configuración. Repetir una acción (seguir, dar
 * me gusta) reemplaza el aviso anterior en lugar de duplicarlo, y deshacerla lo retira.
 * Las solicitudes de seguimiento no se guardan aquí: se leen en vivo de follow_requests.
 */
final class Notification extends Model
{
    /** Tipos que muestra la pestaña "Menciones". */
    public const MENTION_TYPES = ['mention', 'reply', 'comment'];

    /** Crea el aviso si corresponde. Devuelve true si se creó. */
    public static function notify(
        int $userId,
        int $actorId,
        string $type,
        ?int $postId = null,
        ?int $commentId = null,
        ?int $communityId = null
    ): bool {
        $column = User::NOTIFY_COLUMNS[$type] ?? null;
        if ($column === null || $userId === $actorId || $userId < 1 || $actorId < 1) {
            return false;
        }
        $allowed = (bool) self::fetchValue(
            "SELECT 1 FROM users u WHERE u.id = ? AND u.status = 'active' AND u.$column = 1
               AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = u.id AND b.blocked_id = ?) OR (b.blocker_id = ? AND b.blocked_id = u.id))
             LIMIT 1",
            [$userId, $actorId, $actorId]
        );
        if (!$allowed) {
            return false;
        }
        self::remove($userId, $actorId, $type, $postId, $commentId, $communityId);
        self::execute(
            'INSERT INTO notifications (user_id, actor_id, type, post_id, comment_id, community_id) VALUES (?, ?, ?, ?, ?, ?)',
            [$userId, $actorId, $type, $postId, $commentId, $communityId]
        );
        return true;
    }

    /** Tipos que envía TREVIX (sin persona que actúe) sobre la revisión de una canción. */
    public const SONG_TYPES = ['song_approved', 'song_rejected', 'song_removed'];

    /** Aviso del equipo sobre una canción del artista. No depende de preferencias: es parte de la revisión. */
    public static function notifySong(int $userId, string $type, int $songId): void
    {
        if (!in_array($type, self::SONG_TYPES, true)) {
            return;
        }
        self::execute(
            "INSERT INTO notifications (user_id, actor_id, type, song_id)
             SELECT id, NULL, ?, ? FROM users WHERE id = ? AND status = 'active'",
            [$type, $songId, $userId]
        );
    }

    /**
     * Avisa a las personas mencionadas con @ que pueden ver la publicación.
     *
     * @param list<int>    $skipIds   cuentas que ya recibieron otro aviso por la misma acción
     * @param list<string> $skipNames menciones que ya estaban (al editar)
     */
    public static function notifyMentions(int $actorId, ?string $text, int $postId, ?int $commentId = null, array $skipIds = [], array $skipNames = []): void
    {
        $names = array_values(array_diff(Mentions::extract($text), $skipNames));
        if ($names === []) {
            return;
        }
        $ids = self::fetchAll(
            'SELECT id FROM users WHERE status = \'active\' AND username IN (' . implode(',', array_fill(0, count($names), '?')) . ')',
            $names
        );
        foreach (array_map('intval', array_column($ids, 'id')) as $id) {
            if ($id === $actorId || in_array($id, $skipIds, true) || Post::findVisible($postId, $id) === null) {
                continue;
            }
            self::notify($id, $actorId, 'mention', $postId, $commentId);
        }
    }

    /** Retira el aviso de una acción que se deshizo (quitar el me gusta, dejar de seguir). */
    public static function remove(
        int $userId,
        int $actorId,
        string $type,
        ?int $postId = null,
        ?int $commentId = null,
        ?int $communityId = null
    ): void {
        self::execute(
            'DELETE FROM notifications WHERE user_id = ? AND actor_id = ? AND type = ? AND post_id <=> ? AND comment_id <=> ? AND community_id <=> ?',
            [$userId, $actorId, $type, $postId, $commentId, $communityId]
        );
    }

    /** Retira los avisos de un tipo sobre una comunidad que generó una persona (p. ej. al resolver su solicitud). */
    public static function removeForCommunity(int $communityId, int $actorId, string $type): void
    {
        self::execute(
            'DELETE FROM notifications WHERE community_id = ? AND actor_id = ? AND type = ?',
            [$communityId, $actorId, $type]
        );
    }

    /** Al bloquear: se borran los avisos entre ambas cuentas, en los dos sentidos. */
    public static function removeBetween(int $a, int $b): void
    {
        self::execute(
            'DELETE FROM notifications WHERE (user_id = ? AND actor_id = ?) OR (user_id = ? AND actor_id = ?)',
            [$a, $b, $b, $a]
        );
    }

    public static function unreadCount(int $userId): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM notifications n LEFT JOIN users a ON a.id = n.actor_id
             WHERE n.user_id = ? AND n.read_at IS NULL AND (n.actor_id IS NULL OR a.status = 'active')",
            [$userId]
        );
    }

    /**
     * Avisos del usuario, del más reciente al más antiguo, paginados por id ("ver más" usa el último id).
     *
     * @param list<string>|null $types
     * @return array{items: list<array>, hasMore: bool, nextBefore: ?int}
     */
    public static function listFor(int $userId, ?array $types, ?int $beforeId, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $where = '';
        $params = [$userId];
        if ($types !== null && $types !== []) {
            $where .= ' AND n.type IN (' . implode(',', array_fill(0, count($types), '?')) . ')';
            array_push($params, ...$types);
        }
        if ($beforeId !== null && $beforeId > 0) {
            $where .= ' AND n.id < ?';
            $params[] = $beforeId;
        }

        $rows = self::fetchAll(
            "SELECT n.id, n.type, n.post_id, n.comment_id, n.community_id, n.song_id, n.read_at, n.created_at,
                    a.id AS actor_id, a.username, a.display_name, a.avatar_path, a.is_verified, a.is_private,
                    COALESCE(NULLIF(p.body, ''), sp.body) AS post_body,
                    COALESCE(NULLIF(c.body, ''), CASE c.gif_kind WHEN 'sticker' THEN 'Sticker' WHEN 'gif' THEN 'GIF' END) AS comment_body,
                    cm.name AS community_name, sg.title AS song_title, sg.review_note AS song_note,
                    COALESCE((SELECT pm.path FROM post_media pm WHERE pm.post_id = COALESCE(sp.id, p.id) AND pm.type = 'image'
                      ORDER BY pm.position LIMIT 1), sg.cover_path) AS thumb
             FROM notifications n
             LEFT JOIN users a ON a.id = n.actor_id
             LEFT JOIN posts p ON p.id = n.post_id
             LEFT JOIN posts sp ON sp.id = p.shared_post_id
             LEFT JOIN comments c ON c.id = n.comment_id
             LEFT JOIN communities cm ON cm.id = n.community_id
             LEFT JOIN songs sg ON sg.id = n.song_id
             WHERE n.user_id = ? AND (n.actor_id IS NULL OR a.status = 'active')$where
             ORDER BY n.id DESC
             LIMIT " . ($limit + 1),
            $params
        );

        $hasMore = count($rows) > $limit;
        $items = array_map([self::class, 'present'], array_slice($rows, 0, $limit));
        return [
            'items'      => $items,
            'hasMore'    => $hasMore,
            'nextBefore' => $hasMore && $items !== [] ? (int) end($items)['id'] : null,
        ];
    }

    /** Aviso propio por id, para abrirlo. */
    public static function findFor(int $userId, int $id): ?array
    {
        return self::fetchOne(
            'SELECT n.id, n.type, n.post_id, n.comment_id, n.song_id, a.username, cm.slug AS community_slug
             FROM notifications n
             LEFT JOIN users a ON a.id = n.actor_id
             LEFT JOIN communities cm ON cm.id = n.community_id
             WHERE n.id = ? AND n.user_id = ? LIMIT 1',
            [$id, $userId]
        );
    }

    public static function markRead(int $userId, int $id): void
    {
        self::execute('UPDATE notifications SET read_at = NOW() WHERE id = ? AND user_id = ? AND read_at IS NULL', [$id, $userId]);
    }

    /** Devuelve cuántos avisos se marcaron. */
    public static function markAllRead(int $userId): int
    {
        return self::execute('UPDATE notifications SET read_at = NOW() WHERE user_id = ? AND read_at IS NULL', [$userId]);
    }

    /** Página a la que lleva un aviso. */
    public static function targetUrl(array $n): string
    {
        if (in_array($n['type'] ?? '', self::SONG_TYPES, true)) {
            return url('artist.php', ['status' => match ($n['type']) {
                'song_approved' => 'published',
                'song_rejected' => 'rejected',
                default         => 'removed',
            }]);
        }
        if (!empty($n['post_id'])) {
            return url('post.php', ['id' => (int) $n['post_id']]) . (!empty($n['comment_id']) ? '#comentario-' . (int) $n['comment_id'] : '');
        }
        if (($n['type'] ?? '') === 'story_mention' && !empty($n['username'])) {
            return url('stories.php', ['u' => $n['username']]);
        }
        if (!empty($n['community_slug'])) {
            return url('community.php', [
                'c'   => $n['community_slug'],
                'tab' => ($n['type'] ?? '') === 'community_request' ? 'requests' : null,
            ]);
        }
        if (!empty($n['username'])) {
            return url('profile.php', ['u' => $n['username']]);
        }
        return url('notifications.php');
    }

    private static function present(array $r): array
    {
        $isComment = in_array($r['type'], ['comment', 'reply'], true) || ($r['type'] === 'mention' && $r['comment_id'] !== null);
        $community = (string) ($r['community_name'] ?? 'una comunidad');
        $song = '«' . (string) ($r['song_title'] ?? 'tu canción') . '»';
        $text = match ($r['type']) {
            'song_approved'      => 'aprobó tu canción ' . $song . ': ya está en la biblioteca de música.',
            'song_rejected'      => 'no aprobó tu canción ' . $song . '.',
            'song_removed'       => 'retiró tu canción ' . $song . ' de la biblioteca.',
            'like'               => 'le gustó tu publicación.',
            'comment'            => 'comentó tu publicación:',
            'reply'              => 'respondió a tu comentario:',
            'mention'            => $r['comment_id'] !== null ? 'te mencionó en un comentario:' : 'te mencionó en una publicación:',
            'share'              => 'compartió tu publicación.',
            'follow'             => 'comenzó a seguirte.',
            'follow_accepted'    => 'aceptó tu solicitud de seguimiento.',
            'community_request'  => 'solicitó unirse a ' . $community . '.',
            'community_accepted' => 'te aceptó en ' . $community . '.',
            'story_mention'      => 'te mencionó en su historia.',
            'event_going'        => 'asistirá a tu evento.',
            'featured'           => 'destacó tu publicación: aparece arriba en el inicio y en Destacados.',
            default              => 'tiene actividad nueva para ti.',
        };
        $excerpt = $isComment ? $r['comment_body'] : ($r['type'] === 'mention' ? $r['post_body'] : null);
        if (in_array($r['type'], ['song_rejected', 'song_removed'], true)) {
            $excerpt = $r['song_note'] !== null ? 'Motivo: ' . $r['song_note'] : null;
        }

        return [
            'id'         => (int) $r['id'],
            'type'       => $r['type'],
            'actor'      => $r['actor_id'] !== null ? [
                'id'           => (int) $r['actor_id'],
                'username'     => $r['username'],
                'display_name' => $r['display_name'],
                'avatar_path'  => $r['avatar_path'],
                'is_verified'  => (int) $r['is_verified'],
                'is_private'   => (int) $r['is_private'],
            ] : null,
            'text'       => $text,
            'excerpt'    => $excerpt !== null && $excerpt !== '' ? mb_strimwidth(preg_replace('/\s+/u', ' ', $excerpt), 0, 140, '…') : null,
            'thumb'      => $r['thumb'],
            'post_id'    => $r['post_id'] !== null ? (int) $r['post_id'] : null,
            'comment_id' => $r['comment_id'] !== null ? (int) $r['comment_id'] : null,
            'community_id' => $r['community_id'] !== null ? (int) $r['community_id'] : null,
            'song_id'    => $r['song_id'] !== null ? (int) $r['song_id'] : null,
            'read'       => $r['read_at'] !== null,
            'created_at' => $r['created_at'],
            'url'        => url('notifications.php', ['open' => (int) $r['id']]),
        ];
    }
}
