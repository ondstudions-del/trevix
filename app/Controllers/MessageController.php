<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
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
use Trevix\Models\PrivateChat;
use Trevix\Models\User;
use Trevix\Services\MediaUpload;
use Trevix\Services\MessageService;
use Trevix\Services\PrivateChatService;

/**
 * Mensajería privada: bandeja, conversación activa, nuevo mensaje y API (enviar, sondeo, borrar, silenciar).
 * Todo funciona sin JavaScript; con él, messages.js envía sin recargar y consulta mensajes nuevos.
 */
final class MessageController extends Controller
{
    /**
     * messages.php  ?c=ID (conversación) · ?to=usuario (escribir a alguien) · ?new=1&q= (buscar persona) · ?q= (buscar
     * chats; si es el PIN de los chats privados, los abre) · ?private=1 (chats privados) · ?lock=1 (cerrarlos).
     */
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
        Conversation::markDelivered($uid);
        $data = ['active' => null, 'messages' => [], 'hasOlder' => false, 'draftTo' => null, 'blockedReason' => null, 'newSearch' => null, 'lockedChat' => null];

        $to = mb_strtolower(trim(Request::query('to')));
        $conversationId = (int) Request::query('c');
        $term = Request::query('new') === '1' ? '' : trim(mb_substr(Request::query('q'), 0, 80));
        if (Request::query('lock') === '1') {
            PrivateChatService::webLock();
            Response::redirect(url('messages.php'));
        }
        if ($term !== '' && ($token = PrivateChatService::trySearch($uid, $term)) !== null) {
            PrivateChatService::webUnlock($token);
            Response::redirect(url('messages.php', ['private' => 1]));
        }
        $unlocked = PrivateChatService::webUnlocked($uid);
        $privateView = Request::query('private') === '1';
        if ($privateView && !$unlocked) {
            Session::flash('info', 'Escribe tu PIN en el buscador de los chats y pulsa Enter para abrir tus chats privados.');
            Response::redirect(url('messages.php'));
        }

        $active = null;
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
            if ($active === null || ($active['private'] && !$unlocked && $this->isPartial())) {
                Response::abort(404, 'Esta conversación no existe o no participas en ella.');
            }
            $privateView = $active['private'];
            if ($active['private'] && !$unlocked) {
                $data['lockedChat'] = $conversationId;
                $active = null;
            }
        }
        if (!$privateView) {
            PrivateChatService::webLock();
        }
        $inbox = $data['lockedChat'] === null
            ? Conversation::inbox($uid, 100, $privateView ? '' : $term, $privateView)
            : Conversation::inbox($uid);

        if ($conversationId > 0 && $active !== null) {
            $before = (int) Request::query('before');
            $page = Message::page($conversationId, $before ?: null, (int) Config::get('app.limits.messages_page', 40), $uid);
            if ($this->isPartial()) {
                $this->renderMessages($page['messages'], $uid, $active);
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
            $data['blockedReason'] = match (true) {
                $active['e2ee']             => 'Este chat está cifrado de extremo a extremo. Ábrelo en la app TREVIX para leer los mensajes cifrados y escribir.',
                $active['type'] === 'group' => null,
                $active['available']        => Conversation::cannotMessage($uid, User::findByUsername((string) $active['user']['username']), $conversationId),
                default                     => 'Esta cuenta ya no está disponible.',
            };
            if ($data['blockedReason'] !== null) {
                $data['blockedReason'] = t($data['blockedReason']);
            }
        } elseif (Request::query('new') === '1') {
            $data['newSearch'] = $this->newMessageSearch($uid);
        }

        $this->render('pages/messages', [
            'title'         => t('Mensajes') . ' · TREVIX',
            'activeNav'     => 'messages',
            'conversations' => $inbox,
            'viewerId'      => $uid,
            'maxBody'       => (int) Config::get('app.limits.message_body', 2000),
            'layoutWide'    => true,
            'quickReactions'   => User::chatReactions($uid),
            'defaultReactions' => array_values((array) Config::get('app.chat.reactions', [])),
            'maxQuickReactions' => (int) Config::get('app.chat.max_quick_reactions', 6),
            'searchTerm'    => $privateView ? '' : $term,
            'privateMode'   => $privateView && $data['lockedChat'] === null,
            'hasPrivatePin' => PrivateChat::hasPin($uid),
        ] + $data, 'layouts/app');
    }

    /**
     * api/messages.php — GET action=poll | media (nota de voz de una sola vez) | stickers | share_targets · POST action=send | delete | mute |
     * react | quick_reactions | sticker_favorite | private (pasar a privados o sacarlo) | private_unlock (PIN de un chat privado).
     */
    public function api(): void
    {
        $user = $this->requireUser();
        $uid = (int) $user['id'];

        if (!Request::isPost()) {
            match (Request::query('action')) {
                'poll'  => $this->poll($uid),
                'media' => $this->media($uid),
                'stickers' => Response::json(['ok' => true, 'items' => MessageService::stickerFavorites($uid)]),
                'share_targets' => $this->shareTargets($uid),
                default => Response::json(['ok' => false, 'error' => 'Acción no válida.'], 400),
            };
        }

        $this->rejectOversizedRequest();
        VerifyCsrf::handle();
        match (Request::text('action')) {
            'send'             => $this->send($user),
            'delete'           => $this->destroy($uid),
            'mute'             => $this->mute($uid),
            'react'            => $this->react($uid),
            'quick_reactions'  => $this->quickReactions($uid),
            'sticker_favorite' => $this->stickerFavorite($uid),
            'private'          => $this->setPrivate($uid),
            'private_unlock'   => $this->privateUnlock($uid),
            default            => $this->fail('Acción no válida.', 400, url('messages.php')),
        };
    }

    /** Pasa el chat a los chats privados (private=1) o lo devuelve a la bandeja (private=0, con los privados abiertos). */
    private function setPrivate(int $uid): never
    {
        $conversationId = (int) Request::text('c');
        $private = Request::text('private') === '1';
        $back = url('messages.php', ['c' => $conversationId]);
        try {
            $message = MessageService::bulk($uid, [$conversationId], $private ? 'private' : 'unprivate', PrivateChatService::webUnlocked($uid));
        } catch (ActionError $e) {
            Session::flash('error', $e->getMessage());
            Response::redirect(isset($e->fields['pin']) ? url('settings.php', ['section' => 'chats']) : $back);
        }
        Session::flash('success', $message);
        Response::redirect($private ? url('messages.php') : $back);
    }

    /** PIN escrito en el aviso de un chat privado: lo abre (y deja abiertos los demás privados). */
    private function privateUnlock(int $uid): never
    {
        $conversationId = (int) Request::text('c');
        $back = url('messages.php', ['c' => $conversationId]);
        try {
            PrivateChatService::webUnlock(PrivateChatService::unlock($uid, Request::text('pin')));
        } catch (ActionError $e) {
            Session::flash('error', $e->getMessage());
        }
        Response::redirect($back);
    }

    /**
     * Destinos para «Enviar por mensaje»: chats recientes (o los que coinciden con ?q=) y, después, personas que sigues
     * o que coinciden con la búsqueda. Los chats cifrados no aparecen: en la web no se puede escribir en ellos.
     */
    private function shareTargets(int $uid): never
    {
        $term = trim(mb_substr(Request::query('q'), 0, 80));
        $items = [];
        $seen = [$uid => true];
        foreach (Conversation::inbox($uid, 40, $term) as $c) {
            if ($c['type'] === 'direct') {
                $seen[(int) $c['user']['id']] = true;
            }
            if ($c['e2ee'] || !$c['available'] || $c['blocked'] || count($items) >= 12) {
                continue;
            }
            $items[] = [
                'target'   => 'c:' . $c['id'],
                'name'     => (string) ($c['nickname'] ?: $c['user']['display_name']),
                'username' => (string) $c['user']['username'],
                'group'    => $c['type'] === 'group',
                'avatar'   => avatar($c['user'], 'sm'),
            ];
        }
        $users = $term !== '' ? User::search($uid, $term, 1, 16)['users'] : Follow::connections('following', $uid, $uid, 1, 16)['users'];
        foreach ($users as $u) {
            if (isset($seen[(int) $u['id']]) || count($items) >= 24) {
                continue;
            }
            $items[] = [
                'target'   => 'u:' . $u['username'],
                'name'     => (string) $u['display_name'],
                'username' => (string) $u['username'],
                'group'    => false,
                'avatar'   => avatar($u, 'sm'),
            ];
        }
        Response::json(['ok' => true, 'items' => $items]);
    }

    /** Reacciona con un emoji (vacío la quita) y devuelve la burbuja actualizada. */
    private function react(int $uid): never
    {
        $messageId = (int) Request::text('message_id');
        $emoji = Request::text('emoji');
        $message = $this->attempt(static fn () => MessageService::react($uid, $messageId, $emoji !== '' ? $emoji : null), url('messages.php'));
        $conversation = Conversation::findFor((int) $message['conversation_id'], $uid);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'html' => $this->captureMessages([$message], $uid, $conversation)]);
        }
        Response::redirect(url('messages.php', ['c' => (int) $message['conversation_id']]) . '#mensaje-' . $messageId);
    }

    /** Reacciones rápidas propias (reactions[]); sin ninguna vuelven las predeterminadas. */
    private function quickReactions(int $uid): never
    {
        $list = $_POST['reactions'] ?? [];
        $list = is_array($list) ? array_values(array_filter(array_map(
            static fn ($v) => is_string($v) ? trim($v) : '',
            $list
        ), static fn (string $v) => $v !== '')) : [];
        $back = url('messages.php', array_filter(['c' => (int) Request::text('c') ?: null]));
        $saved = $this->attempt(static fn () => MessageService::saveQuickReactions($uid, $list), $back);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'reactions' => $saved, 'message' => t('Guardaste tus reacciones rápidas.')]);
        }
        Session::flash('success', 'Guardaste tus reacciones rápidas.');
        Response::redirect($back);
    }

    /** Guarda (save=1) o quita un sticker o GIF de favoritos. */
    private function stickerFavorite(int $uid): never
    {
        $id = Request::text('gif_id');
        $items = Request::text('save') === '1'
            ? $this->attempt(static fn () => MessageService::addStickerFavorite($uid, $id, Request::text('gif_kind') ?: 'sticker'), url('messages.php'))
            : MessageService::removeStickerFavorite($uid, $id);
        Response::json(['ok' => true, 'items' => $items]);
    }

    /** Nota de voz de una sola vez: se entrega una única vez a cada participante que la recibe. */
    private function media(int $uid): never
    {
        $messageId = (int) Request::query('id');
        $message = Message::findVisible($messageId, $uid);
        if ($message === null || $message['e2ee_epoch'] !== null || empty($message['view_once'])
            || !str_starts_with((string) $message['media_mime'], 'audio/')) {
            Response::json(['ok' => false, 'error' => t('Este mensaje ya no está disponible.')], 404);
        }
        try {
            $file = MessageService::protectedMedia($uid, $messageId);
        } catch (\Trevix\Core\ActionError $e) {
            Response::json(['ok' => false, 'error' => t($e->getMessage())], $e->status);
        }
        $path = BASE_PATH . '/' . $file['path'];
        while (ob_get_level() > 0) {
            ob_end_clean();
        }
        header('Content-Type: ' . $file['mime']);
        header('Content-Length: ' . (string) filesize($path));
        header('Cache-Control: private, no-store');
        header('X-Content-Type-Options: nosniff');
        readfile($path);
        if ($file['purge'] !== null) {
            Message::purgeIfAllViewed($file['purge']);
        }
        exit;
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
            static fn () => MessageService::send(
                $user,
                $conversationId,
                $to,
                Request::text('body', false),
                MediaUpload::collect('image'),
                MediaUpload::collect('voice'),
                ['id' => Request::text('gif_id'), 'kind' => Request::text('gif_kind')],
                ['shared_post' => (int) Request::text('shared_post')]
            ),
            $fallback
        );

        $chatUrl = url('messages.php', ['c' => $conversationId]);
        if (Request::wantsJson()) {
            Response::json([
                'ok'              => true,
                'conversation_id' => $conversationId,
                'message_id'      => $messageId,
                'url'             => $chatUrl,
                'html'            => View::capture('partials/message', [
                    'message' => Message::findFull($messageId, $uid), 'viewerId' => $uid,
                    'isGroup' => (Conversation::findFor($conversationId, $uid)['type'] ?? 'direct') === 'group',
                ]),
            ], 201);
        }
        Response::redirect($chatUrl . '#mensaje-' . $messageId);
    }

    /** Mensajes nuevos, eliminados y estado de lectura desde el último sondeo. */
    private function poll(int $uid): never
    {
        $conversationId = (int) Request::query('c');
        $conversation = $conversationId > 0 ? Conversation::findFor($conversationId, $uid) : null;
        if ($conversation === null || ($conversation['private'] && !PrivateChatService::webUnlocked($uid))) {
            Response::json(['ok' => false, 'error' => 'Esta conversación ya no está disponible.'], 404);
        }
        $after = max(0, (int) Request::query('after'));
        $from = max(0, (int) Request::query('from'));

        Conversation::markDelivered($uid, $conversationId);
        $messages = Message::since($conversationId, $after, 100, $uid);
        $lastId = $messages !== [] ? (int) end($messages)['id'] : $after;
        if (Request::query('read') === '1' && $lastId > 0) {
            Conversation::markRead($conversationId, $uid, $lastId);
        }

        Response::json([
            'ok'        => true,
            'html'      => $messages !== [] ? $this->captureMessages($messages, $uid, $conversation) : '',
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

    private function renderMessages(array $messages, int $uid, ?array $conversation = null): void
    {
        $isGroup = ($conversation['type'] ?? 'direct') === 'group';
        $partnerName = $conversation !== null && !$isGroup ? (string) (($conversation['nickname'] ?? null) ?: $conversation['user']['display_name']) : '';
        foreach ($messages as $message) {
            View::partial('message', ['message' => $message, 'viewerId' => $uid, 'partnerName' => $partnerName, 'isGroup' => $isGroup]);
        }
    }

    private function captureMessages(array $messages, int $uid, ?array $conversation = null): string
    {
        ob_start();
        $this->renderMessages($messages, $uid, $conversation);
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
                'preview' => ($last['from'] === $me ? t('Tú:') . ' ' : '') . $last['body'], 'last_message_at' => $last['created_at'],
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
            'title'         => t('Mensajes') . ' · TREVIX',
            'activeNav'     => 'messages',
            'conversations' => $inbox,
            'active'        => $active,
            'messages'      => $messages,
            'hasOlder'      => false,
            'draftTo'       => null,
            'blockedReason' => Auth::check() ? null : t('Inicia sesión para enviar mensajes.'),
            'newSearch'     => null,
            'viewerId'      => -1,
            'maxBody'       => (int) Config::get('app.limits.message_body', 2000),
            'layoutWide'    => true,
        ], 'layouts/app');
    }
}
