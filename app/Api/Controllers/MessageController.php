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
        Reply::ok(array_map([Present::class, 'conversation'], Conversation::inbox($uid, 100, $term)), ['unread' => Conversation::unreadCount($uid)]);
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
            'options'        => self::options(),
        ]);
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
     * POST /conversations/{id}/messages {body?, gif_id?, gif_kind?, reply_to?, location?: {lat, lng, name?}}
     * + un adjunto opcional (multipart): imagen en «image» o nota de voz en «voice» (M4A/AAC, MP3 o WAV).
     */
    public function reply(string $id): never
    {
        $this->rejectOversized();
        $user = $this->user();
        $this->sent(MessageService::send(
            $user,
            (int) $id,
            '',
            Input::str('body', false),
            MediaUpload::collect('image'),
            MediaUpload::collect('voice'),
            ['id' => Input::str('gif_id'), 'kind' => Input::str('gif_kind')],
            ['reply_to' => Input::int('reply_to'), 'location' => $this->locationInput()]
        ));
    }

    /** POST /messages {to: usuario, body?, gif_id?, gif_kind?, location?} + «image» o «voice» opcional — abre la conversación si no existía. */
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
            ['location' => $this->locationInput()]
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
     * PATCH /conversations/{id} {muted?, nickname?, wallpaper?, disappear_seconds?} — solo cambia lo enviado.
     * El apodo y el fondo solo los ves tú; los mensajes temporales cambian para los dos (y se avisa en el chat).
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
            'message' => $count === 1 ? 'Mensaje reenviado.' : 'Mensaje reenviado a ' . $count . ' personas.',
        ]);
    }

    /** DELETE /messages/{id} — solo los propios; queda como «mensaje eliminado». */
    public function destroy(string $id): never
    {
        Reply::ok($this->presentOwn(MessageService::delete($this->uid(), (int) $id)));
    }

    /** @return array{wallpapers: list<array{key:string, label:string}>, disappear_options: list<array{seconds:int, label:string}>, reactions: list<string>, max_pins:int, max_forward:int} */
    public static function options(): array
    {
        $wallpapers = [];
        foreach ((array) Config::get('app.chat.wallpapers', []) as $key => $label) {
            $wallpapers[] = ['key' => (string) $key, 'label' => (string) $label];
        }
        $durations = [];
        foreach ((array) Config::get('app.chat.disappear_options', []) as $seconds => $label) {
            $durations[] = ['seconds' => (int) $seconds, 'label' => (string) $label];
        }
        return [
            'wallpapers'        => $wallpapers,
            'disappear_options' => $durations,
            'reactions'         => array_values((array) Config::get('app.chat.reactions', [])),
            'max_pins'          => (int) Config::get('app.chat.max_pins', 3),
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

    private function partnerName(array $conversation): string
    {
        $nickname = trim((string) ($conversation['nickname'] ?? ''));
        return $nickname !== '' ? $nickname : (string) ($conversation['user']['display_name'] ?? '');
    }

    private function blockedReason(array $conversation, int $uid): ?string
    {
        return $conversation['available']
            ? Conversation::cannotMessage($uid, User::findByUsername((string) $conversation['user']['username']), (int) $conversation['id'])
            : 'Esta cuenta ya no está disponible.';
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
            throw new ActionError('La imagen supera el tamaño que acepta el servidor.', 413);
        }
    }
}
