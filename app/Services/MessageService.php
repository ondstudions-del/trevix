<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Conversation;
use Trevix\Models\Message;
use Trevix\Models\RateLimit;
use Trevix\Models\Story;
use Trevix\Models\User;

/** Enviar mensajes privados, responder historias y borrar mensajes (compartido por la web y la API). */
final class MessageService
{
    /**
     * Envía a una conversación existente ($conversationId) o a una persona por su usuario ($to).
     * Un mensaje lleva texto y, como mucho, un adjunto: una imagen, una nota de voz o un GIF/sticker de GIPHY.
     *
     * @param list<array> $files imagen adjunta de MediaUpload::collect('image') (como máximo una)
     * @param list<array> $voice nota de voz de MediaUpload::collect('voice') (como máximo una)
     * @param array{id?:string, kind?:string} $gif GIF elegido (id de GIPHY y tipo gif|sticker)
     * @return array{0:int, 1:int} [conversación, mensaje]
     */
    public static function send(array $user, ?int $conversationId, string $to, string $body, array $files, array $voice = [], array $gif = []): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);

        if ($conversationId !== null) {
            $conversation = Conversation::findFor($conversationId, $uid);
            if ($conversation === null || !$conversation['available']) {
                throw new ActionError('Esta conversación ya no está disponible.', 404);
            }
            $recipient = User::findByUsername((string) $conversation['user']['username']);
        } else {
            $recipient = User::findByUsername(mb_strtolower(trim(ltrim(trim($to), '@'))));
            if ($recipient !== null) {
                $conversationId = Conversation::findDirectId($uid, (int) $recipient['id']);
            }
        }

        $reason = Conversation::cannotMessage($uid, $recipient, $conversationId);
        if ($reason !== null) {
            throw new ActionError($reason, 403);
        }

        $rateKey = 'user:' . $uid;
        Guard::rateLimit('message_send', $rateKey, 'Enviaste muchos mensajes seguidos. Espera un momento.');

        $body = Guard::cleanText($body);
        $max = (int) Config::get('app.limits.message_body', 2000);
        if (mb_strlen($body) > $max) {
            throw ActionError::field('body', 'El mensaje no puede superar los ' . $max . ' caracteres.');
        }
        if (count($files) > 1) {
            throw ActionError::field('image', 'Puedes enviar una imagen por mensaje.');
        }
        if (count($voice) > 1) {
            throw ActionError::field('voice', 'Puedes enviar una nota de voz por mensaje.');
        }
        $gifId = trim((string) ($gif['id'] ?? ''));
        if (count(array_filter([$files !== [], $voice !== [], $gifId !== ''])) > 1) {
            throw ActionError::field('body', 'Envía la imagen, la nota de voz o el GIF en mensajes separados.');
        }
        if ($body === '' && $files === [] && $voice === [] && $gifId === '') {
            throw ActionError::field('body', 'Escribe un mensaje o adjunta una imagen, una nota de voz o un GIF.');
        }
        $gifRow = Giphy::resolve($gifId, (string) ($gif['kind'] ?? 'gif'));

        RateLimit::hit('message_send', $rateKey);
        $media = null;
        if ($files !== []) {
            try {
                $media = MediaUpload::storeMessageImage($files[0]);
            } catch (RuntimeException $e) {
                throw ActionError::field('image', $e->getMessage());
            }
        } elseif ($voice !== []) {
            try {
                $media = VoiceUpload::store($voice[0]);
            } catch (RuntimeException $e) {
                throw ActionError::field('voice', $e->getMessage());
            }
        }

        try {
            return Conversation::send($uid, (int) $recipient['id'], $conversationId, $body !== '' ? $body : null, $media, null, null, $gifRow);
        } catch (Throwable $e) {
            MediaUpload::delete($media['path'] ?? null);
            throw $e;
        }
    }

    /**
     * Responder a una historia envía un mensaje privado a su autor, con las mismas reglas que el chat.
     *
     * @return array{conversation_id:int, message_id:int, story:array}
     */
    public static function replyToStory(array $user, int $storyId, string $body): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $story = $storyId > 0 ? Story::findVisible($storyId, $uid) : null;
        if ($story === null) {
            throw new ActionError('Esta historia ya no está disponible.', 404);
        }
        $authorId = (int) $story['user_id'];
        if ($authorId === $uid) {
            throw new ActionError('No puedes responder a tu propia historia.');
        }

        $body = Guard::cleanText($body);
        $max = (int) Config::get('app.limits.message_body', 2000);
        if ($body === '') {
            throw ActionError::field('body', 'Escribe tu respuesta.');
        }
        if (mb_strlen($body) > $max) {
            throw ActionError::field('body', 'La respuesta no puede superar los ' . $max . ' caracteres.');
        }

        $conversationId = Conversation::findDirectId($uid, $authorId);
        $reason = Conversation::cannotMessage($uid, User::findActiveById($authorId), $conversationId);
        if ($reason !== null) {
            throw new ActionError($reason, 403);
        }
        $rateKey = 'user:' . $uid;
        Guard::rateLimit('message_send', $rateKey, 'Enviaste muchos mensajes seguidos. Espera un momento.');
        RateLimit::hit('message_send', $rateKey);

        [$conversationId, $messageId] = Conversation::send($uid, $authorId, $conversationId, $body, null, (int) $story['id']);
        return ['conversation_id' => $conversationId, 'message_id' => $messageId, 'story' => $story];
    }

    /** Borra un mensaje propio (queda como "mensaje eliminado"). Devuelve el mensaje actualizado. */
    public static function delete(int $uid, int $messageId): array
    {
        $message = $messageId > 0 ? Message::find($messageId) : null;
        if ($message === null || Conversation::findFor((int) $message['conversation_id'], $uid) === null || !Message::deleteOwn($messageId, $uid)) {
            throw new ActionError('No puedes eliminar este mensaje.', 403);
        }
        return Message::find($messageId) ?? $message;
    }
}
