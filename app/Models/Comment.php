<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;
use Trevix\Services\Giphy;

/**
 * Comentarios con un nivel de respuestas (parent_id). posts.comments_count cuenta comentarios
 * y respuestas; comments.replies_count cuenta las respuestas directas de cada comentario.
 */
final class Comment extends Model
{
    private const SELECT = 'SELECT c.id, c.post_id, c.user_id, c.parent_id, c.body, c.replies_count, c.is_edited, c.created_at,
            c.gif_id, c.gif_kind, c.gif_url, c.gif_width, c.gif_height, c.gif_title,
            u.username, u.display_name, u.avatar_path, u.is_verified
        FROM comments c JOIN users u ON u.id = c.user_id';

    private const VISIBLE = "c.status = 'published' AND u.status = 'active' AND NOT EXISTS (
            SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = c.user_id) OR (b.blocker_id = c.user_id AND b.blocked_id = ?))";

    public static function find(int $id): ?array
    {
        return self::fetchOne(
            "SELECT id, post_id, user_id, parent_id FROM comments WHERE id = ? AND status = 'published' LIMIT 1",
            [$id]
        );
    }

    /**
     * Listado del panel: comentarios por texto o autor (@usuario), del más reciente al más antiguo.
     * @return array{comments: list<array>, hasMore: bool}
     */
    public static function adminList(string $term, int $page, int $limit): array
    {
        $where = ["c.status = 'published'"];
        $params = [];
        $term = trim($term);
        if (str_starts_with($term, '@')) {
            $where[] = 'u.username = ?';
            $params[] = mb_strtolower(substr($term, 1));
        } elseif ($term !== '') {
            $where[] = 'c.body LIKE ?';
            $params[] = '%' . self::likeEscape($term) . '%';
        }
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            "SELECT c.id, c.post_id, c.user_id, c.parent_id, c.body, c.gif_url, c.gif_kind, c.created_at, c.replies_count,
                    u.username, u.display_name, u.avatar_path, u.role AS author_role,
                    (SELECT COUNT(*) FROM reports r WHERE r.target_type = 'comment' AND r.target_id = c.id AND r.status IN ('open', 'reviewing')) AS open_reports
             FROM comments c JOIN users u ON u.id = c.user_id
             WHERE " . implode(' AND ', $where) . '
             ORDER BY c.id DESC LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return ['comments' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    public static function topLevelCount(int $postId): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM comments WHERE post_id = ? AND parent_id IS NULL AND status = 'published'",
            [$postId]
        );
    }

    /** @param array|null $gif campos gif_* de Giphy::resolve */
    public static function create(int $postId, int $userId, ?int $parentId, string $body, ?array $gif = null): int
    {
        return (int) Database::transaction(static function () use ($postId, $userId, $parentId, $body, $gif): int {
            self::execute(
                'INSERT INTO comments (post_id, user_id, parent_id, body, gif_id, gif_kind, gif_url, gif_width, gif_height, gif_title)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [
                    $postId, $userId, $parentId, $body,
                    $gif['gif_id'] ?? null, $gif['gif_kind'] ?? null, $gif['gif_url'] ?? null,
                    $gif['gif_width'] ?? null, $gif['gif_height'] ?? null, $gif['gif_title'] ?? null,
                ]
            );
            $id = (int) self::db()->lastInsertId();
            self::execute('UPDATE posts SET comments_count = comments_count + 1 WHERE id = ?', [$postId]);
            if ($parentId !== null) {
                self::execute('UPDATE comments SET replies_count = replies_count + 1 WHERE id = ?', [$parentId]);
            }
            return $id;
        });
    }

    /** Borra el comentario y, en cascada, sus respuestas; ajusta los contadores. */
    public static function delete(array $comment): void
    {
        Database::transaction(static function () use ($comment): void {
            $id = (int) $comment['id'];
            $removed = 1 + (int) self::fetchValue('SELECT COUNT(*) FROM comments WHERE parent_id = ?', [$id]);

            self::execute(
                'UPDATE posts SET comments_count = GREATEST(CAST(comments_count AS SIGNED) - ?, 0) WHERE id = ?',
                [$removed, (int) $comment['post_id']]
            );
            if ($comment['parent_id'] !== null) {
                self::execute(
                    'UPDATE comments SET replies_count = replies_count - (replies_count > 0) WHERE id = ?',
                    [(int) $comment['parent_id']]
                );
            }
            self::execute('DELETE FROM comments WHERE id = ?', [$id]);
        });
    }

    /**
     * Comentarios principales de una publicación (del más antiguo al más reciente) con sus respuestas.
     * @return array{comments: list<array>, hasMore: bool}
     */
    public static function forPost(int $postId, int $viewerId, int $page, int $perPage): array
    {
        $rows = self::fetchAll(
            self::SELECT . ' WHERE c.post_id = ? AND c.parent_id IS NULL AND ' . self::VISIBLE
            . ' ORDER BY c.id ASC LIMIT ' . ($perPage + 1) . ' OFFSET ' . (max(0, $page - 1) * $perPage),
            [$postId, $viewerId, $viewerId]
        );
        $hasMore = count($rows) > $perPage;
        $rows = array_slice($rows, 0, $perPage);

        $replies = [];
        if ($rows !== []) {
            $ids = array_map(static fn (array $r) => (int) $r['id'], $rows);
            $marks = implode(',', array_fill(0, count($ids), '?'));
            foreach (self::fetchAll(
                self::SELECT . " WHERE c.parent_id IN ($marks) AND " . self::VISIBLE . ' ORDER BY c.id ASC',
                array_merge($ids, [$viewerId, $viewerId])
            ) as $reply) {
                $replies[(int) $reply['parent_id']][] = self::shape($reply);
            }
        }

        $comments = [];
        foreach ($rows as $row) {
            $comment = self::shape($row);
            $comment['replies'] = $replies[$comment['id']] ?? [];
            $comments[] = $comment;
        }
        return ['comments' => $comments, 'hasMore' => $hasMore];
    }

    private static function shape(array $r): array
    {
        return [
            'id'            => (int) $r['id'],
            'post_id'       => (int) $r['post_id'],
            'user_id'       => (int) $r['user_id'],
            'parent_id'     => $r['parent_id'] !== null ? (int) $r['parent_id'] : null,
            'body'          => $r['body'],
            'gif'           => Giphy::fromRow($r),
            'replies_count' => (int) $r['replies_count'],
            'created_at'    => $r['created_at'],
            'user'          => [
                'id'           => (int) $r['user_id'],
                'username'     => $r['username'],
                'display_name' => $r['display_name'],
                'avatar_path'  => $r['avatar_path'],
                'is_verified'  => (bool) $r['is_verified'],
            ],
            'replies'       => [],
        ];
    }
}
