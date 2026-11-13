<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Temas de las publicaciones (los pone la IA: «fútbol», «cocina», «memes»…), los intereses de cada persona por tema
 * y la predicción de la IA de lo que le gustará. Ordenan «Para ti» y los reels junto con los hashtags.
 */
final class Topic extends Model
{
    public const MAX_PER_POST = 5;
    public const NAME_MAX = 40;

    /** Nombre normalizado (minúsculas, sin # ni signos, espacios simples); '' si no sirve. */
    public static function normalize(string $name): string
    {
        $name = mb_strtolower(trim($name));
        $name = (string) preg_replace('/[^\p{L}\p{N} ]+/u', ' ', $name);
        $name = trim((string) preg_replace('/\s+/u', ' ', $name));
        return mb_strlen($name) >= 2 && mb_strlen($name) <= self::NAME_MAX ? $name : '';
    }

    /** Reemplaza los temas de la publicación. */
    public static function sync(int $postId, array $names): void
    {
        $wanted = [];
        foreach ($names as $name) {
            $name = self::normalize((string) $name);
            if ($name !== '' && count($wanted) < self::MAX_PER_POST) {
                $wanted[$name] = true;
            }
        }
        Database::transaction(static function () use ($postId, $wanted): void {
            $old = array_map('intval', array_column(self::fetchAll('SELECT topic_id FROM post_topics WHERE post_id = ?', [$postId]), 'topic_id'));
            if ($old !== []) {
                self::execute('DELETE FROM post_topics WHERE post_id = ?', [$postId]);
                $marks = implode(',', array_fill(0, count($old), '?'));
                self::execute("UPDATE topics SET posts_count = posts_count - (posts_count > 0) WHERE id IN ($marks)", $old);
            }
            foreach (array_keys($wanted) as $name) {
                self::execute(
                    'INSERT INTO topics (name) VALUES (?) ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)',
                    [$name]
                );
                $id = (int) self::db()->lastInsertId();
                if (self::execute('INSERT IGNORE INTO post_topics (post_id, topic_id) VALUES (?, ?)', [$postId, $id]) === 1) {
                    self::execute('UPDATE topics SET posts_count = posts_count + 1 WHERE id = ?', [$id]);
                }
            }
        });
    }

    /**
     * Temas y hashtags con más (o menos) puntos de la persona, ya enfriados por día.
     * @return list<string>
     */
    public static function userTop(int $userId, string $table, bool $liked, int $limit): array
    {
        [$join, $name, $key] = $table === 'hashtags'
            ? ['hashtag_interests i JOIN hashtags t ON t.id = i.hashtag_id', 't.tag', 'hashtag_id']
            : ['topic_interests i JOIN topics t ON t.id = i.topic_id', 't.name', 'topic_id'];
        $score = 'i.score * POW(' . \Trevix\Services\InterestService::DECAY . ', DATEDIFF(NOW(), i.updated_at))';
        return array_column(self::fetchAll(
            "SELECT $name AS name FROM $join WHERE i.user_id = ? AND i.score " . ($liked ? '> 1' : '< -1') . "
             ORDER BY $score " . ($liked ? 'DESC' : 'ASC') . ' LIMIT ' . max(1, $limit),
            [$userId]
        ), 'name');
    }

    /**
     * Temas de las publicaciones de los últimos días, de los más usados a los menos.
     * @return array<string, int> nombre => id
     */
    public static function recentPopular(int $days, int $limit): array
    {
        $out = [];
        foreach (self::fetchAll(
            "SELECT t.id, t.name, COUNT(*) AS n FROM post_topics pt
             JOIN topics t ON t.id = pt.topic_id
             JOIN posts p ON p.id = pt.post_id AND p.status = 'published'
             WHERE pt.created_at > NOW() - INTERVAL " . max(1, $days) . ' DAY
             GROUP BY t.id, t.name ORDER BY n DESC LIMIT ' . max(1, $limit)
        ) as $row) {
            $out[$row['name']] = (int) $row['id'];
        }
        return $out;
    }

    /** @param array<int, float> $weights id del tema => peso de -1 a 1 */
    public static function savePredictions(int $userId, array $weights): void
    {
        Database::transaction(static function () use ($userId, $weights): void {
            self::execute('DELETE FROM topic_predictions WHERE user_id = ?', [$userId]);
            foreach ($weights as $topicId => $weight) {
                self::execute(
                    'INSERT INTO topic_predictions (user_id, topic_id, weight) VALUES (?, ?, ?)',
                    [$userId, (int) $topicId, max(-1.0, min(1.0, (float) $weight))]
                );
            }
        });
    }
}
