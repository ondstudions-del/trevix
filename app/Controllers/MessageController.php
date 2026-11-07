<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Core\View;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Conversation;
use Trevix\Models\Follow;
use Trevix\Models\Message;
use Trevix\Models\User;
use Trevix\Services\MediaUpload;
use Trevix\Services\MessageService;

/**
 * Mensajería privada: bandeja, conversación activa, nuevo mensaje y API (enviar, sondeo, borrar, silenciar).
 * Todo funciona sin JavaScript; con él, messages.js envía sin recargar y consulta mensajes nuevos.
 */
final class MessageController extends Controller
{
    /** messages.php  ?c=ID (conversación) · ?to=usuario (escribir a alguien) · ?new=1&q= (buscar persona). */
    public function index(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Los mensajes se envían desde el formulario de la conversación.');
        }
        if ($this->isPreview()) {
            $this->renderDemo();
            return;
        }

        $viewer = $this->viewer();
        $uid = (int) $viewer['id'];
        $inbox = Conversation::inbox($uid);
        $data = ['active' => null, 'messages' => [], 'hasOlder' => false, 'draftTo' => null, 'blockedReason' => null, 'newSearch' => null];

        $to = mb_strtolower(trim(Request::query('to')));
        $conversationId = (int) Request::query('c');

        if ($to !== '') {
            $recipient = User::findByUsername($to);
            $existing = $recipient !== null ? Conversation::findDirectId($uid, (int) $recipient['id']) : null;
            if ($existing !== null && Conversation::findFor($existing, $uid) !== null) {
                Response::redirect(url('messages.php', ['c' => $existing]));
            }
            $reason = Conversation::cannotMessage($uid, $recipient, null);
            if ($recipient === null || $reason !== null) {
                Session::flash('error', $reason ?? 'Esta cuenta no está disponible.');
                Response::redirect(url('messages.php', ['new' => 1]));
            }
            $data['draftTo'] = $recipient;
        } elseif ($conversationId > 0) {
            $active = Conversation::findFor($conversationId, $uid);
            if ($active === null) {
                Response::abort(404, 'Esta conversación no existe o no participas en ella.');
            }
            $before = (int) Request::query('before');
            $page = Message::page($conversationId, $before ?: null, (int) Config::get('app.limits.messages_page', 40));
            if ($this->isPartial()) {
                $this->renderMessages($page['messages'], $uid);
                exit;
            }
            if ($before === 0 && $page['messages'] !== []) {
                $lastId = (int) end($page['messages'])['id'];
                Conversation::markRead($conversationId, $uid, $lastId);
                foreach ($inbox as &$item) {
                    if ($item['id'] === $conversationId) {
                        $item['unread'] = 0;
                    }
                }
                unset($item);
            }
            $data['active'] = $active;
            $data['messages'] = $page['messages'];
            $data['hasOlder'] = $page['hasMore'];
            $data['before'] = $before;
            $data['blockedReason'] = $active['available']
                ? Conversation::cannotMessage($uid, User::findByUsername((string) $active['user']['username']), $conversationId)
                : 'Esta cuenta ya no está disponible.';
        } elseif (Request::query('new') === '1') {
            $data['newSearch'] = $this->newMessageSearch($uid);
        }

        $this->render('pages/messages', [
            'title'         => 'Mensajes · TREVIX',
            'activeNav'     => 'messages',
            'conversations' => $inbox,
            'viewerId'      => $uid,
            'maxBody'       => (int) Config::get('app.limits.message_body', 2000),
            'layoutWide'    => true,
        ] + $data, 'layouts/app');
    }

    /** api/messages.php — GET action=poll · POST action=send | delete | mute. */
    public function api(): void
    {
        $user = $this->requireUser();
        $uid = (int) $user['id'];

        if (!Request::isPost()) {
            if (Request::query('action') !== 'poll') {
                Response::json(['ok' => false, 'error' => 'Acción no válida.'], 400);
            }
            $this->poll($uid);
        }

        $this->rejectOversizedRequest();
        VerifyCsrf::handle();
        match (Request::text('action')) {
            'send'   => $this->send($user),
            'delete' => $this->destroy($uid),
            'mute'   => $this->mute($uid),
            default  => $this->fail('Acción no válida.', 400, url('messages.php')),
        };
    }

    // -------------------------------------------------------------------------

    private function send(array $user): never
    {
        $uid = (int) $user['id'];
        $conversationId = (int) Request::text('c') ?: null;
        $to = mb_strtolower(Request::text('to'));
        $fallback = match (true) {
            $conversationId !== null => url('messages.php', ['c' => $conversationId]),
            $to !== ''               => url('messages.php', ['to' => $to]),
            default                  => url('messages.php'),
        };

        [$conversationId, $messageId] = $this->attempt(
            static fn () => MessageService::send($user, $conversationId, $to, Request::text('body', false), MediaUpload::collect('image'), (int) Request::text('song_id')),
            $fallback
        );

        $chatUrl = url('messages.php', ['c' => $conversationId]);
        if (Request::wantsJson()) {
            Response::json([
                'ok'              => true,
                'conversation_id' => $conversationId,
                'message_id'      => $messageId,
                'url'             => $chatUrl,
                'html'            => View::capture('partials/message', ['message' => Message::findFull($messageId), 'viewerId' => $uid]),
            ], 201);
        }
        Response::redirect($chatUrl . '#mensaje-' . $messageId);
    }

    /** Mensajes nuevos, eliminados y estado de lectura desde el último sondeo. */
    private function poll(int $uid): never
    {
        $conversationId = (int) Request::query('c');
        $conversation = $conversationId > 0 ? Conversation::findFor($conversationId, $uid) : null;
        if ($conversation === null) {
            Response::json(['ok' => false, 'error' => 'Esta conversación ya no está disponible.'], 404);
        }
        $after = max(0, (int) Request::query('after'));
        $from = max(0, (int) Request::query('from'));

        $messages = Message::since($conversationId, $after);
        $lastId = $messages !== [] ? (int) end($messages)['id'] : $after;
        if (Request::query('read') === '1' && $lastId > 0) {
            Conversation::markRead($conversationId, $uid, $lastId);
        }

        Response::json([
            'ok'        => true,
            'html'      => $messages !== [] ? $this->captureMessages($messages, $uid) : '',
            'last_id'   => $lastId,
            'deleted'   => $from > 0 ? Message::deletedSince($conversationId, $from) : [],
            'seen_id'   => Conversation::partnerLastRead($conversationId, $uid),
            'online'    => $conversation['online'],
            'unread'    => Conversation::unreadCount($uid),
        ]);
    }

    private function destroy(int $uid): never
    {
        $messageId = (int) Request::text('message_id');
        $message = $this->attempt(static fn () => MessageService::delete($uid, $messageId), url('messages.php'));
        $fallback = url('messages.php', ['c' => (int) $message['conversation_id']]);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'html' => View::capture('partials/message', ['message' => $message, 'viewerId' => $uid])]);
        }
        Session::flash('success', 'Eliminaste el mensaje.');
        Response::redirect($fallback);
    }

    private function mute(int $uid): never
    {
        $conversationId = (int) Request::text('c');
        if ($conversationId < 1 || Conversation::findFor($conversationId, $uid) === null) {
            $this->fail('Esta conversación ya no está disponible.', 404, url('messages.php'));
        }
        $muted = Request::text('muted') === '1';
        Conversation::setMuted($conversationId, $uid, $muted);
        $message = $muted ? 'Silenciaste la conversación: no contará en los avisos de mensajes.' : 'La conversación vuelve a avisarte.';
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'muted' => $muted, 'message' => $message]);
        }
        Session::flash('success', $message);
        Response::redirect(url('messages.php', ['c' => $conversationId]));
    }

    /** Personas a las que escribir: resultados de búsqueda o, sin término, las que sigues. */
    private function newMessageSearch(int $uid): array
    {
        $term = trim(Request::query('q'));
        $users = $term !== ''
            ? User::search($uid, $term, 1, 20)['users']
            : Follow::connections('following', $uid, $uid, 1, 20)['users'];
        return ['term' => $term, 'users' => array_values(array_filter($users, static fn (array $u) => (int) $u['id'] !== $uid))];
    }

    private function renderMessages(array $messages, int $uid): void
    {
        foreach ($messages as $message) {
            View::partial('message', ['message' => $message, 'viewerId' => $uid]);
        }
    }

    private function captureMessages(array $messages, int $uid): string
    {
        ob_start();
        $this->renderMessages($messages, $uid);
        return (string) ob_get_clean();
    }

    /** Si el cuerpo supera post_max_size, PHP descarta $_POST (incluido el token CSRF). */
    private function rejectOversizedRequest(): void
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === []) {
            $this->fail('La imagen supera el tamaño que acepta el servidor.', 413, url('messages.php'));
        }
    }

    /** Vista previa sin sesión: conversaciones de demostración, solo lectura. */
    private function renderDemo(): void
    {
        $me = (string) DemoData::viewer()['username'];
        $inbox = [];
        $active = null;
        $messages = [];
        $requested = (int) Request::query('c');
        foreach (DemoData::conversations() as $c) {
            $last = end($c['messages']);
            $inbox[] = [
                'id' => $c['id'], 'user' => $c['user'] + ['status' => 'active'], 'available' => true, 'blocked' => false,
                'online' => $c['online'], 'unread' => $c['unread'], 'muted' => false,
                'preview' => ($last['from'] === $me ? 'Tú: ' : '') . $last['body'], 'last_message_at' => $last['created_at'],
            ];
            if ($c['id'] === $requested) {
                $active = end($inbox);
                foreach ($c['messages'] as $i => $m) {
                    $messages[] = [
                        'id' => $i + 1, 'conversation_id' => $c['id'], 'sender_id' => $m['from'] === $me ? -1 : 0,
                        'body' => $m['body'], 'media_path' => null, 'media_mime' => null, 'deleted_at' => null, 'created_at' => $m['created_at'],
                    ];
                }
            }
        }

        $this->render('pages/messages', [
            'title'         => 'Mensajes · TREVIX',
            'activeNav'     => 'messages',
            'conversations' => $inbox,
            'active'        => $active,
            'messages'      => $messages,
            'hasOlder'      => false,
            'draftTo'       => null,
            'blockedReason' => Auth::check() ? null : 'Inicia sesión para enviar mensajes.',
            'newSearch'     => null,
            'viewerId'      => -1,
            'maxBody'       => (int) Config::get('app.limits.message_body', 2000),
            'layoutWide'    => true,
        ], 'layouts/app');
    }
}
