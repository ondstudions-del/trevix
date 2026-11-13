<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Models\Playlist;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\User;

/**
 * Listas de reproducción de reels (compartido por la web y la API). Solo las cuentas de creador de contenido
 * crean listas, y solo con sus propios videos.
 */
final class PlaylistService
{
    public const MAX_LISTS = 50;
    public const MAX_ITEMS = 300;
    public const TITLE_MAX = 80;
    public const DESCRIPTION_MAX = 300;

    public static function create(array $user, string $title, string $description): int
    {
        self::assertCreator($user);
        $uid = (int) $user['id'];
        self::throttle($uid);
        [$title, $description] = self::clean($title, $description);
        if (Playlist::countForUser($uid) >= self::MAX_LISTS) {
            throw new ActionError(t('Puedes tener hasta {n} listas de reproducción.', ['n' => self::MAX_LISTS]));
        }
        RateLimit::hit('playlist_action', 'user:' . $uid);
        return Playlist::create($uid, $title, $description);
    }

    public static function update(array $user, int $id, string $title, string $description): void
    {
        $list = self::own($user, $id);
        self::throttle((int) $user['id']);
        [$title, $description] = self::clean($title, $description);
        RateLimit::hit('playlist_action', 'user:' . (int) $user['id']);
        Playlist::update($list['id'], $title, $description);
    }

    public static function delete(array $user, int $id): void
    {
        $list = self::own($user, $id, false);
        Playlist::delete($list['id']);
    }

    /** Agrega un video propio al final de la lista. Devuelve false si ya estaba. */
    public static function addPost(array $user, int $id, int $postId): bool
    {
        $list = self::own($user, $id);
        $uid = (int) $user['id'];
        self::throttle($uid);
        $post = $postId > 0 ? Post::findVisible($postId, $uid) : null;
        if ($post === null || (int) $post['user']['id'] !== $uid) {
            throw new ActionError('Solo puedes agregar tus propias publicaciones.', 404);
        }
        if (array_filter($post['media'], static fn (array $m): bool => $m['type'] === 'video') === []) {
            throw new ActionError('Las listas de reproducción son de videos (reels).');
        }
        if (Playlist::itemCount($list['id']) >= self::MAX_ITEMS) {
            throw new ActionError(t('Una lista puede tener hasta {n} videos.', ['n' => self::MAX_ITEMS]));
        }
        RateLimit::hit('playlist_action', 'user:' . $uid);
        return Playlist::addPost($list['id'], $postId);
    }

    public static function removePost(array $user, int $id, int $postId): void
    {
        $list = self::own($user, $id, false);
        Playlist::removePost($list['id'], $postId);
    }

    /** Lista propia; $creatorOnly = false deja ordenar o borrar lo que quedó si la cuenta dejó de ser de creador. */
    private static function own(array $user, int $id, bool $creatorOnly = true): array
    {
        if ($creatorOnly) {
            self::assertCreator($user);
        }
        $list = $id > 0 ? Playlist::find($id) : null;
        if ($list === null || $list['user_id'] !== (int) $user['id']) {
            throw new ActionError('Esta lista de reproducción no existe.', 404);
        }
        return $list;
    }

    private static function assertCreator(array $user): void
    {
        if (!User::isCreator($user)) {
            throw new ActionError('Las listas de reproducción son para cuentas de creador de contenido. Actívalo en Configuración › Cuenta.', 403);
        }
    }

    private static function throttle(int $uid): void
    {
        Guard::rateLimit('playlist_action', 'user:' . $uid, 'Hiciste muchos cambios seguidos en tus listas. Inténtalo de nuevo en {min} min.');
    }

    /** @return array{0:string, 1:?string} */
    private static function clean(string $title, string $description): array
    {
        $title = Guard::singleLine($title, 1000) ?? '';
        if ($title === '') {
            throw ActionError::field('title', 'Ponle un nombre a la lista.');
        }
        if (mb_strlen($title) > self::TITLE_MAX) {
            throw ActionError::field('title', t('El nombre no puede superar los {n} caracteres.', ['n' => self::TITLE_MAX]));
        }
        $description = Guard::cleanText($description);
        if (mb_strlen($description) > self::DESCRIPTION_MAX) {
            throw ActionError::field('description', t('La descripción no puede superar los {n} caracteres.', ['n' => self::DESCRIPTION_MAX]));
        }
        return [$title, $description !== '' ? $description : null];
    }
}
