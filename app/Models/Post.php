<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;
use Trevix\Services\MediaUpload;

/**
 * Publicaciones y feeds. Toda lectura pasa por visibleTo(): una publicación solo se muestra si está
 * publicada, su autor está activo, no hay bloqueo entre ambos y la visibilidad (pública, seguidores,
 * solo yo) y la privacidad de la cuenta lo permiten.
 */
final class Post extends Model
{
    public const FORMATS = ['post', 'thread'];
    public const VISIBILITIES = ['public' => 'Público', 'followers' => 'Seguidores', 'private' => 'Solo yo', 'subscribers' => 'Suscriptores'];

    /** Acontecimientos importantes: etiqueta e icono (assets/icons). */
    public const LIFE_EVENTS = [
        'job'          => ['Nuevo trabajo', 'briefcase'],
        'graduation'   => ['Graduación', 'graduation-cap'],
        'move'         => ['Mudanza a una nueva ciudad', 'house'],
        'relationship' => ['Nueva relación', 'heart'],
        'family'       => ['Nuevo miembro en la familia', 'users'],
        'travel'       => ['Viaje', 'map-pin'],
        'achievement'  => ['Logro personal', 'trophy'],
        'project'      => ['Nuevo proyecto', 'rocket'],
        'birthday'     => ['Cumpleaños', 'cake'],
        'other'        => ['Acontecimiento importante', 'star'],
    ];

    private const SELECT = 'SELECT p.id, p.user_id, p.community_id, p.shared_post_id, p.song_id, p.song_start, p.format, p.body, p.visibility, p.is_edited,
            p.background, p.life_event, p.location_name, p.location_lat, p.location_lng, p.event_id, p.featured_at,
            p.gif_id, p.gif_kind, p.gif_url, p.gif_width, p.gif_height, p.gif_title,
            p.created_at, p.likes_count, p.comments_count, p.shares_count, p.saves_count,
            u.username, u.display_name, u.avatar_path, u.is_verified, u.is_private,
            c.slug AS community_slug, c.name AS community_name, c.visibility AS community_visibility,
            EXISTS (SELECT 1 FROM likes l WHERE l.user_id = ? AND l.post_id = p.id) AS viewer_liked,
            EXISTS (SELECT 1 FROM saved_posts sp WHERE sp.user_id = ? AND sp.post_id = p.id) AS viewer_saved,
            EXISTS (SELECT 1 FROM follows vf WHERE vf.follower_id = ? AND vf.following_id = p.user_id) AS viewer_follows
        FROM posts p
        JOIN users u ON u.id = p.user_id
        LEFT JOIN communities c ON c.id = p.community_id';

    /**
     * Condición SQL de visibilidad para el usuario $viewerId (alias p = posts, u = users, c = communities).
     * Las publicaciones de una comunidad siguen las reglas de la comunidad (activa y pública, o el lector
     * es miembro activo) en lugar de la visibilidad y privacidad de la cuenta del autor.
     * Las de «Suscriptores» solo las ve quien tiene una suscripción vigente al autor (aunque la cuenta sea privada).
     */
    private static function visibleTo(int $viewerId): array
    {
        $sql = "p.status = 'published' AND u.status = 'active' AND (p.user_id = ? OR (
                NOT EXISTS (SELECT 1 FROM blocks b
                    WHERE (b.blocker_id = ? AND b.blocked_id = p.user_id) OR (b.blocker_id = p.user_id AND b.blocked_id = ?))
                AND (
                    (p.community_id IS NULL
                        AND (p.visibility = 'public' OR (p.visibility = 'followers'
                            AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = p.user_id)))
                        AND (u.is_private = 0
                            OR EXISTS (SELECT 1 FROM follows f2 WHERE f2.follower_id = ? AND f2.following_id = p.user_id)))
                    OR (p.community_id IS NULL AND p.visibility = 'subscribers'
                        AND EXISTS (SELECT 1 FROM collaborator_subscriptions cs
                            WHERE cs.collaborator_id = p.user_id AND cs.subscriber_id = ? AND cs.expires_at > NOW()))
                    OR (p.community_id IS NOT NULL AND c.status = 'active'
                        AND (c.visibility = 'public' OR EXISTS (SELECT 1 FROM community_members cm
                            WHERE cm.community_id = p.community_id AND cm.user_id = ? AND cm.status = 'active')))
                )
            ))";
        return [$sql, array_fill(0, 7, $viewerId)];
    }

    /**
     * Registra que $viewerId vio estas publicaciones (una vez por persona; las propias no cuentan). Se usa al
     * entregar un feed o el detalle de una publicación.
     */
    public static function recordViews(array $postIds, int $viewerId): void
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $postIds))));
        if ($viewerId < 1 || $ids === []) {
            return;
        }
        $marks = implode(',', array_fill(0, count($ids), '?'));
        self::execute(
            "INSERT IGNORE INTO post_views (post_id, user_id)
             SELECT id, ? FROM posts WHERE id IN ($marks) AND user_id <> ?",
            array_merge([$viewerId], $ids, [$viewerId])
        );
    }

    // -------------------------------------------------------------------------
    // Lectura
    // -------------------------------------------------------------------------

    /** Publicación visible para el usuario, ya preparada para la vista. */
    public static function findVisible(int $id, int $viewerId): ?array
    {
        $posts = self::byIds([$id], $viewerId);
        return $posts[$id] ?? null;
    }

    /** Fila cruda (sin filtros de visibilidad) para comprobaciones de propiedad. */
    public static function findRaw(int $id): ?array
    {
        return self::fetchOne(
            'SELECT id, user_id, community_id, shared_post_id, song_id, event_id, format, body, visibility, status, featured_at FROM posts WHERE id = ? LIMIT 1',
            [$id]
        );
    }

    /**
     * Consulta paginada de un feed.
     *
     * @param array{where?:string, params?:array, join?:string, joinParams?:array, order?:string, orderBy?:string, before?:int, page?:int, limit?:int} $q
     *   order: 'recent' (cursor por id) | 'score' (popularidad, paginación por página)
     *          | 'saved' (fecha de guardado, por página; requiere un join con alias "saved")
     *          | 'featured' (destacadas, la más reciente primero) | 'custom' (orderBy fijo del código, nunca del usuario).
     * @return array{posts: list<array>, next: ?array} next = parámetros GET para la siguiente página.
     */
    public static function feed(int $viewerId, array $q = []): array
    {
        [$visSql, $visParams] = self::visibleTo($viewerId);
        $limit = max(1, min(50, (int) ($q['limit'] ?? 15)));
        $order = $q['order'] ?? 'recent';

        $sql = self::SELECT . ' ' . ($q['join'] ?? '') . ' WHERE ' . $visSql;
        $params = array_merge([$viewerId, $viewerId, $viewerId], $q['joinParams'] ?? [], $visParams);

        if (!empty($q['where'])) {
            $sql .= ' AND (' . $q['where'] . ')';
            $params = array_merge($params, $q['params'] ?? []);
        }

        $page = max(1, (int) ($q['page'] ?? 1));
        if ($order === 'recent') {
            $before = (int) ($q['before'] ?? 0);
            if ($before > 0) {
                $sql .= ' AND p.id < ?';
                $params[] = $before;
            }
            $sql .= ' ORDER BY p.id DESC LIMIT ' . ($limit + 1);
        } else {
            $sql .= match ($order) {
                'saved'    => ' ORDER BY saved.created_at DESC, p.id DESC',
                'featured' => ' ORDER BY p.featured_at DESC, p.id DESC',
                'custom'   => ' ORDER BY ' . $q['orderBy'],
                default    => ' ORDER BY (p.likes_count * 2 + p.comments_count * 3 + p.shares_count * 4 + p.saves_count) DESC, p.id DESC',
            };
            $sql .= ' LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit);
        }

        $rows = self::fetchAll($sql, $params);
        $hasMore = count($rows) > $limit;
        $rows = array_slice($rows, 0, $limit);
        $posts = self::hydrate($rows, $viewerId);
        self::recordViews(array_column($posts, 'id'), $viewerId);

        $next = null;
        if ($hasMore && $rows !== []) {
            $next = $order === 'recent' ? ['before' => (int) end($rows)['id']] : ['page' => $page + 1];
        }
        return ['posts' => $posts, 'next' => $next];
    }

    /** Guardados del usuario, del más reciente al más antiguo (solo los que aún puede ver). */
    public static function saved(int $userId, int $page, int $limit): array
    {
        return self::feed($userId, [
            'join'       => 'JOIN saved_posts saved ON saved.post_id = p.id AND saved.user_id = ?',
            'joinParams' => [$userId],
            'order'      => 'saved',
            'page'       => $page,
            'limit'      => $limit,
        ]);
    }

    /**
     * Búsqueda de publicaciones por texto (FULLTEXT; con LIKE si solo hay palabras muy cortas),
     * de la más reciente a la más antigua y con las mismas reglas de visibilidad que el feed.
     */
    public static function search(int $viewerId, string $term, array $paging): array
    {
        $boolean = self::booleanSearch($term);
        $condition = $boolean !== ''
            ? ['where' => 'MATCH (p.body) AGAINST (? IN BOOLEAN MODE)', 'params' => [$boolean]]
            : ['where' => 'p.body LIKE ?', 'params' => ['%' . self::likeEscape(trim($term)) . '%']];
        return self::feed($viewerId, $condition + $paging);
    }

    /** Publicaciones con imágenes recientes y públicas (sección "Descubre" de Explorar). */
    public static function recentMedia(int $viewerId, int $limit = 12): array
    {
        return self::feed($viewerId, [
            'where'  => "p.visibility = 'public' AND EXISTS (SELECT 1 FROM post_media pm WHERE pm.post_id = p.id AND pm.type = 'image')",
            'limit'  => $limit,
        ])['posts'];
    }

    /**
     * Reels: todas las publicaciones con video que puede ver el usuario, mezcladas por interacción, frescura y
     * cuentas que sigue, con una variación propia de cada sesión ($seed) para que el orden no se repita.
     * El orden es estable para un mismo $seed, así la paginación no repite ni salta videos.
     */
    public static function reels(int $viewerId, int $seed, int $page, int $limit, int $excludeId = 0): array
    {
        $viewer = (int) $viewerId;
        $seed = abs($seed) % 1000000;
        $order = "((p.likes_count * 2 + p.comments_count * 3 + p.shares_count * 4 + p.saves_count + 3)
                / POW(TIMESTAMPDIFF(HOUR, p.created_at, NOW()) + 6, 0.8)
                * (1 + 0.6 * EXISTS (SELECT 1 FROM follows rf WHERE rf.follower_id = $viewer AND rf.following_id = p.user_id))
                * (0.4 + CRC32(CONCAT(p.id, ':', $seed)) / 4294967295 * 1.2)) DESC, p.id DESC";
        return self::feed($viewerId, [
            'where'   => "EXISTS (SELECT 1 FROM post_media pm WHERE pm.post_id = p.id AND pm.type = 'video') AND p.id <> ?",
            'params'  => [$excludeId],
            'order'   => 'custom',
            'orderBy' => $order,
            'page'    => $page,
            'limit'   => $limit,
        ]);
    }

    /** @return array<int, array> publicaciones visibles indexadas por id. */
    private static function byIds(array $ids, int $viewerId, bool $withShared = true): array
    {
        $ids = array_values(array_unique(array_map('intval', $ids)));
        if ($ids === []) {
            return [];
        }
        [$visSql, $visParams] = self::visibleTo($viewerId);
        $marks = implode(',', array_fill(0, count($ids), '?'));
        $rows = self::fetchAll(
            self::SELECT . " WHERE p.id IN ($marks) AND " . $visSql,
            array_merge([$viewerId, $viewerId, $viewerId], $ids, $visParams)
        );

        $out = [];
        foreach (self::hydrate($rows, $viewerId, $withShared) as $post) {
            $out[$post['id']] = $post;
        }
        return $out;
    }

    /** Convierte filas SQL en el formato que usan las tarjetas: autor, adjuntos y publicación compartida. */
    private static function hydrate(array $rows, int $viewerId, bool $withShared = true): array
    {
        if ($rows === []) {
            return [];
        }
        $ids = array_map(static fn (array $r) => (int) $r['id'], $rows);
        $media = self::mediaFor($ids);
        $songs = Song::cardsFor(array_column($rows, 'song_id'));
        $events = Event::cardsFor(array_column($rows, 'event_id'), $viewerId);

        $shared = [];
        if ($withShared) {
            $sharedIds = array_filter(array_map(static fn (array $r) => (int) $r['shared_post_id'], $rows));
            $shared = self::byIds($sharedIds, $viewerId, false);
        }

        $posts = [];
        foreach ($rows as $r) {
            $id = (int) $r['id'];
            $sharedId = (int) $r['shared_post_id'];
            $postMedia = $media[$id] ?? [];
            // song_start se conserva aunque la canción se elimine (song_id pasa a NULL): así una publicación
            // que solo tenía música no se confunde con un compartido cuyo original desapareció.
            $hadSong = $r['song_start'] !== null;
            $ownContent = $r['body'] !== null || $postMedia !== [] || $hadSong || $r['gif_url'] !== null
                || $r['event_id'] !== null || $r['life_event'] !== null;
            $isRepost = $sharedId > 0 || !$ownContent;
            $lifeEvent = self::LIFE_EVENTS[$r['life_event'] ?? ''] ?? null;
            $songId = (int) $r['song_id'];
            $song = $hadSong ? ($songs[$songId] ?? Song::unavailable($songId)) + ['start' => (int) $r['song_start']] : null;

            $posts[] = [
                'id'             => $id,
                'user_id'        => (int) $r['user_id'],
                'user'           => [
                    'id'           => (int) $r['user_id'],
                    'username'     => $r['username'],
                    'display_name' => $r['display_name'],
                    'avatar_path'  => $r['avatar_path'],
                    'is_verified'  => (bool) $r['is_verified'],
                    'is_private'   => (bool) $r['is_private'],
                    'viewer_follows' => (bool) $r['viewer_follows'],
                ],
                'format'         => $r['format'],
                'background'     => $r['format'] === 'thread' ? $r['background'] : null,
                'body'           => (string) ($r['body'] ?? ''),
                'life_event'     => $lifeEvent !== null ? ['key' => $r['life_event'], 'label' => $lifeEvent[0], 'icon' => $lifeEvent[1]] : null,
                'location'       => $r['location_name'] !== null ? [
                    'name' => $r['location_name'],
                    'lat'  => $r['location_lat'] !== null ? (float) $r['location_lat'] : null,
                    'lng'  => $r['location_lng'] !== null ? (float) $r['location_lng'] : null,
                ] : null,
                'gif'            => \Trevix\Services\Giphy::fromRow($r),
                'event'          => $events[(int) $r['event_id']] ?? null,
                'featured'       => $r['featured_at'] !== null,
                'visibility'     => $r['visibility'],
                'created_at'     => $r['created_at'],
                'is_edited'      => (bool) $r['is_edited'],
                'community'      => $r['community_slug'] ? [
                    'id'         => (int) $r['community_id'],
                    'slug'       => $r['community_slug'],
                    'name'       => $r['community_name'],
                    'visibility' => $r['community_visibility'],
                ] : null,
                'media'          => $postMedia,
                'song'           => $song,
                'shared'         => $shared[$sharedId] ?? null,
                'shared_missing' => $isRepost && !isset($shared[$sharedId]),
                'likes_count'    => (int) $r['likes_count'],
                'comments_count' => (int) $r['comments_count'],
                'shares_count'   => (int) $r['shares_count'],
                'saves_count'    => (int) $r['saves_count'],
                'viewer_liked'   => (bool) $r['viewer_liked'],
                'viewer_saved'   => (bool) $r['viewer_saved'],
                'replies'        => [],
            ];
        }
        return $posts;
    }

    /** @return array<int, list<array{type:string,src:string,alt:string}>> */
    private static function mediaFor(array $postIds): array
    {
        $marks = implode(',', array_fill(0, count($postIds), '?'));
        $rows = self::fetchAll(
            "SELECT post_id, type, path, poster_path, alt_text, width, height, duration_seconds
             FROM post_media WHERE post_id IN ($marks) ORDER BY post_id, position",
            $postIds
        );
        $out = [];
        foreach ($rows as $m) {
            $out[(int) $m['post_id']][] = [
                'type'     => $m['type'],
                'src'      => $m['path'],
                'poster'   => $m['poster_path'],
                'alt'      => (string) ($m['alt_text'] ?? ''),
                'width'    => $m['width'] !== null ? (int) $m['width'] : null,
                'height'   => $m['height'] !== null ? (int) $m['height'] : null,
                'duration' => $m['duration_seconds'] !== null ? (int) $m['duration_seconds'] : null,
            ];
        }
        return $out;
    }

    // -------------------------------------------------------------------------
    // Escritura
    // -------------------------------------------------------------------------

    /**
     * Crea la publicación con sus adjuntos y hashtags en una transacción.
     * $media es el resultado de MediaUpload::storeAll(); $song, el de MusicService::resolveForUse().
     * $extras (ya validados por PostService): background, life_event, location (name, lat, lng), gif (columnas gif_*), event_id.
     */
    public static function create(
        int $userId,
        string $format,
        ?string $body,
        string $visibility,
        array $media,
        ?int $sharedPostId,
        ?int $communityId = null,
        ?array $song = null,
        array $extras = []
    ): int {
        return (int) Database::transaction(static function () use ($userId, $format, $body, $visibility, $media, $sharedPostId, $communityId, $song, $extras): int {
            $gif = $extras['gif'] ?? null;
            $location = $extras['location'] ?? null;
            self::execute(
                'INSERT INTO posts (user_id, community_id, shared_post_id, song_id, song_start, event_id, format, background, life_event, body,
                                    location_name, location_lat, location_lng, gif_id, gif_kind, gif_url, gif_width, gif_height, gif_title, visibility)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [
                    $userId, $communityId, $sharedPostId, $song['id'] ?? null, $song['start'] ?? null, $extras['event_id'] ?? null,
                    $format, $extras['background'] ?? null, $extras['life_event'] ?? null, $body,
                    $location['name'] ?? null, $location['lat'] ?? null, $location['lng'] ?? null,
                    $gif['gif_id'] ?? null, $gif['gif_kind'] ?? null, $gif['gif_url'] ?? null,
                    $gif['gif_width'] ?? null, $gif['gif_height'] ?? null, $gif['gif_title'] ?? null,
                    $visibility,
                ]
            );
            $postId = (int) self::db()->lastInsertId();
            if ($song !== null) {
                Song::incrementUses((int) $song['id']);
            }
            if ($communityId !== null) {
                self::execute('UPDATE communities SET posts_count = posts_count + 1 WHERE id = ?', [$communityId]);
            }

            foreach (array_values($media) as $position => $m) {
                self::execute(
                    'INSERT INTO post_media (post_id, type, path, poster_path, mime_type, size_bytes, width, height, duration_seconds, position)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    [
                        $postId, $m['type'], $m['path'], $m['poster_path'] ?? null, $m['mime_type'], $m['size_bytes'],
                        $m['width'], $m['height'], $m['duration_seconds'] ?? null, $position,
                    ]
                );
            }

            Hashtag::sync($postId, (string) $body);
            self::execute('UPDATE users SET posts_count = posts_count + 1 WHERE id = ?', [$userId]);
            if ($sharedPostId !== null) {
                self::execute('UPDATE posts SET shares_count = shares_count + 1 WHERE id = ?', [$sharedPostId]);
            }
            return $postId;
        });
    }

    /**
     * Edita texto y visibilidad. Con $songChanged también reemplaza la canción ($song null = quitarla);
     * $newSongUse indica que es una canción distinta de la anterior y suma un uso.
     */
    public static function update(int $postId, ?string $body, string $visibility, bool $songChanged = false, ?array $song = null, bool $newSongUse = false): void
    {
        Database::transaction(static function () use ($postId, $body, $visibility, $songChanged, $song, $newSongUse): void {
            self::execute(
                'UPDATE posts SET body = ?, visibility = ?, is_edited = 1, edited_at = NOW() WHERE id = ?',
                [$body, $visibility, $postId]
            );
            if ($songChanged) {
                self::execute('UPDATE posts SET song_id = ?, song_start = ? WHERE id = ?', [$song['id'] ?? null, $song['start'] ?? null, $postId]);
                if ($song !== null && $newSongUse) {
                    Song::incrementUses((int) $song['id']);
                }
            }
            Hashtag::sync($postId, (string) $body);
        });
    }

    /** Borra la publicación, ajusta contadores y elimina sus archivos del disco. */
    public static function delete(array $post): void
    {
        $postId = (int) $post['id'];
        $paths = [];
        foreach (self::fetchAll('SELECT path, poster_path FROM post_media WHERE post_id = ?', [$postId]) as $row) {
            $paths[] = $row['path'];
            $paths[] = $row['poster_path'];
        }

        // Una publicación oculta por moderación ya se descontó de los contadores al ocultarla.
        $counted = ($post['status'] ?? 'published') === 'published';

        Database::transaction(static function () use ($post, $postId, $counted): void {
            Hashtag::detachAll($postId);
            if (!empty($post['shared_post_id'])) {
                self::execute('UPDATE posts SET shares_count = shares_count - (shares_count > 0) WHERE id = ?', [(int) $post['shared_post_id']]);
            }
            if ($counted && !empty($post['community_id'])) {
                self::execute('UPDATE communities SET posts_count = posts_count - (posts_count > 0) WHERE id = ?', [(int) $post['community_id']]);
            }
            if ($counted) {
                self::execute('UPDATE users SET posts_count = posts_count - (posts_count > 0) WHERE id = ?', [(int) $post['user_id']]);
            }
            self::execute('DELETE FROM posts WHERE id = ?', [$postId]);
        });

        foreach ($paths as $path) {
            MediaUpload::delete($path);
        }
        // Un evento vive con su publicación: al borrarla se borran el evento, sus respuestas y la portada.
        if (!empty($post['event_id'])) {
            \Trevix\Services\ImageUpload::delete(Event::delete((int) $post['event_id']));
        }
    }

    /** Destaca (o deja de destacar) una publicación. Devuelve true si cambió. */
    public static function setFeatured(int $postId, ?int $adminId): bool
    {
        return $adminId !== null
            ? self::execute("UPDATE posts SET featured_at = NOW(), featured_by = ? WHERE id = ? AND featured_at IS NULL AND status = 'published'", [$adminId, $postId]) > 0
            : self::execute('UPDATE posts SET featured_at = NULL, featured_by = NULL WHERE id = ? AND featured_at IS NOT NULL', [$postId]) > 0;
    }

    /** Destacadas visibles para quien mira (arriba del inicio y sección Destacados de Explorar). */
    public static function featured(int $viewerId, int $page = 1, int $limit = 3): array
    {
        return self::feed($viewerId, [
            'where' => "p.featured_at IS NOT NULL AND p.visibility = 'public' AND (p.community_id IS NULL OR c.visibility = 'public')",
            'order' => 'featured',
            'page'  => $page,
            'limit' => $limit,
        ]);
    }

    /**
     * Moderación: oculta (published → hidden) o restaura (hidden → published) una publicación.
     * Mientras está oculta no cuenta en las publicaciones de su autor ni de su comunidad.
     */
    public static function setModerationStatus(array $post, string $status): bool
    {
        $from = $status === 'hidden' ? 'published' : 'hidden';
        $delta = $status === 'hidden' ? '- (posts_count > 0)' : '+ 1';
        return Database::transaction(static function () use ($post, $status, $from, $delta): bool {
            $changed = self::execute('UPDATE posts SET status = ? WHERE id = ? AND status = ?', [$status, (int) $post['id'], $from]);
            if ($changed === 0) {
                return false;
            }
            self::execute("UPDATE users SET posts_count = posts_count $delta WHERE id = ?", [(int) $post['user_id']]);
            if (!empty($post['community_id'])) {
                self::execute("UPDATE communities SET posts_count = posts_count $delta WHERE id = ?", [(int) $post['community_id']]);
            }
            return true;
        });
    }

    /**
     * Listado del panel: publicaciones por estado, texto o autor (@usuario), de la más reciente a la más antigua.
     * @return array{posts: list<array>, hasMore: bool}
     */
    public static function adminList(string $term, ?string $status, int $page, int $limit): array
    {
        $where = ["p.status <> 'removed'"];
        $params = [];
        $term = trim($term);
        if (str_starts_with($term, '@')) {
            $where[] = 'u.username = ?';
            $params[] = mb_strtolower(substr($term, 1));
        } elseif ($term !== '') {
            $where[] = 'p.body LIKE ?';
            $params[] = '%' . self::likeEscape($term) . '%';
        }
        if ($status === 'featured') {
            $where[] = "p.featured_at IS NOT NULL AND p.status = 'published'";
        } elseif ($status !== null) {
            $where[] = 'p.status = ?';
            $params[] = $status;
        }
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            "SELECT p.id, p.user_id, p.community_id, p.shared_post_id, p.format, p.body, p.visibility, p.status, p.created_at,
                    p.likes_count, p.comments_count, p.gif_url, p.gif_kind, p.featured_at,
                    u.username, u.display_name, u.avatar_path, u.role AS author_role,
                    c.name AS community_name, c.slug AS community_slug, c.visibility AS community_visibility,
                    (SELECT COUNT(*) FROM post_media pm WHERE pm.post_id = p.id) AS media_count,
                    (SELECT COUNT(*) FROM reports r WHERE r.target_type = 'post' AND r.target_id = p.id AND r.status IN ('open', 'reviewing')) AS open_reports
             FROM posts p JOIN users u ON u.id = p.user_id LEFT JOIN communities c ON c.id = p.community_id
             WHERE " . implode(' AND ', $where) . '
             ORDER BY p.id DESC LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return ['posts' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Rutas de todos los adjuntos de un usuario (para limpiar el disco al eliminar la cuenta). */
    public static function mediaPathsByUser(int $userId): array
    {
        $paths = [];
        foreach (self::fetchAll('SELECT pm.path, pm.poster_path FROM post_media pm JOIN posts p ON p.id = pm.post_id WHERE p.user_id = ?', [$userId]) as $row) {
            $paths[] = $row['path'];
            if ($row['poster_path'] !== null) {
                $paths[] = $row['poster_path'];
            }
        }
        return $paths;
    }

    /**
     * Antes de borrar una cuenta: descuenta de los contadores ajenos todo lo que se eliminará en cascada
     * (hashtags, compartidos, me gusta, guardados, comentarios y respuestas).
     */
    public static function releaseCountersForUser(int $userId): void
    {
        foreach (['likes' => 'likes_count', 'saved_posts' => 'saves_count'] as $table => $column) {
            self::execute(
                "UPDATE posts t JOIN (SELECT post_id AS id, COUNT(*) AS n FROM $table WHERE user_id = ? GROUP BY post_id) x ON x.id = t.id
                 SET t.$column = GREATEST(CAST(t.$column AS SIGNED) - x.n, 0)",
                [$userId]
            );
        }
        self::execute(
            'UPDATE posts t JOIN (
                SELECT c.post_id AS id, COUNT(*) AS n FROM comments c
                LEFT JOIN comments parent ON parent.id = c.parent_id
                WHERE c.user_id = ? OR parent.user_id = ? GROUP BY c.post_id
             ) x ON x.id = t.id
             SET t.comments_count = GREATEST(CAST(t.comments_count AS SIGNED) - x.n, 0)',
            [$userId, $userId]
        );
        self::execute(
            'UPDATE comments t JOIN (
                SELECT parent_id AS id, COUNT(*) AS n FROM comments WHERE user_id = ? AND parent_id IS NOT NULL GROUP BY parent_id
             ) x ON x.id = t.id
             SET t.replies_count = GREATEST(CAST(t.replies_count AS SIGNED) - x.n, 0)',
            [$userId]
        );
        self::execute(
            'UPDATE hashtags h JOIN (
                SELECT ph.hashtag_id, COUNT(*) AS n FROM post_hashtags ph JOIN posts p ON p.id = ph.post_id
                WHERE p.user_id = ? GROUP BY ph.hashtag_id
             ) x ON x.hashtag_id = h.id
             SET h.posts_count = GREATEST(CAST(h.posts_count AS SIGNED) - x.n, 0)',
            [$userId]
        );
        self::execute(
            'UPDATE posts t JOIN (
                SELECT shared_post_id AS id, COUNT(*) AS n FROM posts WHERE user_id = ? AND shared_post_id IS NOT NULL GROUP BY shared_post_id
             ) x ON x.id = t.id
             SET t.shares_count = GREATEST(CAST(t.shares_count AS SIGNED) - x.n, 0)',
            [$userId]
        );
    }
}
