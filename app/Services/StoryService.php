<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Notification;
use Trevix\Models\ProfileAlert;
use Trevix\Models\RateLimit;
use Trevix\Models\Story;

/** Publicar historias de texto, foto o video (compartido por la web y la API). */
final class StoryService
{
    /**
     * @param string $type text | media
     * @param list<array> $files archivo de MediaUpload::collect (exactamente uno si es media)
     * @param int $songId canción de la biblioteca (0 = sin música) y $songStart, el segundo en que empieza
     * @param mixed $overlays capas del editor (JSON o lista; solo foto o video) y $filter, el filtro de color
     */
    public static function create(array $user, string $type, string $text, string $caption, string $background, array $files, int $songId = 0, int $songStart = 0, mixed $overlays = null, string $filter = ''): int
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $rateKey = 'user:' . $uid;
        Guard::rateLimit('story_create', $rateKey, 'Publicaste muchas historias seguidas. Inténtalo de nuevo en {min} min.');

        $song = $songId > 0 ? MusicService::resolveForUse($songId, $songStart, $uid) : null;
        $layers = $type === 'text' ? ['items' => [], 'mentions' => []] : StoryOverlays::normalize($uid, $overlays);
        $media = null;
        if ($type === 'text') {
            $body = Guard::cleanText($text);
            $max = (int) Config::get('app.limits.story_text', 300);
            if ($body === '') {
                throw ActionError::field('text', 'Escribe el texto de tu historia.');
            }
            if (mb_strlen($body) > $max) {
                throw ActionError::field('text', t('El texto de la historia no puede superar los {n} caracteres.', ['n' => $max]));
            }
            if (!isset(Story::BACKGROUNDS[$background])) {
                $background = 'violet';
            }
            RateLimit::hit('story_create', $rateKey);
        } else {
            $background = null;
            $body = Guard::cleanText($caption);
            $max = (int) Config::get('app.limits.story_caption', 200);
            if (mb_strlen($body) > $max) {
                throw ActionError::field('caption', t('La descripción no puede superar los {n} caracteres.', ['n' => $max]));
            }
            if (count($files) !== 1) {
                throw ActionError::field('media', $files === [] ? 'Elige una foto o un video para tu historia.' : 'Una historia lleva un solo archivo.');
            }
            RateLimit::hit('story_create', $rateKey);
            try {
                $media = MediaUpload::storeStoryMedia($files[0]);
            } catch (RuntimeException $e) {
                throw ActionError::field('media', $e->getMessage());
            }
        }

        try {
            $storyId = Story::create($uid, $media, $body !== '' ? $body : null, $background, $song,
                $layers['items'], $media !== null ? StoryOverlays::filter($filter) : null);
        } catch (Throwable $e) {
            MediaUpload::delete($media['path'] ?? null);
            throw $e;
        }
        // Solo reciben el aviso las personas mencionadas que pueden ver la historia.
        foreach ($layers['mentions'] as $mentionedId) {
            if (Story::findVisible($storyId, $mentionedId) !== null) {
                Notification::notify($mentionedId, $uid, 'story_mention');
            }
        }
        ProfileAlert::fire('new_story', $uid, $storyId);
        Story::purgeExpired(50);
        return $storyId;
    }

    /**
     * Voto en la encuesta de una historia (0 = primera opción, 1 = segunda). Un voto por persona y no se cambia.
     *
     * @return array{counts: list<int>, total: int, viewer_choice: int}
     */
    public static function vote(int $uid, int $storyId, int $choice): array
    {
        $story = $storyId > 0 ? Story::findVisible($storyId, $uid) : null;
        if ($story === null) {
            throw new ActionError('Esta historia ya no está disponible.', 404);
        }
        $hasPoll = array_filter(Story::decodeOverlays($story['overlays'] ?? null), static fn (array $o): bool => $o['type'] === 'poll') !== [];
        if (!$hasPoll) {
            throw new ActionError('Esta historia no tiene encuesta.', 404);
        }
        if ((int) $story['user_id'] === $uid) {
            throw new ActionError('No puedes votar en tu propia encuesta.', 403);
        }
        if ($choice !== 0 && $choice !== 1) {
            throw ActionError::field('choice', 'Elige una de las dos opciones.');
        }
        Guard::rateLimit('interaction', 'user:' . $uid, 'Vas muy rápido. Espera {min} min.');
        RateLimit::hit('interaction', 'user:' . $uid);
        Story::vote($storyId, $uid, $choice);
        $result = Story::pollResults([$storyId], $uid)[$storyId];
        return ['counts' => $result['counts'], 'total' => $result['total'], 'viewer_choice' => (int) $result['viewer_choice']];
    }

    /** Borra una historia propia. Devuelve true si a la cuenta le quedan historias activas. */
    public static function delete(int $uid, int $storyId): bool
    {
        $story = $storyId > 0 ? Story::findOwn($storyId, $uid) : null;
        if ($story === null) {
            throw new ActionError('No encontramos esa historia entre las tuyas.', 404);
        }
        Story::delete($story);
        return Story::ringFor($uid, $uid) !== null;
    }
}
