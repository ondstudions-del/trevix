<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Listas de reproducción de reels de los creadores de contenido. Los videos se ven en el orden en que se
 * agregaron a la lista (el primero que se agregó va primero).
 */
final class Playlist extends Model
{
    private const COLUMNS = 'pl.id, pl.user_id, pl.title, pl.description, pl.created_at, pl.updated_at,
        u.username, u.display_name, u.avatar_path, u.is_verified, u.is_private,
        (SELECT COUNT(*) FROM playlist_posts pc JOIN posts cp ON cp.id = pc.post_id AND cp.status = \'published\'
            WHERE pc.playlist_id = pl.id) AS items_count,
        (SELECT pm.poster_path FROM playlist_posts pp
            JOIN posts vp ON vp.id = pp.post_id AND vp.status = \'published\'
            JOIN post_media pm ON pm.post_id = pp.post_id AND pm.type = \'video\'
            WHERE pp.playlist_id = pl.id ORDER BY pp.added_at, pp.post_id, pm.position LIMIT 1) AS cover_path';

    public static function find(int $id): ?array
    {
        $row = self::fetchOne(
            'SELECT ' . self::COLUMNS . " FROM playlists pl JOIN users u ON u.id = pl.user_id AND u.status = 'active' WHERE pl.id = ? LIMIT 1",
            [$id]
        );
        return $row !== null ? self::card($row) : null;
    }

    /**
     * Listas de una cuenta, la más reciente primero. Con $postId, cada una indica si ya tiene esa publicación.
     * @return list<array>
     */
    public static function forUser(int $userId, int $postId = 0): array
    {
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ',
                EXISTS (SELECT 1 FROM playlist_posts hp WHERE hp.playlist_id = pl.id AND hp.post_id = ?) AS has_post
             FROM playlists pl JOIN users u ON u.id = pl.user_id
             WHERE pl.user_id = ? ORDER BY pl.created_at DESC, pl.id DESC LIMIT 100',
            [$postId, $userId]
        );
        return array_map(static fn (array $r): array => self::card($r) + ['has_post' => (bool) $r['has_post']], $rows);
    }

    public static function countForUser(int $userId): int
    {
        return (int) self::fetchValue('SELECT COUNT(*) FROM playlists WHERE user_id = ?', [$userId]);
    }

    public static function create(int $userId, string $title, ?string $description): int
    {
        self::execute('INSERT INTO playlists (user_id, title, description) VALUES (?, ?, ?)', [$userId, $title, $description]);
        return (int) self::db()->lastInsertId();
    }

    public static function update(int $id, string $title, ?string $description): void
    {
        self::execute('UPDATE playlists SET title = ?, description = ? WHERE id = ?', [$title, $description, $id]);
    }

    public static function delete(int $id): void
    {
        self::execute('DELETE FROM playlists WHERE id = ?', [$id]);
    }

    public static function itemCount(int $id): int
    {
        return (int) self::fetchValue('SELECT COUNT(*) FROM playlist_posts WHERE playlist_id = ?', [$id]);
    }

    /** Devuelve false si la publicación ya estaba en la lista. */
    public static function addPost(int $id, int $postId): bool
    {
        $added = self::execute('INSERT IGNORE INTO playlist_posts (playlist_id, post_id) VALUES (?, ?)', [$id, $postId]) === 1;
        if ($added) {
            self::execute('UPDATE playlists SET updated_at = NOW() WHERE id = ?', [$id]);
        }
        return $added;
    }

    public static function removePost(int $id, int $postId): bool
    {
        return self::execute('DELETE FROM playlist_posts WHERE playlist_id = ? AND post_id = ?', [$id, $postId]) === 1;
    }

    /** Videos de la lista que el lector puede ver, en el orden en que se agregaron. */
    public static function posts(int $id, int $viewerId, int $page, int $limit): array
    {
        return Post::feed($viewerId, [
            'join'       => 'JOIN playlist_posts lp ON lp.post_id = p.id AND lp.playlist_id = ?',
            'joinParams' => [$id],
            'order'      => 'custom',
            'orderBy'    => 'lp.added_at ASC, p.id ASC',
            'page'       => $page,
            'limit'      => $limit,
        ]);
    }

    private static function card(array $r): array
    {
        return [
            'id'          => (int) $r['id'],
            'user_id'     => (int) $r['user_id'],
            'title'       => $r['title'],
            'description' => (string) ($r['description'] ?? ''),
            'items_count' => (int) $r['items_count'],
            'cover_path'  => $r['cover_path'],
            'created_at'  => $r['created_at'],
            'updated_at'  => $r['updated_at'],
            'user'        => [
                'id'           => (int) $r['user_id'],
                'username'     => $r['username'],
                'display_name' => $r['display_name'],
                'avatar_path'  => $r['avatar_path'],
                'is_verified'  => (bool) $r['is_verified'],
                'is_private'   => (bool) $r['is_private'],
            ],
        ];
    }
}
