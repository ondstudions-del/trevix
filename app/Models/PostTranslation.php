<?php
declare(strict_types=1);

namespace Trevix\Models;

/** Traducciones con IA de publicaciones, una por idioma; se rehacen si el autor edita el texto (source_hash). */
final class PostTranslation extends Model
{
    public static function find(int $postId, string $lang, string $sourceHash): ?array
    {
        return self::fetchOne(
            'SELECT body, source_lang FROM post_translations WHERE post_id = ? AND target_lang = ? AND source_hash = ? LIMIT 1',
            [$postId, $lang, $sourceHash]
        );
    }

    public static function save(int $postId, string $lang, ?string $sourceLang, string $sourceHash, string $body): void
    {
        self::execute(
            'INSERT INTO post_translations (post_id, target_lang, source_lang, source_hash, body) VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE source_lang = VALUES(source_lang), source_hash = VALUES(source_hash), body = VALUES(body), created_at = NOW()',
            [$postId, $lang, $sourceLang, $sourceHash, $body]
        );
    }
}
