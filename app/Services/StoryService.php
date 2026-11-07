<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\RateLimit;
use Trevix\Models\Story;

/** Publicar historias de texto, foto o video (compartido por la web y la API). */
final class StoryService
{
    /**
     * @param string $type text | media
     * @param list<array> $files archivo de MediaUpload::collect (exactamente uno si es media)
     * @param int $songId canción de la biblioteca (0 = sin música) y $songStart, el segundo en que empieza
     */
    public static function create(array $user, string $type, string $text, string $caption, string $background, array $files, int $songId = 0, int $songStart = 0): int
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $rateKey = 'user:' . $uid;
        Guard::rateLimit('story_create', $rateKey, 'Publicaste muchas historias seguidas. Inténtalo de nuevo en {min} min.');

        $song = $songId > 0 ? MusicService::resolveForUse($songId, $songStart, $uid) : null;
        $media = null;
        if ($type === 'text') {
            $body = Guard::cleanText($text);
            $max = (int) Config::get('app.limits.story_text', 300);
            if ($body === '') {
                throw ActionError::field('text', 'Escribe el texto de tu historia.');
            }
            if (mb_strlen($body) > $max) {
                throw ActionError::field('text', 'El texto de la historia no puede superar los ' . $max . ' caracteres.');
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
                throw ActionError::field('caption', 'La descripción no puede superar los ' . $max . ' caracteres.');
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
            $storyId = Story::create($uid, $media, $body !== '' ? $body : null, $background, $song);
        } catch (Throwable $e) {
            MediaUpload::delete($media['path'] ?? null);
            throw $e;
        }
        Story::purgeExpired(50);
        return $storyId;
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
