<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Community;
use Trevix\Models\Event;
use Trevix\Models\Interaction;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\Story;

/** Crear, editar y eliminar publicaciones, y me gusta / guardados (compartido por la web y la API). */
final class PostService
{
    private const THREAD_ONLY = 'Los hilos solo llevan texto e imágenes.';

    /**
     * @param array{format?:string, visibility?:string, community_id?:int, shared_post_id?:int, body?:string} $input
     * @param list<array> $files archivos de MediaUpload::collect
     * @return array{id:int, format:string, community_id:?int, shared_id:?int}
     */
    public static function create(array $user, array $input, array $files): array
    {
        $uid = (int) $user['id'];
        $rateKey = 'user:' . $uid;
        Guard::verifiedEmail($user);
        Guard::rateLimit('post_create', $rateKey, 'Publicaste muchas veces seguidas. Inténtalo de nuevo en {min} min.');

        $format = (string) ($input['format'] ?? '');
        $format = in_array($format, Post::FORMATS, true) ? $format : 'post';
        $visibility = (string) ($input['visibility'] ?? '') ?: 'public';
        if (!isset(Post::VISIBILITIES[$visibility])) {
            throw ActionError::field('visibility', 'Elige una visibilidad válida.');
        }
        $sharedParam = (int) ($input['shared_post_id'] ?? 0);

        // En una comunidad la visibilidad la decide la comunidad: la publicación se guarda como pública.
        $communityId = null;
        $communityParam = (int) ($input['community_id'] ?? 0);
        if ($communityParam > 0) {
            $community = Community::find($communityParam, $uid);
            if ($community === null || ($community['membership']['status'] ?? '') !== 'active') {
                throw new ActionError('Para publicar en esta comunidad tienes que ser miembro.', 403);
            }
            if ($sharedParam > 0) {
                throw new ActionError('No se pueden compartir publicaciones dentro de una comunidad.');
            }
            $communityId = $community['id'];
            $visibility = 'public';
        }

        $body = Guard::cleanText((string) ($input['body'] ?? ''));
        $maxBody = (int) Config::get('app.limits.post_body');
        if (mb_strlen($body) > $maxBody) {
            throw ActionError::field('body', 'El texto no puede superar los ' . $maxBody . ' caracteres.');
        }

        $sharedId = null;
        $songParam = (int) ($input['song_id'] ?? 0);
        if ($sharedParam > 0) {
            $sharedId = self::resolveShareTarget($sharedParam, $uid);
            if ($files !== []) {
                throw ActionError::field('media', 'Al compartir una publicación no se pueden adjuntar archivos.');
            }
            if ($songParam > 0) {
                throw ActionError::field('song_id', 'Al compartir una publicación no se puede añadir música.');
            }
            $format = 'post';
        }
        if ($format === 'thread' && $songParam > 0) {
            throw ActionError::field('song_id', self::THREAD_ONLY);
        }
        $song = $songParam > 0 ? MusicService::resolveForUse($songParam, (int) ($input['song_start'] ?? 0), $uid) : null;
        $extras = self::extras($input, $format, $files, $sharedId !== null);

        if ($format === 'thread' && $body === '') {
            throw ActionError::field('body', 'Escribe el texto del hilo.');
        }
        if ($body === '' && $files === [] && $sharedId === null && $song === null && $extras['gif'] === null
            && $extras['event'] === null && $extras['life_event'] === null) {
            throw ActionError::field('body', 'Escribe algo o adjunta una imagen, un video, un GIF o una canción.');
        }

        RateLimit::hit('post_create', $rateKey);

        try {
            $media = MediaUpload::storeAll($files, MediaUpload::collect('poster')[0] ?? null, $format === 'thread');
        } catch (RuntimeException $e) {
            throw ActionError::field('media', $e->getMessage());
        }

        $cover = null;
        $eventId = null;
        try {
            if ($extras['event'] !== null) {
                try {
                    $cover = ImageUpload::storeProfileImage('event_cover', 'event_cover');
                } catch (RuntimeException $e) {
                    throw ActionError::field('event_cover', $e->getMessage());
                }
                $eventId = Event::create($uid, $extras['event'] + ['cover_path' => $cover]);
            }
            $postId = Post::create($uid, $format, $body !== '' ? $body : null, $visibility, $media, $sharedId, $communityId, $song, [
                'background' => $extras['background'],
                'life_event' => $extras['life_event'],
                'location'   => $extras['location'],
                'gif'        => $extras['gif'],
                'event_id'   => $eventId,
            ]);
        } catch (Throwable $e) {
            foreach ($media as $item) {
                MediaUpload::delete($item['path']);
            }
            if ($eventId !== null) {
                Event::delete($eventId);
            }
            ImageUpload::delete($cover);
            throw $e;
        }
        self::notifyNewPost($uid, $postId, $body, $sharedId);

        return ['id' => $postId, 'format' => $format, 'community_id' => $communityId, 'shared_id' => $sharedId];
    }

    /**
     * Lugar, fondo de color (hilos), GIF, acontecimiento importante y evento enviados al publicar, ya validados.
     *
     * @return array{background:?string, life_event:?string, location:?array, gif:?array, event:?array}
     */
    private static function extras(array $input, string $format, array $files, bool $isShare): array
    {
        $errors = [];
        $out = ['background' => null, 'life_event' => null, 'location' => null, 'gif' => null, 'event' => null];

        if ($format === 'thread') {
            $event = $input['event'] ?? null;
            $postOnly = [
                'life_event'    => trim((string) ($input['life_event'] ?? '')) !== '',
                'location_name' => trim((string) ($input['location_name'] ?? '')) !== '',
                'gif'           => trim((string) ($input['gif_id'] ?? '')) !== '',
                'event'         => is_array($event) && trim((string) ($event['title'] ?? '')) !== '',
            ];
            foreach (array_keys(array_filter($postOnly)) as $field) {
                $errors[$field] = self::THREAD_ONLY;
            }
            if ($errors !== []) {
                throw ActionError::fields($errors);
            }
        }

        $background = trim((string) ($input['background'] ?? ''));
        if ($background !== '') {
            if ($format !== 'thread') {
                $errors['background'] = 'El fondo de color es para hilos.';
            } elseif (!isset(Story::BACKGROUNDS[$background])) {
                $errors['background'] = 'Elige un fondo válido.';
            } elseif ($files !== []) {
                $errors['background'] = 'Un hilo con fondo de color no lleva fotos ni videos.';
            } else {
                $out['background'] = $background;
            }
        }

        $lifeEvent = trim((string) ($input['life_event'] ?? ''));
        if ($lifeEvent !== '') {
            if (!isset(Post::LIFE_EVENTS[$lifeEvent])) {
                $errors['life_event'] = 'Elige un acontecimiento de la lista.';
            } else {
                $out['life_event'] = $lifeEvent;
            }
        }

        $place = Guard::cleanText((string) ($input['location_name'] ?? ''));
        if ($place !== '') {
            $lat = $input['location_lat'] ?? null;
            $lng = $input['location_lng'] ?? null;
            $hasCoords = is_numeric($lat) && is_numeric($lng);
            if (mb_strlen($place) > 120) {
                $errors['location_name'] = 'El nombre del lugar no puede superar los 120 caracteres.';
            } elseif ($hasCoords && (abs((float) $lat) > 90 || abs((float) $lng) > 180)) {
                $errors['location_name'] = 'La ubicación no es válida.';
            } else {
                // Coordenadas redondeadas a ~100 m: muestran la zona sin revelar la dirección exacta.
                $out['location'] = [
                    'name' => $place,
                    'lat'  => $hasCoords ? round((float) $lat, 3) : null,
                    'lng'  => $hasCoords ? round((float) $lng, 3) : null,
                ];
            }
        }

        $gifId = trim((string) ($input['gif_id'] ?? ''));
        if ($gifId !== '') {
            if ($files !== [] || $isShare) {
                $errors['gif'] = 'Un GIF se publica sin fotos ni videos.';
            } else {
                $out['gif'] = Giphy::resolve($gifId, (string) ($input['gif_kind'] ?? 'gif'));
            }
        }

        $event = $input['event'] ?? null;
        if (is_array($event) && trim((string) ($event['title'] ?? '')) !== '') {
            if ($isShare || $files !== [] || $out['gif'] !== null) {
                $errors['event'] = 'Un evento se publica con su portada, sin otros archivos.';
            } else {
                [$out['event'], $eventErrors] = self::eventFields($event);
                $errors += $eventErrors;
            }
        }

        if ($errors !== []) {
            throw ActionError::fields($errors);
        }
        return $out;
    }

    /** @return array{0: ?array, 1: array<string, string>} datos del evento y errores por campo */
    private static function eventFields(array $event): array
    {
        $errors = [];
        $title = Guard::cleanText((string) ($event['title'] ?? ''));
        $place = Guard::cleanText((string) ($event['place'] ?? ''));
        $description = Guard::cleanText((string) ($event['description'] ?? ''));
        $starts = self::parseDateTime((string) ($event['starts_at'] ?? ''));
        $endsRaw = trim((string) ($event['ends_at'] ?? ''));
        $ends = $endsRaw !== '' ? self::parseDateTime($endsRaw) : null;

        if (mb_strlen($title) < 3 || mb_strlen($title) > 120) {
            $errors['event_title'] = 'El nombre del evento debe tener entre 3 y 120 caracteres.';
        }
        if (mb_strlen($place) < 2 || mb_strlen($place) > 160) {
            $errors['event_place'] = 'Indica el lugar (hasta 160 caracteres).';
        }
        if (mb_strlen($description) > 2000) {
            $errors['event_description'] = 'La descripción no puede superar los 2000 caracteres.';
        }
        if ($starts === null) {
            $errors['event_starts_at'] = 'Indica la fecha y la hora de inicio.';
        } elseif ($starts < new \DateTimeImmutable('-1 hour')) {
            $errors['event_starts_at'] = 'La fecha de inicio ya pasó.';
        } elseif ($starts > new \DateTimeImmutable('+3 years')) {
            $errors['event_starts_at'] = 'La fecha de inicio es demasiado lejana.';
        }
        if ($endsRaw !== '' && ($ends === null || ($starts !== null && $ends <= $starts))) {
            $errors['event_ends_at'] = 'La hora de fin debe ser posterior al inicio.';
        }
        if ($errors !== []) {
            return [null, $errors];
        }
        return [[
            'title'       => $title,
            'place'       => $place,
            'description' => $description !== '' ? $description : null,
            'starts_at'   => $starts->format('Y-m-d H:i:s'),
            'ends_at'     => $ends?->format('Y-m-d H:i:s'),
        ], []];
    }

    /** Fecha y hora de un <input type="datetime-local"> o ISO 8601 (app), en la zona horaria de TREVIX. */
    private static function parseDateTime(string $value): ?\DateTimeImmutable
    {
        $value = trim($value);
        if ($value === '' || strlen($value) > 40) {
            return null;
        }
        foreach (['Y-m-d\TH:i', 'Y-m-d\TH:i:s', 'Y-m-d H:i', 'Y-m-d H:i:s'] as $format) {
            $date = \DateTimeImmutable::createFromFormat('!' . $format, $value);
            if ($date !== false && $date->format($format) === $value) {
                return $date;
            }
        }
        try {
            $date = new \DateTimeImmutable($value);
        } catch (\Exception) {
            return null;
        }
        return preg_match('/^\d{4}-\d{2}-\d{2}T/', $value) ? $date->setTimezone(new \DateTimeZone(date_default_timezone_get())) : null;
    }

    /**
     * Edita texto, visibilidad y canción de una publicación propia ya cargada con Post::findVisible.
     * $song: null = no tocar la canción; ['id' => 0] = quitarla; ['id' => N, 'start' => S] = ponerla o cambiarla.
     * Devuelve true si algo cambió.
     *
     * @param array{id:int, start?:int}|null $song
     */
    public static function update(array $post, string $body, string $visibility, ?array $song = null): bool
    {
        $body = Guard::cleanText($body);
        $visibility = $post['community'] !== null ? 'public' : $visibility;
        $maxBody = (int) Config::get('app.limits.post_body');
        $current = $post['song'] ?? null;

        $songChanged = false;
        $newSong = null;
        if ($song !== null) {
            $songId = (int) ($song['id'] ?? 0);
            $start = (int) ($song['start'] ?? 0);
            if ($songId <= 0) {
                $songChanged = $current !== null;
            } elseif ($current === null || $songId !== (int) $current['id'] || $start !== (int) $current['start']) {
                if ($post['shared'] !== null || $post['shared_missing']) {
                    throw ActionError::field('song_id', 'No se puede añadir música a una publicación compartida.');
                }
                if ($post['format'] === 'thread') {
                    throw ActionError::field('song_id', self::THREAD_ONLY);
                }
                $newSong = MusicService::resolveForUse($songId, $start, (int) $post['user']['id']);
                $songChanged = $current === null || $newSong['id'] !== (int) $current['id'] || $newSong['start'] !== (int) $current['start'];
            }
        }
        $hasSong = $songChanged ? $newSong !== null : $current !== null;

        $errors = [];
        if (!isset(Post::VISIBILITIES[$visibility])) {
            $errors['visibility'] = 'Elige una visibilidad válida.';
        }
        if (mb_strlen($body) > $maxBody) {
            $errors['body'] = 'El texto no puede superar los ' . $maxBody . ' caracteres.';
        } elseif ($body === '' && $post['format'] === 'thread') {
            $errors['body'] = 'Un hilo necesita texto.';
        } elseif ($body === '' && $post['media'] === [] && $post['shared'] === null && !$post['shared_missing'] && !$hasSong) {
            $errors['body'] = 'Escribe algo: la publicación no tiene archivos adjuntos ni música.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        if ($body === $post['body'] && $visibility === $post['visibility'] && !$songChanged) {
            return false;
        }
        $isNewUse = $newSong !== null && ($current === null || $newSong['id'] !== (int) $current['id']);
        Post::update((int) $post['id'], $body !== '' ? $body : null, $visibility, $songChanged, $newSong, $isNewUse);
        Notification::notifyMentions((int) $post['user']['id'], $body, (int) $post['id'], null, [], Mentions::extract($post['body']));
        return true;
    }

    /** Publicación propia y publicada, lista para editar; si no, 404. */
    public static function findOwnEditable(int $postId, int $uid): array
    {
        $raw = $postId > 0 ? Post::findRaw($postId) : null;
        $post = $raw !== null && (int) $raw['user_id'] === $uid && $raw['status'] === 'published' ? Post::findVisible($postId, $uid) : null;
        if ($post === null) {
            throw new ActionError('No encontramos esa publicación entre las tuyas.', 404);
        }
        return $post;
    }

    public static function delete(int $uid, int $postId): void
    {
        $post = $postId > 0 ? Post::findRaw($postId) : null;
        if ($post === null || (int) $post['user_id'] !== $uid) {
            throw new ActionError('No puedes eliminar esta publicación.', 403);
        }
        Post::delete($post);
    }

    /**
     * Me gusta o guardado. Con $active = null alterna; con true / false deja ese estado (la API).
     *
     * @return array{active: bool, count: int}
     */
    public static function interact(string $kind, int $uid, int $postId, ?bool $active = null): array
    {
        $rateKey = 'user:' . $uid;
        Guard::rateLimit('interaction', $rateKey, 'Vas demasiado rápido. Espera un momento.');
        $post = $postId > 0 ? Post::findVisible($postId, $uid) : null;
        if ($post === null) {
            throw new ActionError('Esta publicación ya no está disponible.', 404);
        }

        $current = $kind === 'like' ? (bool) $post['viewer_liked'] : (bool) $post['viewer_saved'];
        if ($active !== null && $active === $current) {
            return ['active' => $current, 'count' => (int) ($kind === 'like' ? $post['likes_count'] : $post['saves_count'])];
        }

        RateLimit::hit('interaction', $rateKey);
        $result = Interaction::toggle($kind, $uid, $postId);
        if ($kind === 'like') {
            $ownerId = (int) $post['user']['id'];
            $result['active']
                ? Notification::notify($ownerId, $uid, 'like', $postId)
                : Notification::remove($ownerId, $uid, 'like', $postId);
        }
        return $result;
    }

    /**
     * Solo se comparten publicaciones públicas y visibles. Si el objetivo ya es un "compartido",
     * se comparte la publicación original para no anidar citas.
     */
    private static function resolveShareTarget(int $postId, int $uid): int
    {
        $target = Post::findVisible($postId, $uid);
        if ($target !== null && $target['shared'] !== null && $target['body'] === '' && $target['media'] === []) {
            $target = $target['shared'];
        }
        if ($target === null || !empty($target['shared_missing'])) {
            throw new ActionError('La publicación que intentas compartir ya no está disponible.', 404);
        }
        if ($target['visibility'] !== 'public') {
            throw new ActionError('Solo se pueden compartir publicaciones públicas.');
        }
        if (($target['community']['visibility'] ?? 'public') === 'private') {
            throw new ActionError('Las publicaciones de comunidades privadas no se pueden compartir.');
        }
        return (int) $target['id'];
    }

    /** Avisa al autor de la publicación compartida (si puede ver el compartido) y a los mencionados. */
    private static function notifyNewPost(int $uid, int $postId, string $body, ?int $sharedId): void
    {
        $notified = [];
        if ($sharedId !== null) {
            $original = Post::findRaw($sharedId);
            $ownerId = $original !== null ? (int) $original['user_id'] : 0;
            if ($ownerId > 0 && Post::findVisible($postId, $ownerId) !== null && Notification::notify($ownerId, $uid, 'share', $postId)) {
                $notified[] = $ownerId;
            }
        }
        Notification::notifyMentions($uid, $body, $postId, null, $notified);
    }
}
