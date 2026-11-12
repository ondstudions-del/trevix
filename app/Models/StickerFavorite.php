<?php
declare(strict_types=1);

namespace Trevix\Models;

/** Stickers y GIF de GIPHY guardados en favoritos para el chat (sticker_favorites). */
final class StickerFavorite extends Model
{
    public const MAX = 100;

    /** @return list<array> los más recientes primero */
    public static function forUser(int $userId): array
    {
        return self::fetchAll(
            'SELECT giphy_id, kind, url, width, height, title, created_at FROM sticker_favorites
             WHERE user_id = ? ORDER BY created_at DESC, giphy_id LIMIT ' . self::MAX,
            [$userId]
        );
    }

    public static function count(int $userId): int
    {
        return (int) self::fetchValue('SELECT COUNT(*) FROM sticker_favorites WHERE user_id = ?', [$userId]);
    }

    public static function exists(int $userId, string $giphyId): bool
    {
        return self::fetchValue('SELECT 1 FROM sticker_favorites WHERE user_id = ? AND giphy_id = ? LIMIT 1', [$userId, $giphyId]) !== false;
    }

    /** $gif = campos gif_* de Giphy::resolve. */
    public static function add(int $userId, array $gif): void
    {
        self::execute(
            'INSERT INTO sticker_favorites (user_id, giphy_id, kind, url, width, height, title) VALUES (?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE kind = VALUES(kind), url = VALUES(url), width = VALUES(width), height = VALUES(height),
                 title = VALUES(title), created_at = NOW()',
            [$userId, $gif['gif_id'], $gif['gif_kind'], $gif['gif_url'], $gif['gif_width'], $gif['gif_height'], $gif['gif_title']]
        );
    }

    public static function remove(int $userId, string $giphyId): void
    {
        self::execute('DELETE FROM sticker_favorites WHERE user_id = ? AND giphy_id = ?', [$userId, $giphyId]);
    }
}
