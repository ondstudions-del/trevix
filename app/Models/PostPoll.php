<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Encuestas publicadas como post: la pregunta es el texto de la publicación y tiene de 2 a 4 respuestas.
 * Cada persona vota una sola vez; los resultados se ven después de votar, al terminar la encuesta o siendo el autor.
 */
final class PostPoll extends Model
{
    public const MIN_OPTIONS = 2;
    public const MAX_OPTIONS = 4;
    public const OPTION_MAX = 80;
    public const DURATIONS = [1, 3, 7];

    /** Se llama dentro de la transacción de Post::create. */
    public static function create(int $postId, array $options, int $days): void
    {
        $days = in_array($days, self::DURATIONS, true) ? $days : self::DURATIONS[0];
        self::execute('INSERT INTO post_polls (post_id, ends_at) VALUES (?, NOW() + INTERVAL ? DAY)', [$postId, $days]);
        foreach (array_values($options) as $position => $label) {
            self::execute('INSERT INTO post_poll_options (post_id, position, label) VALUES (?, ?, ?)', [$postId, $position, $label]);
        }
    }

    /**
     * Encuestas de estas publicaciones, ya preparadas para la vista.
     * @return array<int, array{options: list<array>, total: int, ends_at: string, ended: bool, viewer_vote: ?int, show_results: bool}>
     */
    public static function forPosts(array $postIds, int $viewerId): array
    {
        $postIds = array_values(array_unique(array_filter(array_map('intval', $postIds))));
        if ($postIds === []) {
            return [];
        }
        $marks = implode(',', array_fill(0, count($postIds), '?'));
        $polls = self::fetchAll(
            "SELECT pp.post_id, pp.ends_at, pp.votes_count, pp.ends_at <= NOW() AS ended, p.user_id,
                    (SELECT v.option_id FROM post_poll_votes v WHERE v.post_id = pp.post_id AND v.user_id = ?) AS viewer_vote
             FROM post_polls pp JOIN posts p ON p.id = pp.post_id WHERE pp.post_id IN ($marks)",
            array_merge([$viewerId], $postIds)
        );
        if ($polls === []) {
            return [];
        }
        $options = [];
        foreach (self::fetchAll(
            "SELECT id, post_id, label, votes_count FROM post_poll_options WHERE post_id IN ($marks) ORDER BY post_id, position",
            $postIds
        ) as $o) {
            $options[(int) $o['post_id']][] = $o;
        }

        $out = [];
        foreach ($polls as $poll) {
            $id = (int) $poll['post_id'];
            $total = (int) $poll['votes_count'];
            $vote = $poll['viewer_vote'] !== null ? (int) $poll['viewer_vote'] : null;
            $ended = (bool) $poll['ended'];
            $show = $vote !== null || $ended || ($viewerId > 0 && (int) $poll['user_id'] === $viewerId);
            $out[$id] = [
                'options'      => array_map(static function (array $o) use ($total, $show): array {
                    $votes = (int) $o['votes_count'];
                    return [
                        'id'      => (int) $o['id'],
                        'label'   => $o['label'],
                        'votes'   => $show ? $votes : null,
                        'percent' => $show ? ($total > 0 ? (int) round($votes * 100 / $total) : 0) : null,
                    ];
                }, $options[$id] ?? []),
                'total'        => $total,
                'ends_at'      => $poll['ends_at'],
                'ended'        => $ended,
                'viewer_vote'  => $vote,
                'show_results' => $show,
            ];
        }
        return $out;
    }

    /**
     * Voto de $userId. Devuelve false si ya había votado, la encuesta terminó o la respuesta no es de esta encuesta.
     */
    public static function vote(int $postId, int $userId, int $optionId): bool
    {
        return (bool) Database::transaction(static function () use ($postId, $userId, $optionId): bool {
            $open = self::fetchValue(
                'SELECT 1 FROM post_polls pp JOIN post_poll_options o ON o.post_id = pp.post_id
                 WHERE pp.post_id = ? AND o.id = ? AND pp.ends_at > NOW() FOR UPDATE',
                [$postId, $optionId]
            );
            if (!$open) {
                return false;
            }
            if (self::execute('INSERT IGNORE INTO post_poll_votes (post_id, user_id, option_id) VALUES (?, ?, ?)', [$postId, $userId, $optionId]) === 0) {
                return false;
            }
            self::execute('UPDATE post_poll_options SET votes_count = votes_count + 1 WHERE id = ?', [$optionId]);
            self::execute('UPDATE post_polls SET votes_count = votes_count + 1 WHERE post_id = ?', [$postId]);
            return true;
        });
    }
}
