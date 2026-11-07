<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Me gusta y guardados. La clave primaria (usuario, publicación) impide duplicados y el contador
 * solo cambia cuando la fila realmente se insertó o se borró, así no se desincroniza con dobles clics.
 */
final class Interaction extends Model
{
    private const KINDS = [
        'like' => ['table' => 'likes', 'column' => 'likes_count'],
        'save' => ['table' => 'saved_posts', 'column' => 'saves_count'],
    ];

    /** @return array{active: bool, count: int} */
    public static function toggle(string $kind, int $userId, int $postId): array
    {
        $cfg = self::KINDS[$kind] ?? throw new \LogicException('Interacción desconocida: ' . $kind);
        $table = $cfg['table'];
        $column = $cfg['column'];

        return Database::transaction(static function () use ($table, $column, $userId, $postId): array {
            $deleted = self::execute("DELETE FROM $table WHERE user_id = ? AND post_id = ?", [$userId, $postId]);
            if ($deleted === 1) {
                self::execute("UPDATE posts SET $column = $column - ($column > 0) WHERE id = ?", [$postId]);
                $active = false;
            } else {
                $inserted = self::execute("INSERT IGNORE INTO $table (user_id, post_id) VALUES (?, ?)", [$userId, $postId]);
                if ($inserted === 1) {
                    self::execute("UPDATE posts SET $column = $column + 1 WHERE id = ?", [$postId]);
                }
                $active = true;
            }
            $count = (int) self::fetchValue("SELECT $column FROM posts WHERE id = ?", [$postId]);
            return ['active' => $active, 'count' => $count];
        });
    }
}
