<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Config;

/**
 * Hashtags extraídos del texto de las publicaciones. La columna tag usa una intercalación que no
 * distingue mayúsculas ni tildes, así #Diseño y #diseno cuentan como la misma etiqueta.
 */
final class Hashtag extends Model
{
    /** Mismo patrón que format_post_body() usa para enlazar etiquetas. */
    private const PATTERN = '~(?<![\w&])#([\p{L}\p{N}_]{1,50})~u';

    /** @return list<string> etiquetas únicas (sin #) en orden de aparición. */
    public static function extract(string $text): array
    {
        if (!preg_match_all(self::PATTERN, $text, $m)) {
            return [];
        }
        $tags = [];
        foreach ($m[1] as $tag) {
            $key = mb_strtolower($tag);
            $tags[$key] ??= $tag;
        }
        return array_slice(array_values($tags), 0, (int) Config::get('app.limits.hashtags_per_post', 10));
    }

    /** Sincroniza las etiquetas de una publicación con su texto actual y mantiene posts_count. */
    public static function sync(int $postId, string $body): void
    {
        $current = [];
        foreach (self::fetchAll(
            'SELECT h.id, h.tag FROM post_hashtags ph JOIN hashtags h ON h.id = ph.hashtag_id WHERE ph.post_id = ?',
            [$postId]
        ) as $row) {
            $current[(int) $row['id']] = $row['tag'];
        }

        $wanted = [];
        foreach (self::extract($body) as $tag) {
            self::execute(
                'INSERT INTO hashtags (tag, posts_count, last_used_at) VALUES (?, 0, NOW())
                 ON DUPLICATE KEY UPDATE last_used_at = NOW(), id = LAST_INSERT_ID(id)',
                [$tag]
            );
            $wanted[(int) self::db()->lastInsertId()] = true;
        }

        foreach (array_diff_key($wanted, $current) as $id => $_) {
            if (self::execute('INSERT IGNORE INTO post_hashtags (post_id, hashtag_id) VALUES (?, ?)', [$postId, $id]) === 1) {
                self::execute('UPDATE hashtags SET posts_count = posts_count + 1 WHERE id = ?', [$id]);
            }
        }
        foreach (array_diff_key($current, $wanted) as $id => $_) {
            self::detach($postId, $id);
        }
    }

    public static function detachAll(int $postId): void
    {
        foreach (self::fetchAll('SELECT hashtag_id FROM post_hashtags WHERE post_id = ?', [$postId]) as $row) {
            self::detach($postId, (int) $row['hashtag_id']);
        }
    }

    /**
     * Etiquetas con más publicaciones públicas en los últimos días.
     * @return list<array{tag:string, category:string, posts_count:int}>
     */
    public static function trending(int $limit = 5, int $days = 7): array
    {
        $rows = self::fetchAll(
            "SELECT h.tag, COUNT(*) AS recent
             FROM post_hashtags ph
             JOIN hashtags h ON h.id = ph.hashtag_id
             JOIN posts p ON p.id = ph.post_id AND p.status = 'published' AND p.visibility = 'public'
             JOIN users u ON u.id = p.user_id AND u.status = 'active' AND u.is_private = 0
             WHERE ph.created_at > (NOW() - INTERVAL " . max(1, $days) . ' DAY)
             GROUP BY h.id, h.tag
             ORDER BY recent DESC, MAX(ph.created_at) DESC
             LIMIT ' . max(1, min(50, $limit))
        );
        return array_map(static fn (array $r) => [
            'tag'         => $r['tag'],
            'category'    => 'Tendencia · últimos ' . $days . ' días',
            'posts_count' => (int) $r['recent'],
        ], $rows);
    }

    /** Etiquetas en uso que empiezan por $term. */
    public static function search(string $term, int $limit = 20): array
    {
        $like = addcslashes($term, '%_\\') . '%';
        $rows = self::fetchAll(
            'SELECT tag, posts_count FROM hashtags WHERE tag LIKE ? AND posts_count > 0
             ORDER BY posts_count DESC, last_used_at DESC LIMIT ' . max(1, min(50, $limit)),
            [$like]
        );
        return array_map(static fn (array $r) => [
            'tag'         => $r['tag'],
            'category'    => 'Hashtag',
            'posts_count' => (int) $r['posts_count'],
        ], $rows);
    }

    /** Etiqueta exacta (según la intercalación) o null. */
    public static function find(string $tag): ?array
    {
        return self::fetchOne('SELECT id, tag, posts_count FROM hashtags WHERE tag = ? LIMIT 1', [$tag]);
    }

    private static function detach(int $postId, int $hashtagId): void
    {
        if (self::execute('DELETE FROM post_hashtags WHERE post_id = ? AND hashtag_id = ?', [$postId, $hashtagId]) === 1) {
            self::execute('UPDATE hashtags SET posts_count = posts_count - (posts_count > 0) WHERE id = ?', [$hashtagId]);
        }
    }
}
