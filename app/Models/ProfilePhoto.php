<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Services\Giphy;

final class ProfilePhoto extends Model
{
    public const KINDS = ['avatar', 'cover'];

    public const PRIVACY = ['public', 'followers', 'only_me'];

    public static function like(int $ownerId, string $kind, int $userId): bool
    {
        return self::execute(
            'INSERT IGNORE INTO profile_photo_likes (owner_id, kind, user_id) VALUES (?, ?, ?)',
            [$ownerId, $kind, $userId]
        ) > 0;
    }

    public static function unlike(int $ownerId, string $kind, int $userId): bool
    {
        return self::execute(
            'DELETE FROM profile_photo_likes WHERE owner_id = ? AND kind = ? AND user_id = ?',
            [$ownerId, $kind, $userId]
        ) > 0;
    }

    public static function liked(int $ownerId, string $kind, int $userId): bool
    {
        return (bool) self::fetchValue(
            'SELECT 1 FROM profile_photo_likes WHERE owner_id = ? AND kind = ? AND user_id = ? LIMIT 1',
            [$ownerId, $kind, $userId]
        );
    }

    public static function likesCount(int $ownerId, string $kind): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM profile_photo_likes WHERE owner_id = ? AND kind = ?',
            [$ownerId, $kind]
        );
    }

    public static function commentsCount(int $ownerId, string $kind): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM profile_photo_comments WHERE owner_id = ? AND kind = ?',
            [$ownerId, $kind]
        );
    }

    /** Raíces (parent_id NULL), más recientes primero. */
    public static function rootComments(int $ownerId, string $kind, int $beforeId, int $limit): array
    {
        $sql = 'SELECT c.*, u.username, u.display_name, u.avatar_path, u.account_type, u.creator_category, u.is_verified
                FROM profile_photo_comments c
                JOIN users u ON u.id = c.user_id
                WHERE c.owner_id = ? AND c.kind = ? AND c.parent_id IS NULL';
        $params = [$ownerId, $kind];
        if ($beforeId > 0) {
            $sql .= ' AND c.id < ?';
            $params[] = $beforeId;
        }
        $sql .= ' ORDER BY c.id DESC LIMIT ' . max(1, min(50, $limit));
        return self::fetchAll($sql, $params);
    }

    /** @deprecated flat list; prefer threaded() */
    public static function comments(int $ownerId, string $kind, int $beforeId, int $limit): array
    {
        return self::rootComments($ownerId, $kind, $beforeId, $limit);
    }

    public static function repliesFor(array $parentIds): array
    {
        if ($parentIds === []) {
            return [];
        }
        $ph = implode(',', array_fill(0, count($parentIds), '?'));
        return self::fetchAll(
            "SELECT c.*, u.username, u.display_name, u.avatar_path, u.account_type, u.creator_category, u.is_verified
             FROM profile_photo_comments c
             JOIN users u ON u.id = c.user_id
             WHERE c.parent_id IN ($ph)
             ORDER BY c.id ASC",
            array_values($parentIds)
        );
    }

    /** Hilos listos para Present (con reacciones del viewer). */
    public static function threaded(int $ownerId, string $kind, int $viewerId, int $beforeId, int $limit): array
    {
        $roots = self::rootComments($ownerId, $kind, $beforeId, $limit);
        if ($roots === []) {
            return [];
        }
        $ids = array_map(static fn(array $r) => (int) $r['id'], $roots);
        $replies = self::repliesFor($ids);
        $byParent = [];
        foreach ($replies as $row) {
            $byParent[(int) $row['parent_id']][] = $row;
        }
        $out = [];
        foreach ($roots as $row) {
            $shaped = self::shape($row, $viewerId);
            $shaped['replies'] = array_map(
                static fn(array $r) => self::shape($r, $viewerId),
                $byParent[(int) $row['id']] ?? []
            );
            $shaped['replies_count'] = count($shaped['replies']);
            $out[] = $shaped;
        }
        return $out;
    }

    public static function findComment(int $id): ?array
    {
        return self::fetchOne(
            'SELECT c.*, u.username, u.display_name, u.avatar_path, u.account_type, u.creator_category, u.is_verified
             FROM profile_photo_comments c
             JOIN users u ON u.id = c.user_id
             WHERE c.id = ? LIMIT 1',
            [$id]
        );
    }

    /**
     * @param array|null $gif campos de Giphy::resolve
     * @param array{path:string,width:int,height:int}|null $media
     */
    public static function addComment(
        int $ownerId,
        string $kind,
        int $userId,
        string $body,
        ?int $parentId = null,
        ?array $gif = null,
        ?array $media = null
    ): int {
        self::execute(
            'INSERT INTO profile_photo_comments
                (owner_id, kind, user_id, parent_id, body,
                 gif_id, gif_kind, gif_url, gif_width, gif_height, gif_title,
                 media_path, media_width, media_height)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $ownerId,
                $kind,
                $userId,
                $parentId,
                $body === '' ? null : $body,
                $gif['gif_id'] ?? null,
                $gif['gif_kind'] ?? null,
                $gif['gif_url'] ?? null,
                $gif['gif_width'] ?? null,
                $gif['gif_height'] ?? null,
                $gif['gif_title'] ?? null,
                $media['path'] ?? null,
                $media['width'] ?? null,
                $media['height'] ?? null,
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function deleteComment(int $id): bool
    {
        return self::execute('DELETE FROM profile_photo_comments WHERE id = ?', [$id]) > 0;
    }

    public static function clearInteractions(int $ownerId, string $kind): void
    {
        self::execute('DELETE FROM profile_photo_likes WHERE owner_id = ? AND kind = ?', [$ownerId, $kind]);
        self::execute('DELETE FROM profile_photo_comments WHERE owner_id = ? AND kind = ?', [$ownerId, $kind]);
    }

    /** @return array{reaction:?string,likes:int,dislikes:int} */
    public static function setReaction(int $commentId, int $userId, ?string $value): array
    {
        self::execute(
            'DELETE FROM profile_photo_comment_reactions WHERE comment_id = ? AND user_id = ?',
            [$commentId, $userId]
        );
        if ($value === 'like' || $value === 'dislike') {
            self::execute(
                'INSERT INTO profile_photo_comment_reactions (comment_id, user_id, value) VALUES (?, ?, ?)',
                [$commentId, $userId, $value]
            );
        }
        return self::reactionStats($commentId, $userId);
    }

    /** @return array{reaction:?string,likes:int,dislikes:int} */
    public static function reactionStats(int $commentId, int $viewerId): array
    {
        $likes = (int) self::fetchValue(
            "SELECT COUNT(*) FROM profile_photo_comment_reactions WHERE comment_id = ? AND value = 'like'",
            [$commentId]
        );
        $dislikes = (int) self::fetchValue(
            "SELECT COUNT(*) FROM profile_photo_comment_reactions WHERE comment_id = ? AND value = 'dislike'",
            [$commentId]
        );
        $mine = $viewerId > 0
            ? self::fetchValue(
                'SELECT value FROM profile_photo_comment_reactions WHERE comment_id = ? AND user_id = ? LIMIT 1',
                [$commentId, $viewerId]
            )
            : null;
        return [
            'likes'    => $likes,
            'dislikes' => $dislikes,
            'reaction' => $mine !== null && $mine !== false ? (string) $mine : null,
        ];
    }

    public static function updateUser(int $userId, array $assignments): void
    {
        if ($assignments === []) {
            return;
        }
        $parts = [];
        $params = [];
        foreach ($assignments as $column => $value) {
            $parts[] = $column . ' = ?';
            $params[] = $value;
        }
        $params[] = $userId;
        self::execute('UPDATE users SET ' . implode(', ', $parts) . ' WHERE id = ?', $params);
    }

    private static function shape(array $r, int $viewerId): array
    {
        $id = (int) $r['id'];
        $stats = self::reactionStats($id, $viewerId);
        return [
            'id'              => $id,
            'owner_id'        => (int) $r['owner_id'],
            'kind'            => (string) $r['kind'],
            'user_id'         => (int) $r['user_id'],
            'parent_id'       => $r['parent_id'] !== null ? (int) $r['parent_id'] : null,
            'body'            => (string) ($r['body'] ?? ''),
            'gif'             => Giphy::fromRow($r),
            'media'           => !empty($r['media_path'])
                ? ['path' => (string) $r['media_path'], 'width' => (int) ($r['media_width'] ?? 0), 'height' => (int) ($r['media_height'] ?? 0)]
                : null,
            'likes_count'     => $stats['likes'],
            'dislikes_count'  => $stats['dislikes'],
            'viewer_reaction' => $stats['reaction'],
            'replies_count'   => 0,
            'replies'         => [],
            'created_at'      => (string) ($r['created_at'] ?? ''),
            'user'            => [
                'id'               => (int) $r['user_id'],
                'username'         => (string) $r['username'],
                'display_name'     => (string) $r['display_name'],
                'avatar_path'      => $r['avatar_path'] ?? null,
                'account_type'     => $r['account_type'] ?? 'personal',
                'creator_category' => $r['creator_category'] ?? null,
                'is_verified'      => !empty($r['is_verified']),
            ],
        ];
    }
}
