<?php
declare(strict_types=1);

namespace Trevix\Models;

final class ProfilePhoto extends Model
{
    public const KINDS = ['avatar', 'cover'];

    public const PRIVACY = ['public', 'followers', 'only_me'];

    public static function like(int $ownerId, string $kind, int $userId): bool
    {
        if ($ownerId === $userId) {
            return false;
        }
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

    /** @return list<array> */
    public static function comments(int $ownerId, string $kind, int $beforeId, int $limit): array
    {
        $sql = 'SELECT c.id, c.owner_id, c.kind, c.user_id, c.body, c.created_at,
                       u.username, u.display_name, u.avatar_path, u.account_type, u.creator_category, u.is_verified
                FROM profile_photo_comments c
                JOIN users u ON u.id = c.user_id
                WHERE c.owner_id = ? AND c.kind = ?';
        $params = [$ownerId, $kind];
        if ($beforeId > 0) {
            $sql .= ' AND c.id < ?';
            $params[] = $beforeId;
        }
        $sql .= ' ORDER BY c.id DESC LIMIT ' . max(1, min(50, $limit));
        return self::fetchAll($sql, $params);
    }

    public static function addComment(int $ownerId, string $kind, int $userId, string $body): int
    {
        self::execute(
            'INSERT INTO profile_photo_comments (owner_id, kind, user_id, body) VALUES (?, ?, ?, ?)',
            [$ownerId, $kind, $userId, $body]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function commentsCount(int $ownerId, string $kind): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM profile_photo_comments WHERE owner_id = ? AND kind = ?',
            [$ownerId, $kind]
        );
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
}