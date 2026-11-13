<?php
declare(strict_types=1);

namespace Trevix\Services;

use Throwable;
use Trevix\Core\Database;

/**
 * Intereses de cada persona por hashtag y por tema (los temas los pone la IA a cada publicación) para ordenar
 * «Para ti» y los reels. Dar me gusta, comentar, guardar, compartir o ver mucho tiempo una publicación suma puntos a
 * sus hashtags y temas; «No me importa» los resta. Los puntos se enfrían un 3 % por día sin actividad.
 */
final class InterestService
{
    public const LIKE = 3.0;
    public const COMMENT = 4.0;
    public const SAVE = 3.0;
    public const SHARE = 5.0;
    public const LONG_VIEW = 2.0;
    /** Puntos que resta «No me importa» a cada hashtag y tema de la publicación (deshacerlo los devuelve). */
    public const NOT_INTERESTED = 25.0;

    /** Tope de puntos de un hashtag o tema, para que uno solo no acapare el feed. */
    private const MAX_SCORE = 1000;
    private const MIN_SCORE = -200;

    /** Factor de enfriamiento diario (también lo usan las consultas de «Para ti» y de los reels). */
    public const DECAY = 0.97;

    /** Las publicaciones propias no cuentan. Si falla, la acción que lo provocó sigue igual (es un extra). */
    public static function fromPost(int $userId, int $postId, float $weight): void
    {
        if ($userId < 1 || $postId < 1 || $weight == 0.0) {
            return;
        }
        $score = 'GREATEST(LEAST(score * POW(' . self::DECAY . ', DATEDIFF(NOW(), updated_at)) + VALUES(score), ' . self::MAX_SCORE . '), ' . self::MIN_SCORE . ')';
        try {
            $db = Database::connection();
            $db->prepare(
                "INSERT INTO hashtag_interests (user_id, hashtag_id, score, updated_at)
                 SELECT ?, ph.hashtag_id, ?, NOW()
                 FROM post_hashtags ph JOIN posts p ON p.id = ph.post_id
                 WHERE ph.post_id = ? AND p.user_id <> ?
                 ON DUPLICATE KEY UPDATE score = $score, updated_at = NOW()"
            )->execute([$userId, $weight, $postId, $userId]);
            $db->prepare(
                "INSERT INTO topic_interests (user_id, topic_id, score, updated_at)
                 SELECT ?, pt.topic_id, ?, NOW()
                 FROM post_topics pt JOIN posts p ON p.id = pt.post_id
                 WHERE pt.post_id = ? AND p.user_id <> ?
                 ON DUPLICATE KEY UPDATE score = $score, updated_at = NOW()"
            )->execute([$userId, $weight, $postId, $userId]);
        } catch (Throwable $e) {
            error_log('TREVIX intereses: ' . $e->getMessage());
        }
    }

    /**
     * Afinidad (SQL) de $viewerId con la publicación p: puntos de sus hashtags y temas, enfriados por día, más la
     * predicción de la IA para sus temas. Puede ser negativa (temas que la persona marcó con «No me importa»).
     */
    public static function affinitySql(int $viewerId): string
    {
        $v = $viewerId;
        $d = self::DECAY;
        return "(COALESCE((SELECT SUM(ui.score * POW($d, DATEDIFF(NOW(), ui.updated_at)))
                    FROM post_hashtags ph JOIN hashtag_interests ui ON ui.hashtag_id = ph.hashtag_id AND ui.user_id = $v
                    WHERE ph.post_id = p.id), 0)
                + COALESCE((SELECT SUM(ti.score * POW($d, DATEDIFF(NOW(), ti.updated_at)))
                    FROM post_topics pt JOIN topic_interests ti ON ti.topic_id = pt.topic_id AND ti.user_id = $v
                    WHERE pt.post_id = p.id), 0)
                + COALESCE((SELECT SUM(tp.weight) * " . TasteService::PREDICTION_POINTS . "
                    FROM post_topics pt2 JOIN topic_predictions tp ON tp.topic_id = pt2.topic_id AND tp.user_id = $v
                    WHERE pt2.post_id = p.id), 0))";
    }

    /** Multiplicador del orden según la afinidad: de 0,1 (no le interesa nada) a 11 (máxima afinidad). */
    public static function factorSql(int $viewerId): string
    {
        return 'GREATEST(0.1, 1 + LEAST(' . self::affinitySql($viewerId) . ', 60) / 6)';
    }
}
