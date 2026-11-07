<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Models\Conversation;
use Trevix\Models\Follow;
use Trevix\Models\Message;
use Trevix\Models\User;
use Trevix\Services\MediaUpload;
use Trevix\Services\MessageService;

/** Mensajería privada: bandeja, historial, sondeo de mensajes nuevos, enviar, borrar y silenciar. */
final class MessageController extends ApiController
{
    /** GET /conversations */
    public function index(): never
    {
        $uid = $this->uid();
        Reply::ok(array_map([Present::class, 'conversation'], Conversation::inbox($uid)), ['unread' => Conversation::unreadCount($uid)]);
    }

    /** GET /conversations/{id} — incluye por qué no se puede escribir (null si se puede). */
    public function show(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        Reply::ok(Present::conversation($conversation) + ['blocked_reason' => $this->blockedReason($conversation, $uid)]);
    }

    /**
     * GET /conversations/{id}/messages
     *   ?before=ID → historial (40 por página, en orden cronológico).
     *   ?after=ID[&from=ID] → sondeo: mensajes nuevos, ids borrados desde «from», hasta dónde leyó la otra persona.
     *   &read=1 → marca como leído hasta el último mensaje devuelto.
     */
    public function messages(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $conversationId = (int) $conversation['id'];
        $markRead = Request::query('read') === '1';

        if (Request::query('after') !== '') {
            $after = max(0, (int) Request::query('after'));
            $from = max(0, (int) Request::query('from'));
            $messages = Message::since($conversationId, $after);
            $lastId = $messages !== [] ? (int) end($messages)['id'] : $after;
            if ($markRead && $lastId > 0) {
                Conversation::markRead($conversationId, $uid, $lastId);
            }
            Reply::ok(Present::messages($messages), [
                'last_id' => $lastId,
                'deleted' => $from > 0 ? Message::deletedSince($conversationId, $from) : [],
                'seen_id' => Conversation::partnerLastRead($conversationId, $uid),
                'online'  => (bool) $conversation['online'],
                'unread'  => Conversation::unreadCount($uid),
            ]);
        }

        $before = max(0, (int) Request::query('before'));
        $page = Message::page($conversationId, $before ?: null, $this->limit('messages_page', 40));
        if ($markRead && $before === 0 && $page['messages'] !== []) {
            Conversation::markRead($conversationId, $uid, (int) end($page['messages'])['id']);
        }
        Reply::ok(Present::messages($page['messages']), [
            'next'    => $page['hasMore'] && $page['messages'] !== [] ? ['before' => (int) $page['messages'][0]['id']] : null,
            'seen_id' => Conversation::partnerLastRead($conversationId, $uid),
        ]);
    }

    /** POST /conversations/{id}/messages {body?, song_id?} + imagen opcional en el campo «image» (multipart). */
    public function reply(string $id): never
    {
        $this->rejectOversized();
        $user = $this->user();
        $this->sent(MessageService::send($user, (int) $id, '', Input::str('body', false), MediaUpload::collect('image'), Input::int('song_id')));
    }

    /** POST /messages {to: usuario, body?, song_id?} + imagen opcional «image» — abre la conversación si no existía. */
    public function create(): never
    {
        $this->rejectOversized();
        $to = Input::str('to');
        if ($to === '') {
            throw ActionError::field('to', 'Indica a quién quieres escribir.');
        }
        $this->sent(MessageService::send($this->user(), null, $to, Input::str('body', false), MediaUpload::collect('image'), Input::int('song_id')));
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
            $latest = Message::page((int) $conversation['id'], null, 1)['messages'];
            $messageId = $latest !== [] ? (int) $latest[0]['id'] : 0;
        }
        Conversation::markRead((int) $conversation['id'], $uid, $messageId);
        Reply::ok(['unread' => Conversation::unreadCount($uid)]);
    }

    /** PATCH /conversations/{id} {muted: bool} */
    public function update(string $id): never
    {
        $uid = $this->uid();
        $conversation = $this->conversation((int) $id);
        $muted = Input::bool('muted');
        if ($muted === null) {
            throw ActionError::field('muted', 'Indica si quieres silenciar la conversación (true o false).');
        }
        Conversation::setMuted((int) $conversation['id'], $uid, $muted);
        Reply::ok([
            'muted'   => $muted,
            'message' => $muted ? 'Silenciaste la conversación: no contará en los avisos de mensajes.' : 'La conversación vuelve a avisarte.',
        ]);
    }

    /** DELETE /messages/{id} — solo los propios; queda como «mensaje eliminado». */
    public function destroy(string $id): never
    {
        Reply::ok(Present::message(MessageService::delete($this->uid(), (int) $id)));
    }

    private function conversation(int $id): array
    {
        $conversation = $id > 0 ? Conversation::findFor($id, $this->uid()) : null;
        if ($conversation === null) {
            $this->notFound('Esta conversación no existe o no participas en ella.');
        }
        return $conversation;
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
        $message = Message::since($conversationId, $messageId - 1, 1)[0] ?? Message::findFull($messageId);
        $this->created(['conversation_id' => $conversationId, 'message' => $message !== null ? Present::message($message) : null]);
    }

    private function rejectOversized(): void
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === [] && !str_contains(strtolower((string) ($_SERVER['CONTENT_TYPE'] ?? '')), 'json')) {
            throw new ActionError('La imagen supera el tamaño que acepta el servidor.', 413);
        }
    }
}
