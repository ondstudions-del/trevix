<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;
use Trevix\Services\MediaUpload;

/**
 * Historias de 24 horas. Una persona ve las historias de una cuenta si es la suya, o si la cuenta está
 * activa, no hay bloqueo entre ambas y la cuenta es pública o la sigue. La barra del inicio muestra
 * solo las propias y las de las cuentas que sigue; el perfil permite abrir las de cualquier cuenta visible.
 */
final class Story extends Model
{
    public const BACKGROUNDS = [
        'violet'   => 'Violeta',
        'blue'     => 'Azul',
        'midnight' => 'Medianoche',
        'sunset'   => 'Atardecer',
        'ocean'    => 'Océano',
        'graphite' => 'Grafito',
    ];

    /** Segundos que se muestra una foto o un texto. */
    public const IMAGE_SECONDS = 6;

    /** Autor visible para quien mira (alias u). Usa 4 parámetros: el id de quien mira. */
    private const VISIBLE_AUTHOR = "u.status = 'active' AND (u.id = ? OR (
            (u.is_private = 0 OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id))
            AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = ?))
        ))";

    private const USER_COLUMNS = 'u.id AS user_id, u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS user_status,
        u.message_privacy';

    // -------------------------------------------------------------------------
    // Lectura
    // -------------------------------------------------------------------------

    /**
     * Barra de historias: primero las propias, luego las de las cuentas que sigue con historias sin ver
     * y al final las ya vistas; dentro de cada grupo, la más reciente primero.
     *
     * @return list<array{user: array, seen: bool, latest: string, total: int}>
     */
    public static function tray(int $viewerId, int $limit = 60): array
    {
        $rows = self::fetchAll(
            'SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified,
                    MAX(s.created_at) AS latest, COUNT(*) AS total, SUM(sv.story_id IS NULL) AS unseen
             FROM stories s
             JOIN users u ON u.id = s.user_id
             LEFT JOIN story_views sv ON sv.story_id = s.id AND sv.viewer_id = ?
             WHERE s.expires_at > NOW() AND u.status = \'active\'
               AND (u.id = ? OR (EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id)
                   AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = ?))))
             GROUP BY u.id, u.username, u.display_name, u.avatar_path, u.is_verified
             ORDER BY (u.id = ?) DESC, (SUM(sv.story_id IS NULL) > 0) DESC, latest DESC
             LIMIT ' . max(1, min(100, $limit)),
            [$viewerId, $viewerId, $viewerId, $viewerId, $viewerId, $viewerId]
        );
        return array_map(static fn (array $r): array => [
            'user'   => [
                'id'           => (int) $r['id'],
                'username'     => $r['username'],
                'display_name' => $r['display_name'],
                'avatar_path'  => $r['avatar_path'],
                'is_verified'  => (int) $r['is_verified'],
            ],
            // Las propias nunca se marcan como vistas: quien publica no se cuenta como espectador.
            'seen'   => (int) $r['id'] !== $viewerId && (int) $r['unseen'] === 0,
            'latest' => $r['latest'],
            'total'  => (int) $r['total'],
        ], $rows);
    }

    /**
     * Historias activas de varias cuentas, agrupadas por autor y en orden cronológico,
     * respetando el orden de $authorIds. Las cuentas que quien mira no puede ver se omiten.
     *
     * @return list<array{user: array, items: list<array>, created_at: string}>
     */
    public static function groupsFor(array $authorIds, int $viewerId): array
    {
        $authorIds = array_values(array_unique(array_filter(array_map('intval', $authorIds))));
        if ($authorIds === []) {
            return [];
        }
        $marks = implode(',', array_fill(0, count($authorIds), '?'));
        $rows = self::fetchAll(
            'SELECT s.id, s.media_type, s.media_path, s.mime_type, s.body, s.background, s.overlays, s.filter, s.duration_seconds,
                    s.song_id, s.song_start, s.views_count, s.created_at, ' . self::USER_COLUMNS . ',
                    EXISTS (SELECT 1 FROM story_views sv WHERE sv.story_id = s.id AND sv.viewer_id = ?) AS seen
             FROM stories s
             JOIN users u ON u.id = s.user_id
             WHERE s.expires_at > NOW() AND s.user_id IN (' . $marks . ') AND ' . self::VISIBLE_AUTHOR . '
             ORDER BY s.created_at ASC, s.id ASC',
            array_merge([$viewerId], $authorIds, array_fill(0, 4, $viewerId))
        );

        $songs = Song::cardsFor(array_column($rows, 'song_id'));
        $layers = [];
        foreach ($rows as $r) {
            $layers[(int) $r['id']] = self::decodeOverlays($r['overlays']);
        }
        $pollIds = array_keys(array_filter($layers, static fn (array $items): bool =>
            array_filter($items, static fn (array $o): bool => $o['type'] === 'poll') !== []));
        $polls = self::pollResults($pollIds, $viewerId);
        $groups = [];
        foreach ($rows as $r) {
            $uid = (int) $r['user_id'];
            $songId = (int) $r['song_id'];
            $storyId = (int) $r['id'];
            $groups[$uid] ??= [
                'user'  => [
                    'id'              => $uid,
                    'username'        => $r['username'],
                    'display_name'    => $r['display_name'],
                    'avatar_path'     => $r['avatar_path'],
                    'is_verified'     => (int) $r['is_verified'],
                    'status'          => $r['user_status'],
                    'message_privacy' => $r['message_privacy'],
                ],
                'items' => [],
            ];
            $groups[$uid]['items'][] = [
                'id'         => (int) $r['id'],
                'type'       => $r['media_type'],
                'src'        => $r['media_path'],
                'mime'       => $r['mime_type'],
                'body'       => (string) ($r['body'] ?? ''),
                'background' => $r['background'],
                'overlays'   => $layers[$storyId],
                'filter'     => $r['filter'],
                // Los resultados se ven después de votar (y siempre en las propias).
                'poll'       => isset($polls[$storyId]) ? [
                    'counts'        => $uid === $viewerId || $polls[$storyId]['viewer_choice'] !== null ? $polls[$storyId]['counts'] : null,
                    'total'         => $polls[$storyId]['total'],
                    'viewer_choice' => $polls[$storyId]['viewer_choice'],
                ] : null,
                'seconds'    => (int) $r['duration_seconds'],
                'song'       => $r['song_start'] !== null
                    ? ($songs[$songId] ?? Song::unavailable($songId)) + ['start' => (int) $r['song_start']]
                    : null,
                'views'      => (int) $r['views_count'],
                'seen'       => (bool) $r['seen'],
                'created_at' => $r['created_at'],
            ];
        }

        $ordered = [];
        foreach ($authorIds as $id) {
            if (isset($groups[$id])) {
                $ordered[] = $groups[$id] + ['created_at' => end($groups[$id]['items'])['created_at']];
            }
        }
        return $ordered;
    }

    /** Anillo del avatar en el perfil: si hay historias visibles y si queda alguna sin ver. */
    public static function ringFor(int $authorId, int $viewerId): ?array
    {
        $row = self::fetchOne(
            'SELECT COUNT(*) AS total, SUM(NOT EXISTS (SELECT 1 FROM story_views sv WHERE sv.story_id = s.id AND sv.viewer_id = ?)) AS unseen
             FROM stories s JOIN users u ON u.id = s.user_id
             WHERE s.user_id = ? AND s.expires_at > NOW() AND ' . self::VISIBLE_AUTHOR,
            array_merge([$viewerId, $authorId], array_fill(0, 4, $viewerId))
        );
        if ($row === null || (int) $row['total'] === 0) {
            return null;
        }
        return ['unseen' => $authorId !== $viewerId && (int) $row['unseen'] > 0];
    }

    /** Historia activa visible para quien mira, con los datos de su autor. */
    public static function findVisible(int $id, int $viewerId): ?array
    {
        return self::fetchOne(
            'SELECT s.id, s.user_id, s.media_type, s.media_path, s.body, s.background, s.overlays, ' . self::USER_COLUMNS . '
             FROM stories s JOIN users u ON u.id = s.user_id
             WHERE s.id = ? AND s.expires_at > NOW() AND ' . self::VISIBLE_AUTHOR . ' LIMIT 1',
            array_merge([$id], array_fill(0, 4, $viewerId))
        );
    }

    /** Historia propia (activa o no) para borrarla o ver quién la vio. */
    public static function findOwn(int $id, int $userId): ?array
    {
        return self::fetchOne(
            'SELECT id, user_id, media_type, media_path, views_count, expires_at FROM stories WHERE id = ? AND user_id = ? LIMIT 1',
            [$id, $userId]
        );
    }

    /**
     * Quién vio una historia, del más reciente al más antiguo (solo cuentas activas).
     *
     * @return list<array>
     */
    public static function viewers(int $storyId, int $limit = 100): array
    {
        return self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, sv.viewed_at
             FROM story_views sv JOIN users u ON u.id = sv.viewer_id
             WHERE sv.story_id = ? AND u.status = 'active'
             ORDER BY sv.viewed_at DESC
             LIMIT " . max(1, min(500, $limit)),
            [$storyId]
        );
    }

    /** Datos mínimos de las historias a las que responden unos mensajes (solo las que siguen activas). */
    public static function previewsFor(array $storyIds): array
    {
        $storyIds = array_values(array_unique(array_filter(array_map('intval', $storyIds))));
        if ($storyIds === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT id, media_type, media_path, body, background FROM stories
             WHERE id IN (' . implode(',', array_fill(0, count($storyIds), '?')) . ') AND expires_at > NOW()',
            $storyIds
        );
        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r['id']] = $r;
        }
        return $out;
    }

    // -------------------------------------------------------------------------
    // Escritura
    // -------------------------------------------------------------------------

    /**
     * Una foto o un texto con música se muestra el tiempo del fragmento (story_song_seconds).
     *
     * @param array{path:string, mime_type:string, type:string}|null $media
     * @param array{id:int, start:int}|null $song de MusicService::resolveForUse()
     */
    public static function create(int $userId, ?array $media, ?string $body, ?string $background, ?array $song = null, array $overlays = [], ?string $filter = null): int
    {
        $type = $media === null ? 'text' : $media['type'];
        $seconds = match (true) {
            $type === 'video' => (int) Config::get('app.uploads.story_video_seconds', 30),
            $song !== null    => (int) Config::get('app.limits.story_song_seconds', 15),
            default           => self::IMAGE_SECONDS,
        };
        self::execute(
            'INSERT INTO stories (user_id, media_type, media_path, mime_type, body, background, overlays, filter, song_id, song_start, duration_seconds, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? SECOND)',
            [$userId, $type, $media['path'] ?? null, $media['mime_type'] ?? null, $body, $media === null ? $background : null,
                $media !== null && $overlays !== [] ? json_encode($overlays, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
                $media !== null ? $filter : null,
                $song['id'] ?? null, $song['start'] ?? null, $seconds, (int) Config::get('app.story_ttl', 86400)]
        );
        $storyId = (int) self::db()->lastInsertId();
        if ($song !== null) {
            Song::incrementUses((int) $song['id']);
        }
        return $storyId;
    }

    /** Capas guardadas en stories.overlays (ya validadas por StoryOverlays al publicar). */
    public static function decodeOverlays(?string $json): array
    {
        if ($json === null || $json === '') {
            return [];
        }
        $items = json_decode($json, true);
        return is_array($items) ? array_values(array_filter($items, static fn ($o): bool => is_array($o) && isset($o['type']))) : [];
    }

    /** Guarda el voto si la persona aún no votó (el voto no se cambia). */
    public static function vote(int $storyId, int $userId, int $choice): void
    {
        self::execute('INSERT IGNORE INTO story_poll_votes (story_id, user_id, choice) VALUES (?, ?, ?)', [$storyId, $userId, $choice]);
    }

    /**
     * Votos de las encuestas de varias historias y la opción de quien mira.
     *
     * @return array<int, array{counts: list<int>, total: int, viewer_choice: ?int}>
     */
    public static function pollResults(array $storyIds, int $viewerId): array
    {
        $storyIds = array_values(array_unique(array_filter(array_map('intval', $storyIds))));
        if ($storyIds === []) {
            return [];
        }
        $out = [];
        foreach ($storyIds as $id) {
            $out[$id] = ['counts' => [0, 0], 'total' => 0, 'viewer_choice' => null];
        }
        $marks = implode(',', array_fill(0, count($storyIds), '?'));
        $rows = self::fetchAll(
            "SELECT story_id, choice, COUNT(*) AS total, MAX(user_id = ?) AS mine FROM story_poll_votes
             WHERE story_id IN ($marks) AND choice IN (0, 1) GROUP BY story_id, choice",
            array_merge([$viewerId], $storyIds)
        );
        foreach ($rows as $r) {
            $id = (int) $r['story_id'];
            $choice = (int) $r['choice'];
            $out[$id]['counts'][$choice] = (int) $r['total'];
            $out[$id]['total'] += (int) $r['total'];
            if ((int) $r['mine'] === 1) {
                $out[$id]['viewer_choice'] = $choice;
            }
        }
        return $out;
    }

    /** Registra la visita una sola vez por persona; quien publica no cuenta. Devuelve true si era nueva. */
    public static function markViewed(array $story, int $viewerId): bool
    {
        if ((int) $story['user_id'] === $viewerId) {
            return false;
        }
        $inserted = self::execute('INSERT IGNORE INTO story_views (story_id, viewer_id) VALUES (?, ?)', [(int) $story['id'], $viewerId]);
        if ($inserted === 1) {
            self::execute('UPDATE stories SET views_count = views_count + 1 WHERE id = ?', [(int) $story['id']]);
        }
        return $inserted === 1;
    }

    public static function delete(array $story): void
    {
        self::execute('DELETE FROM stories WHERE id = ?', [(int) $story['id']]);
        MediaUpload::delete($story['media_path'] ?? null);
    }

    /**
     * Borra las historias caducadas y sus archivos. No hay tareas programadas en el hosting compartido:
     * se llama al publicar y al abrir el visor, por lotes para no alargar la petición.
     */
    public static function purgeExpired(int $limit = 100): int
    {
        $rows = self::fetchAll(
            'SELECT id, media_path FROM stories WHERE expires_at <= NOW() ORDER BY expires_at LIMIT ' . max(1, min(500, $limit))
        );
        if ($rows === []) {
            return 0;
        }
        $ids = array_map(static fn (array $r) => (int) $r['id'], $rows);
        self::execute('DELETE FROM stories WHERE id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')', $ids);
        foreach ($rows as $r) {
            MediaUpload::delete($r['media_path']);
        }
        return count($rows);
    }

    /** Archivos de las historias de una cuenta (para borrarlos al eliminarla). */
    public static function mediaPathsByUser(int $userId): array
    {
        return array_column(self::fetchAll(
            'SELECT media_path FROM stories WHERE user_id = ? AND media_path IS NOT NULL',
            [$userId]
        ), 'media_path');
    }

    /** Antes de borrar una cuenta: descuenta sus visitas de las historias ajenas. */
    public static function releaseViewsForUser(int $userId): void
    {
        self::execute(
            'UPDATE stories s JOIN story_views sv ON sv.story_id = s.id AND sv.viewer_id = ?
             SET s.views_count = GREATEST(CAST(s.views_count AS SIGNED) - 1, 0)',
            [$userId]
        );
    }
}
