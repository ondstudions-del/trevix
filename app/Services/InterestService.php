<?php
declare(strict_types=1);

namespace Trevix\Services;

use Throwable;
use Trevix\Core\Database;

/**
 * Intereses de cada persona por hashtag para ordenar «Para ti». Dar me gusta, comentar, guardar, compartir o ver
 * mucho tiempo una publicación suma puntos a sus hashtags; los puntos se enfrían un 3 % por día sin actividad.
 */
final class InterestService
{
    public const LIKE = 3.0;
    public const COMMENT = 4.0;
    public const SAVE = 3.0;
    public const SHARE = 5.0;
    public const LONG_VIEW = 2.0;

    /** Tope de puntos de un hashtag, para que una sola etiqueta no acapare el feed. */
    private const MAX_SCORE = 1000;

    /** Factor de enfriamiento diario (también lo usa la consulta de «Para ti»). */
    public const DECAY = 0.97;

    /** Las publicaciones propias no cuentan. Si falla, la acción que lo provocó sigue igual (es un extra). */
    public static function fromPost(int $userId, int $postId, float $weight): void
    {
        if ($userId < 1 || $postId < 1 || $weight <= 0) {
            return;
        }
        try {
            $stmt = Database::connection()->prepare(
                'INSERT INTO hashtag_interests (user_id, hashtag_id, score, updated_at)
                 SELECT ?, ph.hashtag_id, ?, NOW()
                 FROM post_hashtags ph JOIN posts p ON p.id = ph.post_id
                 WHERE ph.post_id = ? AND p.user_id <> ?
                 ON DUPLICATE KEY UPDATE
                    score = LEAST(score * POW(' . self::DECAY . ', DATEDIFF(NOW(), updated_at)) + VALUES(score), ' . self::MAX_SCORE . '),
                    updated_at = NOW()'
            );
            $stmt->execute([$userId, $weight, $postId, $userId]);
        } catch (Throwable $e) {
            error_log('TREVIX intereses: ' . $e->getMessage());
        }
    }
}
