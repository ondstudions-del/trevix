<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Gift;
use Trevix\Models\Post;
use Trevix\Models\Story;
use Trevix\Models\User;
use Trevix\Services\GiftService;

/**
 * Regalos en la web: tienda (comprar para guardar), «Mis regalos», recibidos y enviados. Con ?to=usuario (perfil o
 * chat, &context=message) o &context=post|story&ref=ID, la página pasa a modo «enviar» a esa persona.
 */
final class GiftsController extends Controller
{
    public const TABS = [
        'shop'     => ['label' => 'Tienda', 'icon' => 'gift'],
        'mine'     => ['label' => 'Mis regalos', 'icon' => 'inbox'],
        'received' => ['label' => 'Recibidos', 'icon' => 'heart'],
        'sent'     => ['label' => 'Enviados', 'icon' => 'send'],
    ];

    public function index(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            $this->act();
        }
        $tab = Request::queryIn('tab', array_keys(self::TABS), 'shop');
        $uid = (int) Auth::id();
        $data = [
            'title'     => t(self::TABS[$tab]['label']) . ' · ' . t('Regalos') . ' · TREVIX',
            'activeNav' => 'settings',
            'tab'       => $tab,
            'tabs'      => self::TABS,
            'target'    => null,
            'nextUrl'   => null,
        ];
        if ($uid < 1) {
            $this->render('pages/gifts', $data + ['summary' => null]);
            return;
        }
        $data['target'] = $this->target($uid);
        if ($data['target'] !== null) {
            $tab = 'shop';
            $data['tab'] = $tab;
        }
        $data['summary'] = GiftService::summary($uid);
        if ($tab === 'received' || $tab === 'sent') {
            $page = GiftService::history($uid, $tab, max(0, (int) Request::query('before')));
            $data['history'] = $page['items'];
            $data['nextUrl'] = $page['next'] !== null ? url('gifts.php', ['tab' => $tab, 'before' => $page['next']['before']]) : null;
        }
        $this->render('pages/gifts', $data);
    }

    /**
     * Destino del modo «enviar»: la persona (y la publicación o historia) a la que se le envía el regalo.
     *
     * @return array{user: array, context: string, ref: int, back: string}|null
     */
    private function target(int $uid): ?array
    {
        $context = Request::queryIn('context', Gift::CONTEXTS, 'profile');
        $ref = max(0, (int) Request::query('ref'));
        $user = null;
        if ($context === 'post') {
            $post = $ref > 0 ? Post::findVisible($ref, $uid) : null;
            $user = $post !== null ? User::findActiveById((int) $post['user_id']) : null;
        } elseif ($context === 'story') {
            $story = $ref > 0 ? Story::findVisible($ref, $uid) : null;
            $user = $story !== null ? User::findActiveById((int) $story['user_id']) : null;
        } elseif (Request::query('to') !== '') {
            $user = User::findByUsername(mb_strtolower(ltrim(trim(Request::query('to')), '@')));
        }
        if (Request::query('to') === '' && $ref === 0) {
            return null;
        }
        if ($user === null || ($user['status'] ?? '') !== 'active' || (int) $user['id'] === $uid || User::blockedBetween($uid, (int) $user['id'])) {
            Session::flash('error', t('No puedes enviarle un regalo a esta cuenta.'));
            return null;
        }
        return ['user' => $user, 'context' => $context, 'ref' => $ref, 'back' => $this->backUrl($context, $ref, (string) $user['username'], null)];
    }

    private function backUrl(string $context, int $ref, string $username, ?int $conversationId): string
    {
        return match ($context) {
            'message' => $conversationId !== null ? url('messages.php', ['c' => $conversationId]) : url('messages.php', ['to' => $username]),
            'post'    => url('post.php', ['id' => $ref]),
            'story'   => url('stories.php', ['u' => $username]),
            default   => url('profile.php', ['u' => $username]),
        };
    }

    private function act(): never
    {
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $tab = Request::queryIn('tab', array_keys(self::TABS), 'shop');
        $back = url('gifts.php', ['tab' => $tab === 'shop' ? null : $tab]);
        try {
            switch (Request::text('action')) {
                case 'buy':
                    $result = GiftService::buy($user, (int) Request::input('gift_id', 0), (int) Request::input('quantity', 1));
                    Session::flash('success', $result['message']);
                    Response::redirect(url('gifts.php', ['tab' => 'mine']));
                case 'send':
                    $context = Request::text('context') ?: 'profile';
                    $ref = (int) Request::input('ref', 0);
                    $result = GiftService::send(
                        $user,
                        Request::text('to'),
                        (int) Request::input('gift_id', 0),
                        Request::text('source') === 'inventory',
                        $context,
                        $ref
                    );
                    Session::flash('success', $result['message']);
                    $username = (string) ($result['send']['user']['username'] ?? '');
                    Response::redirect($this->backUrl($context, $ref, $username, $result['conversation_id']));
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (ActionError $e) {
            Session::flash('error', $e->getMessage());
            if ($e->status === 402) {
                Response::redirect(url('wallet.php') . '#recargar');
            }
            $this->redirectBack($back);
        }
    }
}
