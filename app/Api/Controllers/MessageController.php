<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Models\Block;
use Trevix\Models\Conversation;
use Trevix\Models\Follow;
use Trevix\Models\Message;
use Trevix\Models\User;
use Trevix\Services\ChatStorage;
use Trevix\Services\MediaUpload;
use Trevix\Services\MessageService;

/**
 * Mensajería privada: bandeja (con búsqueda), historial, sondeo de mensajes nuevos y cambios, enviar (con respuesta
 * o ubicación), reaccionar, fijar, reenviar, eliminar (para todos o para ti), buscar y ajustes del chat.
 */
final class MessageController extends ApiController
{
    /** GET /conversations?q= — con término: por nombre, usuario, apodo o texto de los mensajes. */
    public function index(): never
    {
        $uid = $this->uid();
        $term = trim(mb_substr(Request::query('q'), 0, 80));
        Conversation::markDelivered($uid);
        Reply::ok(array_map([Present::class, 'conversation'], Conversation::inbox($uid, 100, $term)), [
            'unread'           => Conversation::unreadCount($uid),
            'max_pinned_chats' => (int) Config::get('app.chat.max_pinned_chats', 3),
        ]);
    }

    /**
     * GET /conversations/{id} — incluye por qué no se puede escribir (null si se puede), los mensajes fijados y las
     * opciones del chat (fondos, duraciones de los mensajes temporales, reacciones rápidas).
     */
    public function show(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $partnerId = (int) $conversation['user']['id'];
        Reply::ok(Present::conversation($conversation) + [
            'blocked_reason' => $this->blockedReason($conversation, $uid),
            'blocked_by_me'  => $partnerId > 0 && Block::exists($uid, $partnerId),
            'pinned'         => Present::messages(Message::pinned((int) $conversation['id'], $uid), $this->partnerName($conversation)),
            'read_states'    => $this->readStates($conversation, $uid),
            'options'        => self::options($uid),
        ]);
    }

    /** En los grupos: hasta dónde leyó cada participante (fotos pequeñas de «Visto por»). */
    private function readStates(array $conversation, int $uid): array
    {
        if (($conversation['type'] ?? 'direct') !== 'group') {
            return [];
        }
        return array_map(static fn (array $r): array => [
            'user_id'      => $r['user_id'],
            'display_name' => $r['display_name'],
            'avatar_url'   => Present::file($r['avatar_path']),
            'last_read_id' => $r['last_read_id'],
        ], Conversation::readStates((int) $conversation['id'], $uid));
    }

    /**
     * GET /conversations/{id}/messages
     *   ?before=ID → historial (40 por página, en orden cronológico).
     *   ?around=ID → los mensajes alrededor de uno (saltar a un resultado de la búsqueda).
     *   ?after=ID[&from=ID&since=FECHA] → sondeo: mensajes nuevos, ids borrados desde «from», mensajes ya cargados
     *     que cambiaron desde «since» (reacciones, fijados), los fijados y hasta dónde leyó la otra persona.
     *   &read=1 → marca como leído hasta el último mensaje devuelto.
     */
    public function messages(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $conversationId = (int) $conversation['id'];
        $markRead = Request::query('read') === '1';
        $name = $this->partnerName($conversation);
        Conversation::markDelivered($uid, $conversationId);

        if (Request::query('after') !== '') {
            $after = max(0, (int) Request::query('after'));
            $from = max(0, (int) Request::query('from'));
            $since = Request::query('since');
            $messages = Message::since($conversationId, $after, 100, $uid);
            $lastId = $messages !== [] ? (int) end($messages)['id'] : $after;
            if ($markRead && $lastId > 0) {
                Conversation::markRead($conversationId, $uid, $lastId);
            }
            $validSince = preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $since) === 1;
            Reply::ok(Present::messages($messages, $name), [
                'last_id' => $lastId,
                'deleted' => $from > 0 ? Message::deletedSince($conversationId, $from) : [],
                'updated' => $validSince ? Present::messages(Message::updatedSince($conversationId, $from, $after, $since, $uid), $name) : [],
                'pinned'  => Present::messages(Message::pinned($conversationId, $uid), $name),
                'now'     => Message::now(),
                'seen_id' => Conversation::partnerLastRead($conversationId, $uid),
                'online'  => (bool) $conversation['online'],
                'disappear_seconds' => (int) ($conversation['disappear_seconds'] ?? 0),
                'unread'  => Conversation::unreadCount($uid),
                'theme'   => $conversation['theme'],
                'wallpaper' => $conversation['wallpaper'],
                'typing'  => $conversation['blocked'] ? [] : Conversation::typingNames($conversationId, $uid),
                'e2ee'    => $conversation['e2ee'],
                'key_epoch' => $conversation['key_epoch'],
                'read_states' => $this->readStates($conversation, $uid),
            ]);
        }

        $around = max(0, (int) Request::query('around'));
        if ($around > 0) {
            $page = Message::around($conversationId, $around, 25, $uid);
        } else {
            $before = max(0, (int) Request::query('before'));
            $page = Message::page($conversationId, $before ?: null, $this->limit('messages_page', 40), $uid);
            if ($markRead && $before === 0 && $page['messages'] !== []) {
                Conversation::markRead($conversationId, $uid, (int) end($page['messages'])['id']);
            }
        }
        Reply::ok(Present::messages($page['messages'], $name), [
            'next'    => $page['hasMore'] && $page['messages'] !== [] ? ['before' => (int) $page['messages'][0]['id']] : null,
            'seen_id' => Conversation::partnerLastRead($conversationId, $uid),
            'now'     => Message::now(),
        ]);
    }

    /** GET /conversations/{id}/search?q= — mensajes con ese texto, del más reciente al más antiguo. */
    public function search(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $term = trim(mb_substr(Request::query('q'), 0, 80));
        if (mb_strlen($term) < 2) {
            throw ActionError::field('q', 'Escribe al menos 2 caracteres para buscar.');
        }
        $results = Message::search((int) $conversation['id'], $uid, $term, (int) Config::get('app.chat.search_results', 50));
        Reply::ok(Present::messages($results, $this->partnerName($conversation)));
    }

    /**
     * POST /conversations/{id}/messages {body?, gif_id?, gif_kind?, reply_to?, location?: {lat, lng, name?}, view_once?, view_seconds?}
     * + un adjunto opcional (multipart): imagen en «image», video en «video» (con su miniatura en «poster») o nota de
     * voz en «voice» (M4A/AAC, MP3 o WAV).
     */
    public function reply(string $id): never
    {
        $this->rejectOversized();
        $user = $this->user();
        if (Input::has('e2ee_epoch')) {
            $this->sent(MessageService::sendEncrypted($user, (int) $id, [
                'epoch'            => Input::int('e2ee_epoch'),
                'ciphertext'       => Input::str('ciphertext'),
                'reply_to'         => Input::int('reply_to'),
                'forwarded'        => Input::bool('forwarded') ?? false,
                'view_once'        => Input::bool('view_once') ?? false,
                'view_seconds'     => Input::int('view_seconds'),
                'forward_media_of' => Input::int('forward_media_of'),
            ], MediaUpload::collect('file')));
        }
        $this->sent(MessageService::send(
            $user,
            (int) $id,
            '',
            Input::str('body', false),
            MediaUpload::collect('image'),
            MediaUpload::collect('voice'),
            ['id' => Input::str('gif_id'), 'kind' => Input::str('gif_kind')],
            [
                'reply_to'     => Input::int('reply_to'),
                'location'     => $this->locationInput(),
                'view_once'    => Input::bool('view_once') ?? false,
                'view_seconds' => Input::int('view_seconds'),
                'video'        => MediaUpload::collect('video'),
                'poster'       => MediaUpload::collect('poster'),
            ]
        ));
    }

    /**
     * GET /messages/{id}/info — de un mensaje propio: a quién se le entregó, quién lo leyó y quién abrió la foto o el
     * video de visualización única. Lo leído y lo abierto respetan la confirmación de lectura.
     */
    public function info(string $id): never
    {
        $uid = $this->uid();
        $message = Message::findVisible((int) $id, $uid);
        if ($message === null || $message['deleted_at'] !== null || ($message['kind'] ?? 'message') !== 'message'
            || Conversation::findFor((int) $message['conversation_id'], $uid) === null) {
            throw new ActionError('Este mensaje ya no está disponible.', 404);
        }
        if ((int) $message['sender_id'] !== $uid) {
            throw new ActionError('Solo puedes ver la información de tus mensajes.', 403);
        }
        $info = Conversation::deliveryInfo($message, $uid);
        $people = array_map(static fn (array $p): array => [
            'user'        => Present::user($p['user']),
            'status'      => $p['status'],
            'opened'      => $p['opened'],
            'read_hidden' => $p['read_hidden'],
        ], $info['people']);
        $count = static fn (string $status): int => count(array_filter($people, static fn (array $p): bool => $p['status'] === $status));
        Reply::ok([
            'message_id'    => (int) $message['id'],
            'view_once'     => !empty($message['view_once']),
            'read_receipts' => $info['receipts'],
            'recipients'    => count($people),
            'read'          => $count('read'),
            'delivered'     => $count('read') + $count('delivered'),
            'pending'       => $count('sent'),
            'opened'        => count(array_filter($people, static fn (array $p): bool => $p['opened'] === true)),
            'people'        => $people,
        ]);
    }

    /** POST /conversations {to} — prepara el chat directo con alguien (sin mensajes) y devuelve la conversación. */
    public function open(): never
    {
        $to = Input::str('to');
        if ($to === '') {
            throw ActionError::field('to', 'Indica con quién quieres hablar.');
        }
        $conversationId = MessageService::openDirect($this->user(), $to);
        Reply::ok(Present::conversation($this->conversation($conversationId)));
    }

    /** GET /conversations/{id}/shared?type=media|links&before=ID — fotos, notas de voz, GIF y archivos, o enlaces. */
    public function shared(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $type = Request::queryIn('type', ['media', 'links'], 'media');
        $before = max(0, (int) Request::query('before'));
        $page = Message::shared((int) $conversation['id'], $uid, $type, $before ?: null, 30);
        Reply::ok(Present::messages($page['messages'], $this->partnerName($conversation)), [
            'next' => $page['hasMore'] && $page['messages'] !== [] ? ['before' => (int) end($page['messages'])['id']] : null,
        ]);
    }

    /** GET /conversations/{id}/storage — cuánto ocupan los archivos del chat, por tipo y por persona. */
    public function storage(string $id): never
    {
        $conversation = $this->conversation((int) $id);
        $result = ChatStorage::conversation((int) $conversation['id']);
        $result['people'] = array_map(static fn (array $p) => Present::user($p) + [
            'files' => (int) $p['files'],
            'bytes' => (int) $p['bytes'],
        ], $result['people']);
        Reply::ok($result);
    }

    /**
     * GET /messages/{id}/media — archivo cifrado o de visualización única (con el token de la sesión). Las fotos de
     * visualización única solo se entregan una vez a cada persona.
     */
    public function media(string $id): never
    {
        $file = MessageService::protectedMedia($this->uid(), (int) $id);
        $path = BASE_PATH . '/' . $file['path'];
        while (ob_get_level() > 0) {
            ob_end_clean();
        }
        header('Content-Type: ' . $file['mime']);
        header('Content-Length: ' . (string) filesize($path));
        header('Cache-Control: private, no-store');
        header('X-Content-Type-Options: nosniff');
        header('Content-Disposition: attachment; filename="trevix-' . (int) $id . '"');
        readfile($path);
        if ($file['purge'] !== null) {
            Message::purgeIfAllViewed($file['purge']);
        }
        exit;
    }

    /** GET /me/chat-storage — tus archivos enviados en el servidor: total, de más de 30 y 90 días y por chat. */
    public function myStorage(): never
    {
        Reply::ok(ChatStorage::mine($this->uid()) + [
            'clean_days' => array_map('intval', (array) Config::get('app.chat.storage_clean_days', [30, 90])),
        ]);
    }

    /** POST /me/chat-storage/clean {older_than_days: 30|90, conversation_id?} — borra tus archivos enviados viejos. */
    public function cleanStorage(): never
    {
        $uid = $this->uid();
        $conversationId = Input::int('conversation_id');
        if ($conversationId > 0) {
            $this->conversation($conversationId);
        }
        $result = ChatStorage::clean($uid, Input::int('older_than_days'), $conversationId > 0 ? $conversationId : null);
        Reply::ok($result + [
            'message' => $result['files'] === 0
                ? 'No había archivos tuyos tan antiguos.'
                : tn((int) $result['files'], 'Liberaste {size} ({n} archivo).', 'Liberaste {size} ({n} archivos).', ['size' => self::size($result['bytes'])]),
            'storage' => ChatStorage::mine($uid),
        ]);
    }

    private static function size(int $bytes): string
    {
        [$decimal, $thousands] = locale() === 'en' ? ['.', ','] : [',', '.'];
        return match (true) {
            $bytes >= 1073741824 => number_format($bytes / 1073741824, 1, $decimal, $thousands) . ' GB',
            $bytes >= 1048576    => number_format($bytes / 1048576, 1, $decimal, $thousands) . ' MB',
            default              => max(1, (int) round($bytes / 1024)) . ' KB',
        };
    }

    /**
     * POST /messages {to: usuario, body?, gif_id?, gif_kind?, location?, view_once?, view_seconds?} + «image», «video»
     * (con «poster») o «voice» opcional — abre la conversación si no existía.
     */
    public function create(): never
    {
        $this->rejectOversized();
        $to = Input::str('to');
        if ($to === '') {
            throw ActionError::field('to', 'Indica a quién quieres escribir.');
        }
        $this->sent(MessageService::send(
            $this->user(),
            null,
            $to,
            Input::str('body', false),
            MediaUpload::collect('image'),
            MediaUpload::collect('voice'),
            ['id' => Input::str('gif_id'), 'kind' => Input::str('gif_kind')],
            [
                'location'     => $this->locationInput(),
                'view_once'    => Input::bool('view_once') ?? false,
                'view_seconds' => Input::int('view_seconds'),
                'video'        => MediaUpload::collect('video'),
                'poster'       => MediaUpload::collect('poster'),
            ]
        ));
    }

    /** GET /messages/recipients?q= — personas a las que escribir (sin término: las que sigues). */
    public function recipients(): never
    {
        $uid = $this->uid();
        $term = trim(mb_substr(Request::query('q'), 0, 80));
        $users = $term !== '' ? User::search($uid, $term, 1, 20)['users'] : Follow::connections('following', $uid, $uid, 1, 20)['users'];
        Reply::ok(array_values(array_map(
            [Present::class, 'user'],
            array_filter($users, static fn (array $u) => (int) $u['id'] !== $uid)
        )));
    }

    /** POST /conversations/{id}/read {message_id?} — sin id, hasta el último mensaje. */
    public function read(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $messageId = Input::int('message_id');
        if ($messageId < 1) {
            $latest = Message::page((int) $conversation['id'], null, 1, $uid)['messages'];
            $messageId = $latest !== [] ? (int) $latest[0]['id'] : 0;
        }
        Conversation::markRead((int) $conversation['id'], $uid, $messageId);
        Reply::ok(['unread' => Conversation::unreadCount($uid)]);
    }

    /**
     * POST /conversations/bulk {ids: [id…], action: pin|unpin|mute|unmute|read|favorite|unfavorite|clear|delete} —
     * acciones de la bandeja sobre uno o varios chats (vaciar y eliminar solo afectan a quien lo hace).
     */
    public function bulk(): never
    {
        $ids = Input::raw('ids');
        if (is_string($ids)) {
            $ids = explode(',', $ids);
        }
        $uid = $this->uid();
        $message = MessageService::bulk($uid, is_array($ids) ? array_filter($ids, 'is_scalar') : [], Input::str('action'));
        Reply::ok(['message' => $message, 'unread' => Conversation::unreadCount($uid)]);
    }

    /** POST /conversations/{id}/typing {typing: true|false} — la app lo envía cada pocos segundos mientras escribes. */
    public function typing(string $id): never
    {
        MessageService::typing($this->uid(), (int) $id, Input::bool('typing') ?? true);
        Reply::ok(['ok' => true]);
    }

    /**
     * PATCH /conversations/{id} {muted?, nickname?, wallpaper?, theme?, disappear_seconds?} — solo cambia lo enviado.
     * El apodo solo lo ves tú; el fondo, el estilo y los mensajes temporales cambian para todos (con aviso en el chat).
     */
    public function update(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $conversationId = (int) $conversation['id'];
        $changes = [];
        foreach (['nickname', 'wallpaper'] as $key) {
            if (Input::has($key)) {
                $value = Input::str($key);
                $changes[$key] = $value !== '' ? $value : null;
            }
        }
        if (Input::has('disappear_seconds')) {
            $changes['disappear_seconds'] = Input::int('disappear_seconds');
        }
        if (Input::has('theme')) {
            $changes['theme'] = Input::str('theme');
        }
        $muted = Input::has('muted') ? Input::bool('muted') : null;
        if (Input::has('muted') && $muted === null) {
            throw ActionError::field('muted', 'Indica si quieres silenciar la conversación (true o false).');
        }
        if ($changes === [] && $muted === null) {
            throw new ActionError('No hay cambios que guardar.');
        }
        if ($changes !== []) {
            MessageService::updateSettings($uid, $conversationId, $changes);
        }
        $message = 'Guardado.';
        if ($muted !== null) {
            Conversation::setMuted($conversationId, $uid, $muted);
            $message = $muted ? 'Silenciaste la conversación: no contará en los avisos de mensajes.' : 'La conversación vuelve a avisarte.';
        } elseif (array_key_exists('disappear_seconds', $changes)) {
            $message = $changes['disappear_seconds'] > 0 ? 'Mensajes temporales activados.' : 'Mensajes temporales desactivados.';
        } elseif (array_key_exists('nickname', $changes)) {
            $message = $changes['nickname'] !== null ? 'Apodo guardado.' : 'Quitaste el apodo.';
        } elseif (array_key_exists('wallpaper', $changes)) {
            $message = 'Fondo del chat cambiado.';
        } elseif (array_key_exists('theme', $changes)) {
            $message = 'Estilo del chat cambiado.';
        }
        $fresh = $this->conversation($conversationId);
        Reply::ok(Present::conversation($fresh) + ['muted' => (bool) $fresh['muted'], 'message' => $message]);
    }

    /** POST /messages/{id}/reaction {emoji} — una por persona (otra la reemplaza). */
    public function react(string $id): never
    {
        $emoji = Input::str('emoji');
        if ($emoji === '') {
            throw ActionError::field('emoji', 'Elige un emoji para reaccionar.');
        }
        Reply::ok($this->presentOwn(MessageService::react($this->uid(), (int) $id, $emoji)));
    }

    /** DELETE /messages/{id}/reaction */
    public function unreact(string $id): never
    {
        Reply::ok($this->presentOwn(MessageService::react($this->uid(), (int) $id, null)));
    }

    /** POST /messages/{id}/hide — «eliminar para ti». */
    public function hide(string $id): never
    {
        MessageService::hide($this->uid(), (int) $id);
        Reply::ok(['id' => (int) $id, 'message' => 'Mensaje eliminado para ti.']);
    }

    /** POST /messages/{id}/pin — devuelve los fijados de la conversación. */
    public function pin(string $id): never
    {
        $this->pinned((int) $id, true);
    }

    /** DELETE /messages/{id}/pin */
    public function unpin(string $id): never
    {
        $this->pinned((int) $id, false);
    }

    /** POST /messages/{id}/forward {to: [usuarios]} — hasta app.chat.max_forward personas. */
    public function forward(string $id): never
    {
        $to = Input::raw('to');
        if (is_string($to)) {
            $to = explode(',', $to);
        }
        $result = MessageService::forward($this->user(), (int) $id, is_array($to) ? array_map('strval', array_filter($to, 'is_scalar')) : []);
        $count = count($result['sent']);
        Reply::ok($result + [
            'message' => $count === 1 ? 'Mensaje reenviado.' : tn($count, 'Mensaje reenviado a {n} persona.', 'Mensaje reenviado a {n} personas.'),
        ]);
    }

    /** PUT /me/chat-reactions {reactions: [emoji, …]} — reacciones rápidas propias; [] vuelve a las predeterminadas. */
    public function quickReactions(): never
    {
        $list = Input::raw('reactions');
        if (is_string($list)) {
            $list = json_decode($list, true);
        }
        if (!is_array($list)) {
            throw ActionError::field('reactions', 'Elige tus reacciones rápidas.');
        }
        Reply::ok(['reactions' => MessageService::saveQuickReactions($this->uid(), array_values($list))]);
    }

    /** GET /me/stickers/favorites — stickers y GIF guardados (los más recientes primero). */
    public function stickerFavorites(): never
    {
        Reply::ok(MessageService::stickerFavorites($this->uid()));
    }

    /** POST /me/stickers/favorites {id, kind: sticker|gif} */
    public function addStickerFavorite(): never
    {
        Reply::ok(MessageService::addStickerFavorite($this->uid(), Input::str('id'), Input::str('kind') ?: 'sticker'), [], 201);
    }

    /** DELETE /me/stickers/favorites/{id} */
    public function removeStickerFavorite(string $id): never
    {
        Reply::ok(MessageService::removeStickerFavorite($this->uid(), $id));
    }

    /** DELETE /messages/{id} — solo los propios; queda como «mensaje eliminado». */
    public function destroy(string $id): never
    {
        Reply::ok($this->presentOwn(MessageService::delete($this->uid(), (int) $id)));
    }

    /**
     * reactions = reacciones rápidas de la persona (la primera es la del doble toque); default_reactions = las de TREVIX.
     *
     * @return array{wallpapers: list<array{key:string, label:string}>, disappear_options: list<array{seconds:int, label:string}>, reactions: list<string>, max_pins:int, max_forward:int}
     */
    public static function options(int $uid): array
    {
        $wallpapers = [];
        foreach ((array) Config::get('app.chat.wallpapers', []) as $key => $label) {
            $wallpapers[] = ['key' => (string) $key, 'label' => t((string) $label)];
        }
        $durations = [];
        foreach ((array) Config::get('app.chat.disappear_options', []) as $seconds => $label) {
            $durations[] = ['seconds' => (int) $seconds, 'label' => t((string) $label)];
        }
        $themes = [];
        foreach ((array) Config::get('app.chat.themes', []) as $key => $label) {
            $themes[] = ['key' => (string) $key, 'label' => t((string) $label)];
        }
        return [
            'wallpapers'        => $wallpapers,
            'themes'            => $themes,
            'view_seconds'      => array_map('intval', (array) Config::get('app.chat.view_seconds', [0, 3, 5, 10])),
            'disappear_options' => $durations,
            'reactions'         => User::chatReactions($uid),
            'default_reactions' => array_values((array) Config::get('app.chat.reactions', [])),
            'max_quick_reactions' => (int) Config::get('app.chat.max_quick_reactions', 6),
            'max_pins'          => (int) Config::get('app.chat.max_pins', 3),
            'max_pinned_chats'  => (int) Config::get('app.chat.max_pinned_chats', 3),
            'max_forward'       => (int) Config::get('app.chat.max_forward', 5),
            'nickname_max'      => (int) Config::get('app.chat.nickname_max', 40),
        ];
    }

    private function pinned(int $messageId, bool $pin): never
    {
        $uid = $this->uid();
        $pinned = MessageService::pin($uid, $messageId, $pin);
        $conversation = $pinned !== [] ? $this->conversation((int) $pinned[0]['conversation_id']) : null;
        Reply::ok([
            'pinned'  => Present::messages($pinned, $conversation !== null ? $this->partnerName($conversation) : ''),
            'message' => $pin ? 'Mensaje fijado.' : 'Mensaje desfijado.',
        ]);
    }

    /** Mensaje presentado con el nombre de la otra persona de su conversación. */
    private function presentOwn(array $message): array
    {
        $conversation = Conversation::findFor((int) $message['conversation_id'], $this->uid());
        return Present::message($message, $conversation !== null ? $this->partnerName($conversation) : '');
    }

    /** location: {lat, lng, name?} en JSON, o location_lat / location_lng / location_name en un formulario. */
    private function locationInput(): ?array
    {
        $raw = Input::raw('location');
        if (is_string($raw) && $raw !== '') {
            $raw = json_decode($raw, true);
        }
        if (is_array($raw)) {
            return $raw;
        }
        if (Input::has('location_lat') || Input::has('location_lng')) {
            return ['lat' => Input::str('location_lat'), 'lng' => Input::str('location_lng'), 'name' => Input::str('location_name')];
        }
        return null;
    }

    private function conversation(int $id): array
    {
        $conversation = $id > 0 ? Conversation::findFor($id, $this->uid()) : null;
        if ($conversation === null) {
            $this->notFound('Esta conversación no existe o no participas en ella.');
        }
        return $conversation;
    }

    /** Nombre (o apodo) de la otra persona para los avisos del chat; en los grupos, '' (cada aviso usa a su autor). */
    private function partnerName(array $conversation): string
    {
        if (($conversation['type'] ?? 'direct') === 'group') {
            return '';
        }
        $nickname = trim((string) ($conversation['nickname'] ?? ''));
        return $nickname !== '' ? $nickname : (string) ($conversation['user']['display_name'] ?? '');
    }

    private function blockedReason(array $conversation, int $uid): ?string
    {
        if (($conversation['type'] ?? 'direct') === 'group') {
            return null;
        }
        $reason = $conversation['available']
            ? Conversation::cannotMessage($uid, User::findByUsername((string) $conversation['user']['username']), (int) $conversation['id'])
            : 'Esta cuenta ya no está disponible.';
        return $reason !== null ? t($reason) : null;
    }

    /** @param array{0:int, 1:int} $result */
    private function sent(array $result): never
    {
        [$conversationId, $messageId] = $result;
        $uid = $this->uid();
        $message = Message::findFull($messageId, $uid);
        $conversation = Conversation::findFor($conversationId, $uid);
        $this->created([
            'conversation_id' => $conversationId,
            'message'         => $message !== null ? Present::message($message, $conversation !== null ? $this->partnerName($conversation) : '') : null,
        ]);
    }

    private function rejectOversized(): void
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === [] && !str_contains(strtolower((string) ($_SERVER['CONTENT_TYPE'] ?? '')), 'json')) {
            throw new ActionError('El archivo supera el tamaño que acepta el servidor.', 413);
        }
    }
}
