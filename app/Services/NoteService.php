<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Block;
use Trevix\Models\Follow;
use Trevix\Models\Note;
use Trevix\Models\RateLimit;
use Trevix\Models\User;

/** Publicar y borrar la nota de 6 horas y armar la lista de mejores amigos (su público más reducido). */
final class NoteService
{
    /** Publica la nota (reemplaza la anterior) y la devuelve. */
    public static function publish(array $user, string $body, string $audience): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $body = trim((string) preg_replace('/\s+/u', ' ', Guard::cleanText($body)));
        $max = (int) Config::get('app.notes.max_length', 60);
        if ($body === '') {
            throw ActionError::field('body', 'Escribe tu nota.');
        }
        if (mb_strlen($body) > $max) {
            throw ActionError::field('body', 'La nota puede tener hasta ' . $max . ' caracteres.');
        }
        if (!isset(Note::AUDIENCES[$audience])) {
            throw ActionError::field('audience', 'Elige quién puede ver tu nota.');
        }
        if ($audience === 'close_friends' && Note::closeFriendsCount($uid) === 0) {
            throw ActionError::field('audience', 'Agrega al menos una persona a tu lista de mejores amigos.');
        }
        self::hit('note_create', $uid, 'Cambiaste tu nota muchas veces. Espera {min} min.');
        Note::publish($uid, $body, $audience);
        return Note::current($uid) ?? throw new ActionError('No pudimos publicar tu nota.', 500);
    }

    public static function remove(int $uid): void
    {
        if (!Note::remove($uid)) {
            throw new ActionError('No tienes una nota activa.', 404);
        }
    }

    /** Solo tus seguidores o las cuentas que sigues (activas y sin bloqueo) pueden estar en tu lista. */
    public static function addCloseFriend(int $uid, int $friendId): void
    {
        $friend = $friendId > 0 && $friendId !== $uid ? User::findActiveById($friendId) : null;
        if ($friend === null || Block::exists($uid, $friendId) || Block::exists($friendId, $uid)) {
            throw new ActionError('Esta cuenta no está disponible.', 404);
        }
        $relation = Follow::relation($uid, $friendId);
        if (!$relation['following'] && !$relation['follows_you']) {
            throw new ActionError('Solo puedes agregar a personas que sigues o que te siguen.');
        }
        if (Note::isCloseFriend($uid, $friendId)) {
            return;
        }
        $max = (int) Config::get('app.notes.close_friends_max', 200);
        if (Note::closeFriendsCount($uid) >= $max) {
            throw new ActionError('Tu lista de mejores amigos puede tener hasta ' . $max . ' personas.');
        }
        self::hit('close_friends', $uid, 'Hiciste muchos cambios en tu lista. Espera {min} min.');
        Note::addCloseFriend($uid, $friendId);
    }

    public static function removeCloseFriend(int $uid, int $friendId): void
    {
        self::hit('close_friends', $uid, 'Hiciste muchos cambios en tu lista. Espera {min} min.');
        Note::removeCloseFriend($uid, $friendId);
    }

    private static function hit(string $action, int $uid, string $message): void
    {
        $key = 'user:' . $uid;
        Guard::rateLimit($action, $key, $message);
        RateLimit::hit($action, $key);
    }
}
