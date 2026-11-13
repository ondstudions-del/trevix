<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\Database;
use Trevix\Core\Deferred;
use Trevix\Models\RateLimit;
use Trevix\Models\Topic;

/**
 * Predicción de gustos con IA: una vez al día por persona, Gemini mira los temas y hashtags que le interesan y los que
 * marcó con «No me importa» y elige, entre los temas que se están publicando, los que probablemente querrá ver (y los
 * que no) aunque todavía no haya interactuado con ellos. El resultado (topic_predictions) suma o resta en el orden
 * de «Para ti» y de los reels (InterestService::affinitySql).
 */
final class TasteService
{
    /** Puntos de afinidad que vale una predicción con peso 1 (un me gusta vale 3). */
    public const PREDICTION_POINTS = 12;
    private const REFRESH_HOURS = 24;
    private const CANDIDATE_DAYS = 30;
    private const MAX_CANDIDATES = 80;

    /** Al abrir «Para ti» o los reels: rehace la predicción al terminar la petición si ya tiene un día. */
    public static function refreshLater(int $userId): void
    {
        if ($userId < 1 || !Gemini::configured()) {
            return;
        }
        Deferred::run(static fn () => self::refresh($userId));
        ContentAi::backfillLater();
    }

    /** @return bool true si guardó una predicción nueva */
    public static function refresh(int $userId): bool
    {
        $db = Database::connection();
        // Reclama la predicción del día (status se asigna antes que predicted_at para leer la fecha anterior).
        $claim = $db->prepare(
            "INSERT INTO taste_profiles (user_id, predicted_at, status) VALUES (?, NOW(), 'empty')
             ON DUPLICATE KEY UPDATE
                status = IF(predicted_at < NOW() - INTERVAL " . self::REFRESH_HOURS . " HOUR, 'empty', status),
                predicted_at = IF(predicted_at < NOW() - INTERVAL " . self::REFRESH_HOURS . ' HOUR, NOW(), predicted_at)'
        );
        $claim->execute([$userId]);
        if ($claim->rowCount() === 0) {
            return false;
        }

        $likedTopics = Topic::userTop($userId, 'topics', true, 15);
        $likedTags = Topic::userTop($userId, 'hashtags', true, 15);
        if (count($likedTopics) + count($likedTags) < 2) {
            return false;
        }
        $candidates = Topic::recentPopular(self::CANDIDATE_DAYS, self::MAX_CANDIDATES);
        if (count($candidates) < 3 || RateLimit::tooManyAttempts('taste_daily', 'global')) {
            return false;
        }
        RateLimit::hit('taste_daily', 'global');

        $profile = json_encode([
            'temas_que_le_gustan'    => $likedTopics,
            'hashtags_que_le_gustan' => $likedTags,
            'temas_que_no_le_importan'    => Topic::userTop($userId, 'topics', false, 10),
            'hashtags_que_no_le_importan' => Topic::userTop($userId, 'hashtags', false, 10),
            'temas_candidatos'       => array_keys($candidates),
        ], JSON_UNESCAPED_UNICODE);

        try {
            $result = Gemini::json(self::prompt(), [['role' => 'user', 'parts' => [['text' => (string) $profile]]]], [
                'type'       => 'OBJECT',
                'properties' => [
                    'predictions' => [
                        'type'  => 'ARRAY',
                        'items' => [
                            'type'       => 'OBJECT',
                            'properties' => ['topic' => ['type' => 'STRING'], 'weight' => ['type' => 'NUMBER']],
                            'required'   => ['topic', 'weight'],
                        ],
                    ],
                ],
                'required'   => ['predictions'],
            ], 0.4);
        } catch (RuntimeException $e) {
            error_log('TREVIX predicción de gustos ' . $userId . ': ' . $e->getMessage());
            $db->prepare("UPDATE taste_profiles SET status = 'failed' WHERE user_id = ?")->execute([$userId]);
            return false;
        }

        $weights = [];
        foreach ((array) ($result['predictions'] ?? []) as $item) {
            $name = Topic::normalize((string) ($item['topic'] ?? ''));
            $weight = (float) ($item['weight'] ?? 0);
            if (isset($candidates[$name]) && abs($weight) >= 0.1 && count($weights) < 30) {
                $weights[$candidates[$name]] = $weight;
            }
        }
        try {
            Topic::savePredictions($userId, $weights);
            $db->prepare("UPDATE taste_profiles SET status = 'ok' WHERE user_id = ?")->execute([$userId]);
        } catch (Throwable $e) {
            error_log('TREVIX predicción de gustos ' . $userId . ': ' . $e->getMessage());
            return false;
        }
        return true;
    }

    private static function prompt(): string
    {
        return <<<'TXT'
Eres el motor de recomendaciones de TREVIX, una red social. Recibes los gustos de una persona (temas y hashtags con los que interactúa) y lo que marcó con «No me importa», más una lista de temas candidatos que se están publicando. Predice qué contenido querrá ver en su feed y en los reels.

Responde en JSON con predictions: hasta 25 temas tomados EXACTAMENTE de temas_candidatos, cada uno con weight entre -1 y 1:
- Positivo (0.2 a 1) para los temas que probablemente le gustarán, incluidos los relacionados con sus gustos que aún no ha visto (por ejemplo, a quien le gusta el fútbol probablemente le interesen los deportes o los videojuegos de fútbol).
- Negativo (-0.2 a -1) para los temas parecidos a lo que marcó con «No me importa».
No incluyas temas fuera de la lista ni repitas temas.
TXT;
    }
}
