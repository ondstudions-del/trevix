<?php
declare(strict_types=1);

namespace Trevix\Services;

use PDO;
use RuntimeException;
use Throwable;
use Trevix\Core\Database;
use Trevix\Core\Deferred;
use Trevix\Models\RateLimit;
use Trevix\Models\Topic;

/**
 * Revisión de cada publicación con la IA (Gemini) después de publicarla: le pone de 1 a 5 temas para el feed y
 * reconoce el contenido para adultos (+18), que desde ese momento solo ven las cuentas mayores de edad. Corre al
 * terminar la petición (Deferred) y las publicaciones recientes que aún no se revisaron se revisan poco a poco
 * mientras la gente usa el feed. Lo que marca el autor o un moderador como +18 no lo cambia la IA.
 */
final class ContentAi
{
    private const MAX_IMAGES = 3;
    private const MAX_IMAGE_BYTES = 1_500_000;
    private const IMAGE_TYPES = ['jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp'];
    /** Días hacia atrás que se revisan las publicaciones que quedaron sin revisar. */
    private const BACKFILL_DAYS = 30;

    /** Revisa la publicación al terminar la petición. Con $again se revisa de nuevo (se editó el texto). */
    public static function analyzeLater(int $postId, bool $again = false): void
    {
        if ($postId > 0 && Gemini::configured()) {
            Deferred::run(static fn () => self::analyze($postId, $again));
        }
    }

    /** Revisa al terminar la petición algunas publicaciones recientes que aún no pasaron por la IA. */
    public static function backfillLater(int $count = 2): void
    {
        if (!Gemini::configured()) {
            return;
        }
        Deferred::run(static function () use ($count): void {
            $ids = Database::connection()->query(
                "SELECT id FROM posts WHERE ai_checked_at IS NULL AND status = 'published' AND shared_post_id IS NULL
                   AND created_at > NOW() - INTERVAL " . self::BACKFILL_DAYS . ' DAY
                 ORDER BY id DESC LIMIT ' . max(1, min(5, $count))
            )->fetchAll(PDO::FETCH_COLUMN);
            foreach ($ids as $id) {
                self::analyze((int) $id);
            }
        });
    }

    /** @return array{adult: bool, topics: list<string>}|null null si no se revisó (sin cupo, ya revisada o falló). */
    public static function analyze(int $postId, bool $again = false): ?array
    {
        if (RateLimit::tooManyAttempts('content_ai', 'global') || RateLimit::tooManyAttempts('content_ai_daily', 'global')) {
            return null;
        }
        $db = Database::connection();
        $claim = $db->prepare(
            "UPDATE posts SET ai_checked_at = NOW() WHERE id = ? AND status = 'published'" . ($again ? '' : ' AND ai_checked_at IS NULL')
        );
        $claim->execute([$postId]);
        if ($claim->rowCount() === 0) {
            return null;
        }

        $stmt = $db->prepare('SELECT body, adult_source, life_event, location_name, gif_title FROM posts WHERE id = ?');
        $stmt->execute([$postId]);
        $post = $stmt->fetch(PDO::FETCH_ASSOC);
        $stmt = $db->prepare('SELECT type, path, poster_path FROM post_media WHERE post_id = ? ORDER BY position');
        $stmt->execute([$postId]);
        $media = $stmt->fetchAll(PDO::FETCH_ASSOC);
        if (!$post) {
            return null;
        }

        $parts = self::parts($post, $media);
        if ($parts === null) {
            return null;
        }
        RateLimit::hit('content_ai', 'global');
        RateLimit::hit('content_ai_daily', 'global');

        try {
            $result = Gemini::json(self::prompt(), [['role' => 'user', 'parts' => $parts]], [
                'type'       => 'OBJECT',
                'properties' => [
                    'adult'  => ['type' => 'BOOLEAN'],
                    'topics' => ['type' => 'ARRAY', 'items' => ['type' => 'STRING']],
                ],
                'required'   => ['adult', 'topics'],
            ], 0.2, null, true);
            $adult = !empty($result['adult']);
            $topics = array_values(array_filter((array) ($result['topics'] ?? []), 'is_string'));
        } catch (RuntimeException $e) {
            if ($e->getCode() !== Gemini::BLOCKED) {
                error_log('TREVIX revisión IA ' . $postId . ': ' . $e->getMessage());
                return null;
            }
            // Gemini se negó a revisarla por sus filtros de seguridad: se trata como contenido para adultos.
            $adult = true;
            $topics = [];
        }

        try {
            $source = $post['adult_source'];
            if ($adult && $source === null) {
                $db->prepare("UPDATE posts SET is_adult = 1, adult_source = 'ai' WHERE id = ?")->execute([$postId]);
            } elseif (!$adult && $source === 'ai') {
                $db->prepare('UPDATE posts SET is_adult = 0, adult_source = NULL WHERE id = ?')->execute([$postId]);
            }
            if ($topics !== [] || $again) {
                Topic::sync($postId, $topics);
            }
        } catch (Throwable $e) {
            error_log('TREVIX revisión IA ' . $postId . ': ' . $e->getMessage());
            return null;
        }
        return ['adult' => $adult, 'topics' => $topics];
    }

    /** Texto e imágenes (las fotos y la portada de los videos) que se envían a revisar; null si no hay nada. */
    private static function parts(array $post, array $media): ?array
    {
        $tags = [];
        preg_match_all('/#([\p{L}\p{N}_]{2,50})/u', (string) $post['body'], $m);
        foreach ($m[1] ?? [] as $tag) {
            $tags[] = '#' . mb_strtolower($tag);
        }
        $lines = [];
        if (trim((string) $post['body']) !== '') {
            $lines[] = 'Texto: ' . mb_substr((string) $post['body'], 0, 3000);
        }
        if ($post['gif_title'] !== null) {
            $lines[] = 'GIF: ' . $post['gif_title'];
        }
        if ($post['life_event'] !== null) {
            $lines[] = 'Acontecimiento: ' . $post['life_event'];
        }
        if ($post['location_name'] !== null) {
            $lines[] = 'Lugar: ' . $post['location_name'];
        }
        $videos = count(array_filter($media, static fn (array $x): bool => $x['type'] === 'video'));
        if ($media !== []) {
            $lines[] = 'Adjuntos: ' . (count($media) - $videos) . ' imagen(es), ' . $videos . ' video(s) (de los videos va su portada).';
        }

        $images = [];
        foreach ($media as $item) {
            if (count($images) >= self::MAX_IMAGES) {
                break;
            }
            $path = $item['type'] === 'video' ? $item['poster_path'] : $item['path'];
            $image = self::inlineImage($path);
            if ($image !== null) {
                $images[] = $image;
            }
        }
        if ($lines === [] && $images === []) {
            return null;
        }
        return array_merge([['text' => implode("\n", $lines ?: ['(sin texto)'])]], $images);
    }

    private static function inlineImage(?string $relative): ?array
    {
        if ($relative === null || str_contains($relative, '..')) {
            return null;
        }
        $mime = self::IMAGE_TYPES[strtolower(pathinfo($relative, PATHINFO_EXTENSION))] ?? null;
        $file = BASE_PATH . '/' . $relative;
        if ($mime === null || !is_file($file) || filesize($file) > self::MAX_IMAGE_BYTES) {
            return null;
        }
        $data = file_get_contents($file);
        return $data !== false ? ['inline_data' => ['mime_type' => $mime, 'data' => base64_encode($data)]] : null;
    }

    private static function prompt(): string
    {
        return <<<'TXT'
Eres el revisor de contenido de TREVIX, una red social en la que también hay menores de edad. Revisa la publicación (texto, hashtags e imágenes; de los videos recibes su portada) y responde en JSON:

- adult: true solo si es contenido para adultos que un menor no debe ver: desnudos o semidesnudos con intención sexual, actos o insinuaciones sexuales explícitas, pornografía, juguetes o servicios sexuales, violencia gráfica o sangre real, gore, autolesiones, o consumo explícito de drogas. false para todo lo demás: ropa de baño o deportiva normal, besos, humor, arte no sexual, noticias, lenguaje vulgar leve o fiestas.
- topics: de 1 a 5 temas generales de la publicación, en español, en minúsculas, de 1 a 3 palabras y sin #. Usa temas amplios y reutilizables (por ejemplo: fútbol, cocina, memes, música urbana, videojuegos, moda, viajes, mascotas, tecnología, fitness, humor, anime, naturaleza, belleza, autos, educación, familia, noticias, arte, baile). Nada de frases ni nombres propios poco conocidos.
TXT;
    }
}
