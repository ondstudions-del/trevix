<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\Conversation;
use Trevix\Models\E2ee;
use Trevix\Models\Group;
use Trevix\Models\Message;
use Trevix\Models\Note;
use Trevix\Models\Post;
use Trevix\Models\PrivateChat;
use Trevix\Models\RateLimit;
use Trevix\Models\StickerFavorite;
use Trevix\Models\Story;
use Trevix\Models\Support;
use Trevix\Models\User;

/** Enviar mensajes privados, responder historias y borrar mensajes (compartido por la web y la API). */
final class MessageService
{
    /**
     * Envía a una conversación existente ($conversationId) o a una persona por su usuario ($to).
     * Un mensaje lleva texto y, como mucho, un adjunto: una imagen, un video, una nota de voz o un GIF/sticker de GIPHY.
     *
     * @param list<array> $files imagen adjunta de MediaUpload::collect('image') (como máximo una)
     * @param list<array> $voice nota de voz de MediaUpload::collect('voice') (como máximo una)
     * @param array{id?:string, kind?:string} $gif GIF elegido (id de GIPHY y tipo gif|sticker)
     * @param array{reply_to?:int, location?:array{lat:mixed, lng:mixed, name?:mixed}|null, video?:list<array>, poster?:list<array>} $extra
     *        mensaje al que responde, ubicación (otro tipo de adjunto) y video (MediaUpload::collect('video')) con su
     *        miniatura opcional
     * @return array{0:int, 1:int} [conversación, mensaje]
     */
    public static function send(array $user, ?int $conversationId, string $to, string $body, array $files, array $voice = [], array $gif = [], array $extra = []): array
    {
        $uid = (int) $user['id'];
        [$conversation, $recipient, $conversationId] = self::target($uid, $conversationId, $to);
        if ($recipient === null || !Support::isAccount((int) $recipient['id'])) {
            Guard::verifiedEmail($user);
        }
        if ($conversation !== null && $conversation['e2ee']) {
            throw new ActionError('Este chat está cifrado de extremo a extremo. Ábrelo en la app TREVIX para escribir.', 403);
        }
        $viewOnce = !empty($extra['view_once']);

        $rateKey = 'user:' . $uid;
        Guard::rateLimit('message_send', $rateKey, 'Enviaste muchos mensajes seguidos. Espera un momento.');

        $body = Guard::cleanText($body);
        $max = (int) Config::get('app.limits.message_body', 2000);
        if (mb_strlen($body) > $max) {
            throw ActionError::field('body', t('El mensaje no puede superar los {n} caracteres.', ['n' => $max]));
        }
        if (count($files) > 1) {
            throw ActionError::field('image', 'Puedes enviar una imagen por mensaje.');
        }
        if (count($voice) > 1) {
            throw ActionError::field('voice', 'Puedes enviar una nota de voz por mensaje.');
        }
        $video = (array) ($extra['video'] ?? []);
        if (count($video) > 1) {
            throw ActionError::field('video', 'Puedes enviar un video por mensaje.');
        }
        $gifId = trim((string) ($gif['id'] ?? ''));
        $location = isset($extra['location']) ? self::location($extra['location']) : null;
        $sharedPost = (int) ($extra['shared_post'] ?? 0);
        if ($sharedPost > 0 && Post::findVisible($sharedPost, $uid) === null) {
            throw ActionError::field('shared_post', 'Esa publicación ya no está disponible.');
        }
        if (count(array_filter([$files !== [], $video !== [], $voice !== [], $gifId !== '', $location !== null, $sharedPost > 0])) > 1) {
            throw ActionError::field('body', 'Envía la imagen, el video, la nota de voz, el GIF o la ubicación en mensajes separados.');
        }
        if ($body === '' && $sharedPost < 1 && $files === [] && $video === [] && $voice === [] && $gifId === '' && $location === null) {
            throw ActionError::field('body', 'Escribe un mensaje o adjunta una imagen, un video, una nota de voz, un GIF o tu ubicación.');
        }
        if ($viewOnce && $files === [] && $video === [] && $voice === []) {
            throw ActionError::field('view_once', 'La visualización única es para fotos, videos y notas de voz.');
        }
        $viewSeconds = $viewOnce && $voice === [] ? self::viewSeconds($extra['view_seconds'] ?? 0) : null;
        $replyTo = (int) ($extra['reply_to'] ?? 0);
        self::checkReply($uid, $conversationId, $replyTo);
        $gifRow = Giphy::resolve($gifId, (string) ($gif['kind'] ?? 'gif'));

        RateLimit::hit('message_send', $rateKey);
        $media = null;
        if ($files !== []) {
            try {
                $media = MediaUpload::storeMessageImage($files[0], $viewOnce);
            } catch (RuntimeException $e) {
                throw ActionError::field('image', $e->getMessage());
            }
        } elseif ($video !== []) {
            try {
                $poster = ((array) ($extra['poster'] ?? []))[0] ?? null;
                $media = MediaUpload::storeMessageVideo($video[0], $poster, $viewOnce);
            } catch (RuntimeException $e) {
                throw ActionError::field('video', $e->getMessage());
            }
        } elseif ($voice !== []) {
            try {
                $media = VoiceUpload::store($voice[0], $viewOnce);
            } catch (RuntimeException $e) {
                throw ActionError::field('voice', $e->getMessage());
            }
        }

        try {
            $sent = Conversation::send($uid, $recipient !== null ? (int) $recipient['id'] : null, $conversationId, $body !== '' ? $body : null, $media, null, null, $gifRow, [
                'reply_to_id'    => $replyTo > 0 ? $replyTo : null,
                'location'       => $location,
                'view_once'      => $viewOnce,
                'view_seconds'   => $viewSeconds,
                'shared_post_id' => $sharedPost > 0 ? $sharedPost : null,
            ]);
        } catch (Throwable $e) {
            MediaUpload::delete($media['path'] ?? null);
            MediaUpload::delete($media['poster_path'] ?? null);
            throw $e;
        }
        if ($recipient !== null) {
            Ix::afterMessage($uid, $sent[0], $sent[1]);
        }
        return $sent;
    }

    /**
     * Conversación de destino: una existente ($conversationId, directa o grupo) o la directa con $to. En las directas
     * aplica la privacidad de mensajes y los bloqueos. @return array{0: ?array, 1: ?array, 2: ?int}
     */
    private static function target(int $uid, ?int $conversationId, string $to): array
    {
        $conversation = null;
        $recipient = null;
        if ($conversationId !== null) {
            $conversation = Conversation::findFor($conversationId, $uid);
            if ($conversation === null || !$conversation['available']) {
                throw new ActionError('Esta conversación ya no está disponible.', 404);
            }
            if ($conversation['type'] === 'group') {
                return [$conversation, null, $conversationId];
            }
            $recipient = User::findByUsername((string) $conversation['user']['username']);
        } else {
            $recipient = User::findByUsername(mb_strtolower(trim(ltrim(trim($to), '@'))));
            if ($recipient !== null) {
                $conversationId = Conversation::findDirectId($uid, (int) $recipient['id']);
                $conversation = $conversationId !== null ? Conversation::findFor($conversationId, $uid) : null;
            }
        }
        $reason = Conversation::cannotMessage($uid, $recipient, $conversationId);
        if ($reason !== null) {
            throw new ActionError($reason, 403);
        }
        return [$conversation, $recipient, $conversationId];
    }

    private static function checkReply(int $uid, ?int $conversationId, int $replyTo): void
    {
        if ($replyTo < 1) {
            return;
        }
        $original = $conversationId !== null ? Message::findVisible($replyTo, $uid) : null;
        if ($original === null || (int) $original['conversation_id'] !== $conversationId || $original['kind'] !== 'message' || $original['deleted_at'] !== null) {
            throw ActionError::field('reply_to', 'Ese mensaje ya no está disponible para responderlo.');
        }
    }

    /** Segundos de una foto de visualización única (0 = hasta cerrarla). */
    private static function viewSeconds(mixed $value): ?int
    {
        $seconds = (int) $value;
        if (!in_array($seconds, array_map('intval', (array) Config::get('app.chat.view_seconds', [0, 3, 5, 10])), true)) {
            throw ActionError::field('view_seconds', 'Elige cuánto tiempo se verá la foto.');
        }
        return $seconds > 0 ? $seconds : null;
    }

    /**
     * Prepara una conversación directa sin mensajes (la app la necesita para repartir la clave del cifrado antes del
     * primer mensaje). Devuelve su id.
     */
    public static function openDirect(array $user, string $to): int
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        [, $recipient, $conversationId] = self::target($uid, null, $to);
        return $conversationId ?? \Trevix\Core\Database::transaction(static fn (): int => Conversation::openDirect($uid, (int) $recipient['id']));
    }

    /**
     * Mensaje cifrado de extremo a extremo (solo desde la app). $input: epoch, ciphertext (base64), reply_to,
     * forwarded, view_once, view_seconds, forward_media_of (reenviar el archivo cifrado de otro mensaje sin volver a
     * subirlo). $files: archivo cifrado opcional (campo «file»). Si la época no es la vigente o ya no cubre a los
     * participantes, responde 409 en «e2ee_epoch» y la app crea una nueva.
     *
     * @return array{0:int, 1:int} [conversación, mensaje]
     */
    public static function sendEncrypted(array $user, int $conversationId, array $input, array $files): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        [$conversation] = self::target($uid, $conversationId, '');
        if (E2ee::keyOf($uid) === null) {
            throw ActionError::field('e2ee', 'Configura el cifrado en la app antes de escribir.', 409);
        }
        $epoch = (int) ($input['epoch'] ?? 0);
        if ($epoch !== (int) $conversation['key_epoch'] || E2ee::stale($conversationId, $epoch)) {
            throw ActionError::field('e2ee_epoch', 'Las claves del chat cambiaron. Vuelve a intentarlo.', 409);
        }
        $ciphertext = trim((string) ($input['ciphertext'] ?? ''));
        $max = (int) Config::get('app.chat.e2ee_body_max', 24000);
        if ($ciphertext === '' || strlen($ciphertext) > $max || base64_decode($ciphertext, true) === false) {
            throw ActionError::field('ciphertext', 'El mensaje cifrado no es válido.');
        }
        if (count($files) > 1) {
            throw ActionError::field('file', 'Puedes enviar un archivo por mensaje.');
        }
        $forwardOf = (int) ($input['forward_media_of'] ?? 0);
        $viewOnce = !empty($input['view_once']);
        if ($viewOnce && $files === []) {
            throw ActionError::field('view_once', 'La visualización única es para fotos, videos y notas de voz.');
        }
        $viewSeconds = $viewOnce ? self::viewSeconds($input['view_seconds'] ?? 0) : null;
        $replyTo = (int) ($input['reply_to'] ?? 0);
        self::checkReply($uid, $conversationId, $replyTo);
        $source = null;
        if ($forwardOf > 0) {
            $source = Message::findVisible($forwardOf, $uid);
            if ($source === null || $source['deleted_at'] !== null || !empty($source['view_once']) || !MediaUpload::isProtected($source['media_path'])
                || Conversation::findFor((int) $source['conversation_id'], $uid) === null) {
                throw ActionError::field('forward_media_of', 'El archivo de ese mensaje ya no está disponible.');
            }
        }

        $rateKey = 'user:' . $uid;
        Guard::rateLimit('message_send', $rateKey, 'Enviaste muchos mensajes seguidos. Espera un momento.');
        RateLimit::hit('message_send', $rateKey);
        $media = null;
        if ($files !== []) {
            try {
                $media = MediaUpload::storeEncrypted($files[0]);
            } catch (RuntimeException $e) {
                throw ActionError::field('file', $e->getMessage());
            }
        } elseif ($source !== null) {
            $media = MediaUpload::duplicate((string) $source['media_path']);
            if ($media === null) {
                throw ActionError::field('forward_media_of', 'El archivo de ese mensaje ya no está disponible.');
            }
            $media['mime_type'] = 'application/octet-stream';
        }
        try {
            return Conversation::send($uid, null, $conversationId, $ciphertext, $media, null, null, null, [
                'reply_to_id'  => $replyTo > 0 ? $replyTo : null,
                'forwarded'    => !empty($input['forwarded']),
                'e2ee_epoch'   => $epoch,
                'view_once'    => $viewOnce,
                'view_seconds' => $viewSeconds,
            ]);
        } catch (Throwable $e) {
            MediaUpload::delete($media['path'] ?? null);
            throw $e;
        }
    }

    /**
     * Archivo protegido de un mensaje (cifrado o de visualización única) para un participante. Al abrir una foto de
     * visualización única queda marcada como vista (no se puede volver a abrir) y, si ya la vieron todos, el
     * archivo se borra después de entregarlo. @return array{path:string, mime:string, purge: ?array}
     */
    public static function protectedMedia(int $uid, int $messageId): array
    {
        $message = $messageId > 0 ? Message::findVisible($messageId, $uid) : null;
        if ($message === null || $message['deleted_at'] !== null || Conversation::findFor((int) $message['conversation_id'], $uid) === null) {
            throw new ActionError('Este mensaje ya no está disponible.', 404);
        }
        if (!MediaUpload::isProtected($message['media_path']) || !is_file(BASE_PATH . '/' . $message['media_path'])) {
            throw new ActionError(!empty($message['view_once']) ? 'Esto ya se abrió.' : 'Este archivo ya no está disponible.', 410);
        }
        $purge = null;
        if (!empty($message['view_once'])) {
            if ((int) $message['sender_id'] === $uid) {
                throw new ActionError('Lo que envías para una sola vez no se puede volver a abrir después de enviarlo.', 403);
            }
            if (!Message::markViewed($message, $uid)) {
                throw new ActionError('Ya lo abriste.', 410);
            }
            $purge = $message;
        }
        return [
            'path'  => (string) $message['media_path'],
            'mime'  => $message['e2ee_epoch'] !== null ? 'application/octet-stream' : (string) ($message['media_mime'] ?: 'application/octet-stream'),
            'purge' => $purge,
        ];
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
            throw ActionError::field('body', t('La respuesta no puede superar los {n} caracteres.', ['n' => $max]));
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
            throw ActionError::field('body', t('La respuesta no puede superar los {n} caracteres.', ['n' => $max]));
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

    /**
     * Reacciones rápidas propias (de 1 a app.chat.max_quick_reactions emojis distintos; la primera es la del doble
     * toque). Una lista vacía vuelve a las predeterminadas.
     *
     * @return list<string>
     */
    public static function saveQuickReactions(int $uid, array $list): array
    {
        $max = (int) Config::get('app.chat.max_quick_reactions', 6);
        $clean = [];
        foreach ($list as $emoji) {
            $emoji = self::emoji(is_string($emoji) ? $emoji : '');
            if (!in_array($emoji, $clean, true)) {
                $clean[] = $emoji;
            }
        }
        if (count($clean) > $max) {
            throw ActionError::field('reactions', t('Elige como mucho {n} reacciones rápidas.', ['n' => $max]));
        }
        self::action($uid);
        User::saveChatReactions($uid, $clean !== [] ? $clean : null);
        return User::chatReactions($uid);
    }

    /** @return list<array{id:string, kind:string, url:string, width:int, height:int, title:string}> */
    public static function stickerFavorites(int $uid): array
    {
        return array_values(array_filter(array_map(
            static fn (array $row): ?array => Giphy::fromRow([
                'gif_id' => $row['giphy_id'], 'gif_kind' => $row['kind'], 'gif_url' => $row['url'],
                'gif_width' => $row['width'], 'gif_height' => $row['height'], 'gif_title' => $row['title'],
            ]),
            StickerFavorite::forUser($uid)
        )));
    }

    /** Guarda un sticker o GIF en favoritos: se comprueba en GIPHY por su id (nunca se guarda una URL del cliente). */
    public static function addStickerFavorite(int $uid, string $giphyId, string $kind): array
    {
        $giphyId = trim($giphyId);
        if (!StickerFavorite::exists($uid, $giphyId) && StickerFavorite::count($uid) >= StickerFavorite::MAX) {
            throw new ActionError(t('Ya tienes {n} favoritos. Quita alguno para guardar otro.', ['n' => StickerFavorite::MAX]), 422);
        }
        self::action($uid);
        $gif = Giphy::resolve($giphyId, $kind);
        if ($gif === null) {
            throw ActionError::field('gif', 'Elige un sticker.');
        }
        StickerFavorite::add($uid, $gif);
        return self::stickerFavorites($uid);
    }

    public static function removeStickerFavorite(int $uid, string $giphyId): array
    {
        StickerFavorite::remove($uid, trim($giphyId));
        return self::stickerFavorites($uid);
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
                throw new ActionError(t('Puedes fijar hasta {n} mensajes. Deja de fijar alguno primero.', ['n' => $max]));
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
        if ($message['e2ee_epoch'] !== null || !empty($message['view_once'])) {
            throw new ActionError('Este mensaje está cifrado o es de visualización única: reenvíalo desde la app.');
        }
        if ($message['body'] === null && $message['media_path'] === null && $message['gif_id'] === null && $message['location_lat'] === null
            && empty($message['shared_post_id'])) {
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
            throw ActionError::field('to', t('Puedes reenviarlo a {n} personas como máximo.', ['n' => $max]));
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
            if ($reason === null && $conversationId !== null && (Conversation::findFor($conversationId, $uid)['e2ee'] ?? false)) {
                $reason = t('Ese chat está cifrado de extremo a extremo: reenvíalo desde la app.');
            }
            if ($reason === null && RateLimit::tooManyAttempts('message_send', $rateKey)) {
                $reason = t('Enviaste muchos mensajes seguidos. Espera un momento.');
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
                    $failed[$username] = t('El archivo del mensaje ya no está disponible.');
                    continue;
                }
                $media += [
                    'mime_type' => $message['media_mime'], 'duration' => $message['media_duration'],
                    'width' => $message['media_width'], 'height' => $message['media_height'],
                ];
                if (!empty($message['media_poster'])) {
                    $media['poster_path'] = MediaUpload::duplicate((string) $message['media_poster'])['path'] ?? null;
                }
            }
            try {
                [$cid] = Conversation::send($uid, (int) $recipient['id'], $conversationId, $message['body'], $media, null, null, $gif, [
                    'forwarded'      => true,
                    'location'       => $location,
                    'shared_post_id' => !empty($message['shared_post_id']) ? (int) $message['shared_post_id'] : null,
                ]);
                $sent[] = ['username' => $username, 'conversation_id' => $cid];
            } catch (Throwable $e) {
                MediaUpload::delete($media['path'] ?? null);
                MediaUpload::delete($media['poster_path'] ?? null);
                throw $e;
            }
        }
        if ($sent === []) {
            throw new ActionError((string) reset($failed), 403);
        }
        return ['sent' => $sent, 'failed' => $failed];
    }

    /**
     * Ajustes del chat: apodo de la otra persona (solo lo ve quien lo pone) y, para todos los participantes, el
     * fondo, el estilo y los mensajes temporales (en los grupos solo los administradores). Solo cambia lo enviado.
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
                $errors['nickname'] = t('El apodo puede tener hasta {n} caracteres.', ['n' => $max]);
            } elseif (preg_match('/[<>\p{C}]/u', $nickname)) {
                $errors['nickname'] = 'El apodo tiene caracteres no permitidos.';
            }
        }
        if (array_key_exists('wallpaper', $changes) && $changes['wallpaper'] !== null
            && !isset(((array) Config::get('app.chat.wallpapers', []))[(string) $changes['wallpaper']])) {
            $errors['wallpaper'] = 'Elige uno de los fondos disponibles.';
        }
        $isGroup = $conversation['type'] === 'group';
        $manager = $isGroup && Group::isManager($conversation['group']['role'] ?? null);
        if (array_key_exists('disappear_seconds', $changes)) {
            if (!$conversation['available'] || $conversation['blocked'] || ($isGroup && !$manager)) {
                $errors['disappear_seconds'] = $isGroup
                    ? 'Solo los administradores del grupo cambian los mensajes temporales.'
                    : 'No puedes cambiar los mensajes temporales en esta conversación.';
            } elseif (!array_key_exists((int) $changes['disappear_seconds'], (array) Config::get('app.chat.disappear_options', []))) {
                $errors['disappear_seconds'] = 'Elige una de las duraciones disponibles.';
            }
        }
        if (array_key_exists('theme', $changes)) {
            if (!isset(((array) Config::get('app.chat.themes', []))[(string) $changes['theme']])) {
                $errors['theme'] = 'Elige uno de los estilos disponibles.';
            } elseif ($isGroup && !$manager) {
                $errors['theme'] = 'Solo los administradores del grupo cambian el estilo.';
            } elseif (!$isGroup && (!$conversation['available'] || $conversation['blocked'])) {
                $errors['theme'] = 'No puedes cambiar el estilo de esta conversación.';
            }
        }
        if (array_key_exists('wallpaper', $changes) && !isset($errors['wallpaper'])) {
            if ($isGroup && !$manager) {
                $errors['wallpaper'] = 'Solo los administradores del grupo cambian el fondo.';
            } elseif (!$isGroup && (!$conversation['available'] || $conversation['blocked'])) {
                $errors['wallpaper'] = 'No puedes cambiar el fondo de esta conversación.';
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
            Conversation::setWallpaper($conversationId, $uid, (string) ($changes['wallpaper'] ?? 'default'));
        }
        if (array_key_exists('disappear_seconds', $changes)) {
            Conversation::setDisappear($conversationId, $uid, (int) $changes['disappear_seconds']);
        }
        if (array_key_exists('theme', $changes)) {
            Conversation::setTheme($conversationId, $uid, (string) $changes['theme']);
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
            throw ActionError::field('location', t('El nombre del lugar puede tener hasta {n} caracteres, sin símbolos especiales.', ['n' => $max]));
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

    public const BULK_ACTIONS = ['pin', 'unpin', 'mute', 'unmute', 'read', 'favorite', 'unfavorite', 'clear', 'delete', 'private', 'unprivate'];

    /**
     * Acciones de la bandeja sobre uno o varios chats propios: fijar (hasta app.chat.max_pinned_chats), silenciar,
     * marcar como leído, favoritos, vaciar, eliminar y pasar a privados o sacarlos (solo para quien lo hace; pasar a
     * privados exige tener PIN y sacarlos, haberlos desbloqueado). Devuelve un mensaje para mostrar.
     *
     * @param list<int> $ids
     */
    public static function bulk(int $uid, array $ids, string $action, bool $privateUnlocked = false): string
    {
        if (!in_array($action, self::BULK_ACTIONS, true)) {
            throw ActionError::field('action', 'Elige una acción válida.');
        }
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids), static fn (int $id): bool => $id > 0)));
        if ($ids === [] || count($ids) > 100) {
            throw ActionError::field('ids', 'Elige entre 1 y 100 chats.');
        }
        foreach ($ids as $id) {
            $conversation = Conversation::findFor($id, $uid);
            if ($conversation === null || ($conversation['private'] && !$privateUnlocked && $action !== 'private')) {
                throw ActionError::field('ids', 'Uno de los chats ya no existe o no participas en él.', 404);
            }
        }
        $count = count($ids);
        if ($action === 'pin') {
            $max = (int) Config::get('app.chat.max_pinned_chats', 3);
            $already = array_filter($ids, static fn (int $id): bool => (Conversation::findFor($id, $uid)['pinned'] ?? false) === true);
            if (Conversation::pinnedCount($uid) + $count - count($already) > $max) {
                throw ActionError::field('ids', t('Puedes fijar hasta {n} chats. Desfija alguno primero.', ['n' => $max]));
            }
        }
        if ($action === 'private' && !PrivateChat::hasPin($uid)) {
            throw ActionError::field('pin', 'Primero crea el PIN de tus chats privados.');
        }
        if ($action === 'unprivate' && !$privateUnlocked) {
            throw new ActionError('Escribe tu PIN en el buscador de los chats para abrir tus chats privados.', 423);
        }
        self::action($uid);
        switch ($action) {
            case 'pin':
            case 'unpin':
                Conversation::setPinned($ids, $uid, $action === 'pin');
                return $action === 'pin'
                    ? tn($count, 'El chat quedó fijado.', 'Los {n} chats quedaron fijados.')
                    : tn($count, 'Desfijaste el chat.', 'Desfijaste los {n} chats.');
            case 'mute':
            case 'unmute':
                foreach ($ids as $id) {
                    Conversation::setMuted($id, $uid, $action === 'mute');
                }
                return $action === 'mute'
                    ? tn($count, 'Silenciaste el chat.', 'Silenciaste los {n} chats.')
                    : tn($count, 'El chat vuelve a avisarte.', 'Los {n} chats vuelven a avisarte.');
            case 'read':
                foreach ($ids as $id) {
                    $latest = Message::page($id, null, 1, $uid)['messages'];
                    if ($latest !== []) {
                        Conversation::markRead($id, $uid, (int) $latest[0]['id']);
                    }
                }
                return tn($count, 'Marcaste como leído el chat.', 'Marcaste como leídos los {n} chats.');
            case 'favorite':
            case 'unfavorite':
                Conversation::setFavorite($ids, $uid, $action === 'favorite');
                return $action === 'favorite'
                    ? tn($count, 'Agregaste el chat a favoritos.', 'Agregaste los {n} chats a favoritos.')
                    : tn($count, 'Quitaste el chat de favoritos.', 'Quitaste los {n} chats de favoritos.');
            case 'clear':
            case 'delete':
                foreach ($ids as $id) {
                    Conversation::clearFor($id, $uid, $action === 'delete');
                }
                return $action === 'clear'
                    ? tn($count, 'Vaciaste el chat.', 'Vaciaste los {n} chats.')
                    : tn($count, 'Eliminaste el chat.', 'Eliminaste los {n} chats.');
            case 'private':
            case 'unprivate':
                Conversation::setPrivate($ids, $uid, $action === 'private');
                return $action === 'private'
                    ? tn($count, 'El chat pasó a tus chats privados.', 'Los {n} chats pasaron a tus chats privados.')
                    : tn($count, 'El chat volvió a tu bandeja.', 'Los {n} chats volvieron a tu bandeja.');
        }
        return 'Listo.';
    }

    /** «Escribiendo…» en un chat donde se puede escribir (ni bloqueado ni con una cuenta no disponible). */
    public static function typing(int $uid, int $conversationId, bool $typing): void
    {
        $conversation = Conversation::findFor($conversationId, $uid);
        if ($conversation === null) {
            throw new ActionError('Esta conversación no existe o no participas en ella.', 404);
        }
        if ($typing && ($conversation['type'] !== 'group' && (!$conversation['available'] || $conversation['blocked']))) {
            return;
        }
        Conversation::setTyping($conversationId, $uid, $typing);
    }

    private static function action(int $uid): void
    {
        $key = 'user:' . $uid;
        Guard::rateLimit('message_action', $key, 'Hiciste demasiadas acciones seguidas en el chat. Espera un momento.');
        RateLimit::hit('message_action', $key);
    }

    /**
     * Borra un mensaje propio (queda como "mensaje eliminado"). En los grupos, los administradores también pueden
     * borrar los de otras personas. Devuelve el mensaje actualizado.
     */
    public static function delete(int $uid, int $messageId): array
    {
        $message = $messageId > 0 ? Message::find($messageId) : null;
        $conversation = $message !== null ? Conversation::findFor((int) $message['conversation_id'], $uid) : null;
        if ($message === null || $conversation === null) {
            throw new ActionError('No puedes eliminar este mensaje.', 403);
        }
        $own = (int) ($message['sender_id'] ?? 0) === $uid;
        $groupAdmin = $conversation['type'] === 'group' && Group::isManager($conversation['group']['role'] ?? null);
        $deleted = $own
            ? Message::deleteOwn($messageId, $uid)
            : ($groupAdmin && $message['kind'] === 'message' && Message::deleteByModerator($messageId));
        if (!$deleted) {
            throw new ActionError('No puedes eliminar este mensaje.', 403);
        }
        return Message::find($messageId) ?? $message;
    }
}
