<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Conversation;
use Trevix\Models\Follow;
use Trevix\Models\Notification;

final class NotificationController extends Controller
{
    public const FILTERS = ['all' => 'Todas', 'mentions' => 'Menciones', 'requests' => 'Solicitudes'];

    private const REQUESTS_PAGE = 50;

    public function index(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Usa los botones de la página para gestionar tus notificaciones.');
        }

        $filter = Request::queryIn('filter', array_keys(self::FILTERS), 'all');
        $openId = (int) Request::query('open');
        if ($openId > 0 && Auth::check()) {
            $this->open($openId);
        }

        $nextUrl = null;
        $unread = 0;
        if ($this->isPreview()) {
            $items = DemoData::notifications();
            $items = match ($filter) {
                'mentions' => array_filter($items, static fn (array $n) => in_array($n['type'], Notification::MENTION_TYPES, true)),
                'requests' => array_filter($items, static fn (array $n) => $n['type'] === 'follow_request'),
                default    => $items,
            };
        } else {
            $uid = (int) $this->viewer()['id'];
            $before = (int) Request::query('before');
            $items = [];

            if ($filter !== 'mentions' && $before === 0) {
                $page = max(1, (int) Request::query('page', '1'));
                $requests = Follow::pendingRequests($uid, $filter === 'requests' ? $page : 1, self::REQUESTS_PAGE);
                foreach ($requests['users'] as $user) {
                    $items[] = [
                        'type'       => 'follow_request',
                        'actor'      => $user,
                        'text'       => t('quiere seguirte.'),
                        'created_at' => $user['requested_at'],
                        'read'       => false,
                    ];
                }
                if ($requests['hasMore']) {
                    $nextUrl = url('notifications.php', ['filter' => 'requests', 'page' => ($filter === 'requests' ? $page : 1) + 1]);
                }
            }

            if ($filter !== 'requests') {
                $list = Notification::listFor(
                    $uid,
                    $filter === 'mentions' ? Notification::MENTION_TYPES : null,
                    $before ?: null,
                    (int) Config::get('app.limits.notifications_page', 30)
                );
                $items = array_merge($items, $this->withFollowButtons($uid, $list['items']));
                if ($list['nextBefore'] !== null) {
                    $nextUrl = url('notifications.php', ['filter' => $filter === 'all' ? null : $filter, 'before' => $list['nextBefore']]);
                }
                usort($items, static fn (array $a, array $b) => strcmp($b['created_at'], $a['created_at']));
            }
            $unread = (int) ($this->viewer()['unread_notifications'] ?? 0);
        }

        $groups = [t('Hoy') => [], t('Esta semana') => [], t('Anteriores') => []];
        foreach ($items as $item) {
            $age = time() - (int) strtotime($item['created_at']);
            $key = $age < 86400 ? t('Hoy') : ($age < 604800 ? t('Esta semana') : t('Anteriores'));
            $groups[$key][] = $item;
        }

        $this->render('pages/notifications', [
            'title'     => t('Notificaciones') . ' · TREVIX',
            'activeNav' => 'notifications',
            'filter'    => $filter,
            'filters'   => self::FILTERS,
            'groups'    => array_filter($groups),
            'nextUrl'   => $nextUrl,
            'unread'    => $unread,
            'aside'     => $this->asideData(),
        ]);
    }

    /**
     * api/notifications.php
     * GET  ?action=counts       → avisos y chats sin leer (sondeo de la navegación).
     * POST action=read_all      → marca todas como leídas.
     */
    public function api(): void
    {
        $user = $this->requireUser();
        $uid = (int) $user['id'];

        if (!Request::isPost()) {
            if (Request::query('action') !== 'counts') {
                Response::json(['ok' => false, 'error' => 'Acción no válida.'], 400);
            }
            Response::json([
                'ok'            => true,
                'notifications' => Notification::unreadCount($uid) + (int) ($user['pending_requests'] ?? 0),
                'messages'      => Conversation::unreadCount($uid),
            ]);
        }

        VerifyCsrf::handle();
        if (Request::text('action') !== 'read_all') {
            $this->fail('Acción no válida.', 400, url('notifications.php'));
        }
        $marked = Notification::markAllRead($uid);
        $pending = (int) ($user['pending_requests'] ?? 0);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'marked' => $marked, 'notifications' => $pending]);
        }
        Session::flash('success', $marked > 0 ? 'Marcaste todas las notificaciones como leídas.' : 'No tenías notificaciones sin leer.');
        $this->redirectBack(url('notifications.php'));
    }

    /** Abrir un aviso lo marca como leído y lleva a la publicación, el comentario o el perfil. */
    private function open(int $id): never
    {
        $uid = (int) Auth::id();
        $notification = Notification::findFor($uid, $id);
        if ($notification === null) {
            Session::flash('info', 'Esa notificación ya no está disponible.');
            Response::redirect(url('notifications.php'));
        }
        Notification::markRead($uid, $id);
        Response::redirect(Notification::targetUrl($notification));
    }

    /** Los avisos de "comenzó a seguirte" muestran el botón para seguir de vuelta. */
    private function withFollowButtons(int $uid, array $items): array
    {
        $ids = [];
        foreach ($items as $item) {
            if ($item['type'] === 'follow' && $item['actor'] !== null) {
                $ids[] = $item['actor']['id'];
            }
        }
        $relations = Follow::relationsFor($uid, $ids);
        foreach ($items as &$item) {
            if ($item['type'] === 'follow' && $item['actor'] !== null) {
                $item['actor']['relation'] = $relations[$item['actor']['id']];
            }
        }
        return $items;
    }
}
