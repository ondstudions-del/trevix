<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Conversation;
use Trevix\Models\Message;
use Trevix\Models\Note;
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
     * @param array{reply_to?:int, location?:array{lat:mixed, lng:mixed, name?:mixed}|null} $extra mensaje al que
     *        responde y ubicación (otro tipo de adjunto)
     * @return array{0:int, 1:int} [conversación, mensaje]
     */
    public static function send(array $user, ?int $conversationId, string $to, string $body, array $files, array $voice = [], array $gif = [], array $extra = []): array
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
        $location = isset($extra['location']) ? self::location($extra['location']) : null;
        if (count(array_filter([$files !== [], $voice !== [], $gifId !== '', $location !== null])) > 1) {
            throw ActionError::field('body', 'Envía la imagen, la nota de voz, el GIF o la ubicación en mensajes separados.');
        }
        if ($body === '' && $files === [] && $voice === [] && $gifId === '' && $location === null) {
            throw ActionError::field('body', 'Escribe un mensaje o adjunta una imagen, una nota de voz, un GIF o tu ubicación.');
        }
        $replyTo = (int) ($extra['reply_to'] ?? 0);
        if ($replyTo > 0) {
            $original = $conversationId !== null ? Message::findVisible($replyTo, $uid) : null;
            if ($original === null || (int) $original['conversation_id'] !== $conversationId || $original['kind'] !== 'message' || $original['deleted_at'] !== null) {
                throw ActionError::field('reply_to', 'Ese mensaje ya no está disponible para responderlo.');
            }
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
            return Conversation::send($uid, (int) $recipient['id'], $conversationId, $body !== '' ? $body : null, $media, null, null, $gifRow, [
                'reply_to_id' => $replyTo > 0 ? $replyTo : null,
                'location'    => $location,
            ]);
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

    /**
     * Reacción con un emoji a una historia ajena (null la quita). Queda en la lista de quién la vio y, si es
     * nueva o cambia y el autor acepta mensajes de quien reacciona, le llega también por mensaje privado.
     *
     * @return array{reaction: ?string, story: array, message_id: ?int}
     */
    public static function reactToStory(array $user, int $storyId, ?string $emoji): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $story = $storyId > 0 ? Story::findVisible($storyId, $uid) : null;
        if ($story === null) {
            throw new ActionError('Esta historia ya no está disponible.', 404);
        }
        $authorId = (int) $story['user_id'];
        if ($authorId === $uid) {
            throw new ActionError('No puedes reaccionar a tu propia historia.');
        }
        $emoji = $emoji !== null ? self::emoji($emoji) : null;
        self::action($uid);
        $previous = Story::reactionOf($storyId, $uid);
        Story::markViewed($story, $uid);
        Story::react($storyId, $uid, $emoji);

        $messageId = null;
        if ($emoji !== null && $emoji !== $previous) {
            $conversationId = Conversation::findDirectId($uid, $authorId);
            $rateKey = 'user:' . $uid;
            if (Conversation::cannotMessage($uid, User::findActiveById($authorId), $conversationId) === null
                && !RateLimit::tooManyAttempts('message_send', $rateKey)) {
                RateLimit::hit('message_send', $rateKey);
                [, $messageId] = Conversation::send($uid, $authorId, $conversationId, $emoji, null, $storyId, null, null, ['context' => 'story_reaction']);
            }
        }
        return ['reaction' => $emoji, 'story' => $story, 'message_id' => $messageId];
    }

    /**
     * Responder a una nota envía un mensaje privado a su autor con el texto de la nota (que caduca a las 6 horas).
     *
     * @return array{conversation_id:int, message_id:int, note:array}
     */
    public static function replyToNote(array $user, int $noteId, string $body): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $note = $noteId > 0 ? Note::findVisible($noteId, $uid) : null;
        if ($note === null) {
            throw new ActionError('Esta nota ya no está disponible.', 404);
        }
        $authorId = (int) $note['user_id'];
        if ($authorId === $uid) {
            throw new ActionError('No puedes responder a tu propia nota.');
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

        [$conversationId, $messageId] = Conversation::send($uid, $authorId, $conversationId, $body, null, null, null, null, [
            'context'   => 'note_reply',
            'note_text' => (string) $note['body'],
        ]);
        return ['conversation_id' => $conversationId, 'message_id' => $messageId, 'note' => $note];
    }

    /** Un emoji (o una secuencia de emojis, p. ej. con tono de piel) para reaccionar. */
    private static function emoji(string $emoji): string
    {
        $emoji = trim($emoji);
        if ($emoji === '' || mb_strlen($emoji) > 16 || strlen($emoji) > 32
            || !preg_match('/^[^\p{L}\p{N}\p{Z}\p{Cc}\p{P}<>]+$/u', $emoji) || !preg_match('/\p{So}/u', $emoji)) {
            throw ActionError::field('emoji', 'Elige un emoji para reaccionar.');
        }
        return $emoji;
    }

    /** Reacción con un emoji (null la quita). Una por persona y mensaje; los avisos del chat no admiten reacciones. */
    public static function react(int $uid, int $messageId, ?string $emoji): array
    {
        $message = self::usable($uid, $messageId);
        $emoji = $emoji !== null ? self::emoji($emoji) : null;
        self::action($uid);
        Message::react((int) $message['id'], $uid, $emoji);
        return Message::findFull((int) $message['id'], $uid) ?? $message;
    }

    /** «Eliminar para ti»: deja de mostrarse solo a quien lo pide (cualquier mensaje de sus conversaciones). */
    public static function hide(int $uid, int $messageId): void
    {
        $message = $messageId > 0 ? Message::findVisible($messageId, $uid) : null;
        if ($message === null || Conversation::findFor((int) $message['conversation_id'], $uid) === null) {
            throw new ActionError('Este mensaje ya no está disponible.', 404);
        }
        self::action($uid);
        Message::hideFor($messageId, $uid);
    }

    /** Fijar (true) o dejar de fijar (false) un mensaje para los dos. Como mucho app.chat.max_pins por conversación. */
    public static function pin(int $uid, int $messageId, bool $pin): array
    {
        $message = self::usable($uid, $messageId);
        $conversationId = (int) $message['conversation_id'];
        if ($pin) {
            if ($message['pinned_at'] !== null) {
                throw new ActionError('Este mensaje ya está fijado.');
            }
            $max = (int) Config::get('app.chat.max_pins', 3);
            if (Message::pinnedCount($conversationId) >= $max) {
                throw new ActionError('Puedes fijar hasta ' . $max . ' mensajes. Deja de fijar alguno primero.');
            }
        } elseif ($message['pinned_at'] === null) {
            throw new ActionError('Este mensaje no está fijado.');
        }
        self::action($uid);
        Message::setPinned((int) $message['id'], $pin ? $uid : null);
        return Message::pinned($conversationId, $uid);
    }

    /**
     * Reenvía un mensaje a varias personas (por usuario). Cada envío sigue las reglas del chat (bloqueos,
     * privacidad de mensajes y límite de envíos). La imagen o la nota de voz se copian.
     *
     * @param list<string> $usernames
     * @return array{sent: list<array{username:string, conversation_id:int}>, failed: array<string, string>}
     */
    public static function forward(array $user, int $messageId, array $usernames): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $message = self::usable($uid, $messageId);
        if ($message['body'] === null && $message['media_path'] === null && $message['gif_id'] === null && $message['location_lat'] === null) {
            throw new ActionError('Este mensaje no se puede reenviar.');
        }
        $usernames = array_values(array_unique(array_filter(array_map(
            static fn ($u) => mb_strtolower(trim(ltrim(trim((string) $u), '@'))),
            $usernames
        ))));
        $max = (int) Config::get('app.chat.max_forward', 5);
        if ($usernames === []) {
            throw ActionError::field('to', 'Elige a quién reenviarlo.');
        }
        if (count($usernames) > $max) {
            throw ActionError::field('to', 'Puedes reenviarlo a ' . $max . ' personas como máximo.');
        }
        self::action($uid);

        $gif = $message['gif_id'] !== null ? [
            'gif_id' => $message['gif_id'], 'gif_kind' => $message['gif_kind'], 'gif_url' => $message['gif_url'],
            'gif_width' => $message['gif_width'], 'gif_height' => $message['gif_height'], 'gif_title' => $message['gif_title'],
        ] : null;
        $location = $message['location_lat'] !== null
            ? ['lat' => (float) $message['location_lat'], 'lng' => (float) $message['location_lng'], 'name' => $message['location_name']]
            : null;
        $sent = [];
        $failed = [];
        $rateKey = 'user:' . $uid;
        foreach ($usernames as $username) {
            $recipient = User::findByUsername($username);
            $conversationId = $recipient !== null ? Conversation::findDirectId($uid, (int) $recipient['id']) : null;
            $reason = Conversation::cannotMessage($uid, $recipient, $conversationId);
            if ($reason === null && RateLimit::tooManyAttempts('message_send', $rateKey)) {
                $reason = 'Enviaste muchos mensajes seguidos. Espera un momento.';
            }
            if ($reason !== null) {
                $failed[$username] = $reason;
                continue;
            }
            RateLimit::hit('message_send', $rateKey);
            $media = null;
            if ($message['media_path'] !== null) {
                $media = MediaUpload::duplicate((string) $message['media_path']);
                if ($media === null) {
                    $failed[$username] = 'El archivo del mensaje ya no está disponible.';
                    continue;
                }
                $media += ['mime_type' => $message['media_mime'], 'duration' => $message['media_duration']];
            }
            try {
                [$cid] = Conversation::send($uid, (int) $recipient['id'], $conversationId, $message['body'], $media, null, null, $gif, [
                    'forwarded' => true,
                    'location'  => $location,
                ]);
                $sent[] = ['username' => $username, 'conversation_id' => $cid];
            } catch (Throwable $e) {
                MediaUpload::delete($media['path'] ?? null);
                throw $e;
            }
        }
        if ($sent === []) {
            throw new ActionError((string) reset($failed), 403);
        }
        return ['sent' => $sent, 'failed' => $failed];
    }

    /**
     * Ajustes del chat de una persona: apodo de la otra persona y fondo (solo los ve ella) y mensajes temporales
     * (para los dos). Solo cambia lo enviado.
     *
     * @param array{nickname?:?string, wallpaper?:?string, disappear_seconds?:?int} $changes
     */
    public static function updateSettings(int $uid, int $conversationId, array $changes): void
    {
        $conversation = Conversation::findFor($conversationId, $uid);
        if ($conversation === null) {
            throw new ActionError('Esta conversación no existe o no participas en ella.', 404);
        }
        $errors = [];
        if (array_key_exists('nickname', $changes)) {
            $max = (int) Config::get('app.chat.nickname_max', 40);
            $nickname = Guard::singleLine((string) ($changes['nickname'] ?? ''), 200) ?? '';
            if (mb_strlen($nickname) > $max) {
                $errors['nickname'] = 'El apodo puede tener hasta ' . $max . ' caracteres.';
            } elseif (preg_match('/[<>\p{C}]/u', $nickname)) {
                $errors['nickname'] = 'El apodo tiene caracteres no permitidos.';
            }
        }
        if (array_key_exists('wallpaper', $changes) && $changes['wallpaper'] !== null
            && !isset(((array) Config::get('app.chat.wallpapers', []))[(string) $changes['wallpaper']])) {
            $errors['wallpaper'] = 'Elige uno de los fondos disponibles.';
        }
        if (array_key_exists('disappear_seconds', $changes)) {
            if (!$conversation['available'] || $conversation['blocked']) {
                $errors['disappear_seconds'] = 'No puedes cambiar los mensajes temporales en esta conversación.';
            } elseif (!array_key_exists((int) $changes['disappear_seconds'], (array) Config::get('app.chat.disappear_options', []))) {
                $errors['disappear_seconds'] = 'Elige una de las duraciones disponibles.';
            }
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }
        self::action($uid);
        if (array_key_exists('nickname', $changes)) {
            Conversation::setPreference($conversationId, $uid, 'nickname', $nickname !== '' ? $nickname : null);
        }
        if (array_key_exists('wallpaper', $changes)) {
            $wallpaper = (string) ($changes['wallpaper'] ?? 'default');
            Conversation::setPreference($conversationId, $uid, 'wallpaper', $wallpaper !== 'default' ? $wallpaper : null);
        }
        if (array_key_exists('disappear_seconds', $changes)) {
            Conversation::setDisappear($conversationId, $uid, (int) $changes['disappear_seconds']);
        }
    }

    /** Ubicación validada (latitud, longitud y nombre opcional del lugar). */
    private static function location(mixed $raw): ?array
    {
        if (!is_array($raw) || (($raw['lat'] ?? '') === '' && ($raw['lng'] ?? '') === '')) {
            return null;
        }
        $lat = filter_var($raw['lat'] ?? null, FILTER_VALIDATE_FLOAT);
        $lng = filter_var($raw['lng'] ?? null, FILTER_VALIDATE_FLOAT);
        if ($lat === false || $lng === false || $lat < -90 || $lat > 90 || $lng < -180 || $lng > 180) {
            throw ActionError::field('location', 'La ubicación no es válida.');
        }
        $max = (int) Config::get('app.chat.location_name_max', 120);
        $name = Guard::singleLine((string) ($raw['name'] ?? ''), 400) ?? '';
        if (mb_strlen($name) > $max || preg_match('/[<>\p{C}]/u', $name)) {
            throw ActionError::field('location', 'El nombre del lugar puede tener hasta ' . $max . ' caracteres, sin símbolos especiales.');
        }
        return ['lat' => round($lat, 6), 'lng' => round($lng, 6), 'name' => $name !== '' ? $name : null];
    }

    /** Mensaje de una conversación de $uid, visible para él, que no es un aviso ni está eliminado. */
    private static function usable(int $uid, int $messageId): array
    {
        $message = $messageId > 0 ? Message::findVisible($messageId, $uid) : null;
        if ($message === null || $message['kind'] !== 'message' || $message['deleted_at'] !== null
            || Conversation::findFor((int) $message['conversation_id'], $uid) === null) {
            throw new ActionError('Este mensaje ya no está disponible.', 404);
        }
        return $message;
    }

    private static function action(int $uid): void
    {
        $key = 'user:' . $uid;
        Guard::rateLimit('message_action', $key, 'Hiciste demasiadas acciones seguidas en el chat. Espera un momento.');
        RateLimit::hit('message_action', $key);
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
