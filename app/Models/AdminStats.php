<?php
declare(strict_types=1);

namespace Trevix\Models;

final class AdminStats extends Model
{
    /**
     * @return array{users:int, posts:int, active_users:int, open_reports:int, suspended_users:int,
     *               hidden_posts:int, communities:int, reports_today:int, pending_songs:int, published_songs:int}
     */
    public static function overview(): array
    {
        return [
            'users'        => (int) self::fetchValue("SELECT COUNT(*) FROM users WHERE status <> 'deleted'"),
            'posts'        => (int) self::fetchValue("SELECT COUNT(*) FROM posts WHERE status = 'published'"),
            'active_users' => (int) self::fetchValue(
                'SELECT COUNT(*) FROM users WHERE last_seen_at >= (NOW() - INTERVAL 1 DAY)'
            ),
            'open_reports'    => Report::openCount(),
            'suspended_users' => (int) self::fetchValue("SELECT COUNT(*) FROM users WHERE status = 'suspended'"),
            'hidden_posts'    => (int) self::fetchValue("SELECT COUNT(*) FROM posts WHERE status = 'hidden'"),
            'communities'     => (int) self::fetchValue("SELECT COUNT(*) FROM communities WHERE status <> 'deleted'"),
            'reports_today'   => (int) self::fetchValue('SELECT COUNT(*) FROM reports WHERE created_at >= (NOW() - INTERVAL 1 DAY)'),
            'pending_songs'   => Song::pendingCount(),
            'published_songs' => (int) self::fetchValue("SELECT COUNT(*) FROM songs WHERE status = 'published'"),
        ];
    }
}
