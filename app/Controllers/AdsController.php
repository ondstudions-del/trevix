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
use Trevix\Models\Ad;
use Trevix\Services\AdService;
use Trevix\Services\MediaUpload;

/**
 * OND-ADS en la web: crear una campaña (promocionar una publicación, comunidad o grupo propios, o un anuncio libre)
 * y «Mis anuncios». ?go=ID es el toque en una tarjeta «Patrocinado» del feed: lo cuenta y lleva a su destino.
 * ?kind=post&target=ID abre el formulario con esa publicación elegida (enlace «Promocionar» de la publicación).
 */
final class AdsController extends Controller
{
    public const TABS = [
        'create' => ['label' => 'Crear anuncio', 'icon' => 'megaphone'],
        'mine'   => ['label' => 'Mis anuncios', 'icon' => 'trending-up'],
    ];

    public function index(): void
    {
        Authenticate::handle();
        $uid = (int) Auth::id();
        $go = (int) Request::query('go');
        if ($go > 0 && $uid > 0) {
            $this->go($uid, $go);
        }
        $tab = Request::queryIn('tab', array_keys(self::TABS), 'create');
        if (Request::isPost()) {
            $this->act($tab);
        }
        $data = [
            'title'     => t(self::TABS[$tab]['label']) . ' · OND-ADS · TREVIX',
            'activeNav' => 'settings',
            'tab'       => $tab,
            'tabs'      => self::TABS,
            'errors'    => Session::pull('_errors', []),
            'old'       => Session::pull('_old', []),
            'summary'   => null,
            'items'     => [],
            'nextUrl'   => null,
            'preset'    => [
                'kind'   => Request::queryIn('kind', array_keys(Ad::KINDS), ''),
                'target' => max(0, (int) Request::query('target')),
            ],
        ];
        if ($uid < 1) {
            $this->render('pages/ads', $data);
            return;
        }
        $data['summary'] = AdService::summary($uid);
        if ($tab === 'mine') {
            $page = AdService::mine($uid, max(0, (int) Request::query('before')));
            $data['items'] = $page['items'];
            $data['nextUrl'] = $page['next'] !== null ? url('ads.php', ['tab' => 'mine', 'before' => $page['next']['before']]) : null;
        }
        $this->render('pages/ads', $data);
    }

    private function go(int $uid, int $id): never
    {
        try {
            $dest = AdService::click($uid, $id);
        } catch (ActionError $e) {
            Session::flash('error', $e->getMessage());
            Response::redirect(url('feed.php'));
        }
        Response::redirect($dest['url']);
    }

    private function act(string $tab): never
    {
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $back = url('ads.php', ['tab' => $tab === 'create' ? null : $tab]);
        $old = [];
        try {
            switch (Request::text('action')) {
                case 'create':
                    $old = [
                        'kind'     => Request::text('kind'),
                        'target_id' => (int) Request::input('target_id_' . Request::text('kind'), 0),
                        'days'     => (int) Request::input('days', 1),
                        'title'    => Request::text('title'),
                        'body'     => Request::text('body'),
                        'link_url' => Request::text('link_url'),
                        'cta'      => Request::text('cta'),
                    ];
                    $result = AdService::create($user, $old, MediaUpload::collect('image'));
                    Session::flash('success', $result['message']);
                    Response::redirect(url('ads.php', ['tab' => 'mine']) . '#anuncio-' . (int) $result['campaign']['id']);
                case 'cancel':
                    $result = AdService::cancel($user, (int) Request::input('id', 0));
                    Session::flash('success', $result['message']);
                    break;
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (ActionError $e) {
            if ($e->status === 402) {
                Session::flash('error', $e->getMessage());
                Response::redirect(url('wallet.php') . '#recargar');
            }
            if ($e->fields !== [] && $old !== []) {
                $this->backWithErrors($back, $e->fields, $old);
            }
            Session::flash('error', $e->getMessage());
            $this->redirectBack($back);
        }
        Response::redirect($back);
    }
}
