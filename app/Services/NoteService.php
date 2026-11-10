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
    /**
     * Publica la nota (reemplaza la anterior) y la devuelve. Lleva texto, un sticker de GIPHY ($stickerId) y/o un
     * fragmento de una canción de la biblioteca ($songId desde $songStart); al menos uno de los tres.
     */
    public static function publish(array $user, string $body, string $audience, string $stickerId = '', int $songId = 0, int $songStart = 0): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $body = trim((string) preg_replace('/\s+/u', ' ', Guard::cleanText($body)));
        $stickerId = trim($stickerId);
        $max = (int) Config::get('app.notes.max_length', 60);
        if ($body === '' && $stickerId === '' && $songId <= 0) {
            throw ActionError::field('body', 'Escribe tu nota o agrega un sticker o una canción.');
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
        $song = $songId > 0 ? MusicService::resolveForUse($songId, $songStart, $uid) : null;
        $sticker = null;
        if ($stickerId !== '') {
            $sticker = Giphy::resolve($stickerId, 'sticker');
            if ($sticker === null) {
                throw ActionError::field('sticker_id', 'Ese sticker ya no está disponible. Elige otro.');
            }
        }
        self::hit('note_create', $uid, 'Cambiaste tu nota muchas veces. Espera {min} min.');
        Note::publish($uid, $body, $audience, $sticker, $song);
        return Note::current($uid) ?? throw new ActionError('No pudimos publicar tu nota.', 500);
    }

    /** Me gusta en una nota visible de otra persona. Devuelve la nota actualizada. */
    public static function like(int $uid, int $noteId, bool $liked): array
    {
        $note = $noteId > 0 ? Note::findVisible($noteId, $uid) : null;
        if ($note === null) {
            throw new ActionError('Esta nota ya no está disponible.', 404);
        }
        if ((int) $note['user_id'] === $uid) {
            throw new ActionError('No puedes darle me gusta a tu propia nota.');
        }
        self::hit('note_like', $uid, 'Hiciste muchos cambios seguidos. Espera {min} min.');
        Note::setLiked($note, $uid, $liked);
        return Note::findVisible($noteId, $uid) ?? $note;
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
