<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Community;
use Trevix\Models\Interaction;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;

/** Crear, editar y eliminar publicaciones, y me gusta / guardados (compartido por la web y la API). */
final class PostService
{
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
        $song = $songParam > 0 ? MusicService::resolveForUse($songParam, (int) ($input['song_start'] ?? 0), $uid) : null;

        if ($format === 'thread' && $body === '') {
            throw ActionError::field('body', 'Escribe el texto del hilo.');
        }
        if ($body === '' && $files === [] && $sharedId === null && $song === null) {
            throw ActionError::field('body', 'Escribe algo o adjunta una imagen, un video o una canción.');
        }

        RateLimit::hit('post_create', $rateKey);

        try {
            $media = MediaUpload::storeAll($files);
        } catch (RuntimeException $e) {
            throw ActionError::field('media', $e->getMessage());
        }

        try {
            $postId = Post::create($uid, $format, $body !== '' ? $body : null, $visibility, $media, $sharedId, $communityId, $song);
        } catch (Throwable $e) {
            foreach ($media as $item) {
                MediaUpload::delete($item['path']);
            }
            throw $e;
        }
        self::notifyNewPost($uid, $postId, $body, $sharedId);

        return ['id' => $postId, 'format' => $format, 'community_id' => $communityId, 'shared_id' => $sharedId];
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
