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
use Trevix\Models\Collaborator;
use Trevix\Models\Wallet;
use Trevix\Services\CollaboratorService;
use Trevix\Services\WalletService;

/** Monedero (recargas con comprobante, retiros e historial), plan de colaborador y suscripciones compradas. */
final class WalletController extends Controller
{
    public const TABS = [
        'wallet'        => ['label' => 'Monedero', 'icon' => 'wallet'],
        'collaborator'  => ['label' => 'Colaborador', 'icon' => 'crown'],
        'subscriptions' => ['label' => 'Mis suscripciones', 'icon' => 'star'],
    ];

    public function index(): void
    {
        Authenticate::handle();
        $tab = Request::queryIn('tab', array_keys(self::TABS), 'wallet');
        if (Request::isPost()) {
            $this->act($tab);
        }

        $user = Auth::user();
        $uid = (int) Auth::id();
        $data = [
            'title'     => t(self::TABS[$tab]['label']) . ' · TREVIX',
            'activeNav' => 'settings',
            'tab'       => $tab,
            'tabs'      => self::TABS,
            'errors'    => Session::pull('_errors', []),
            'old'       => Session::pull('_old', []),
        ];
        if ($user === null) {
            $this->render('pages/wallet', $data + ['summary' => null]);
            return;
        }

        if ($tab === 'wallet') {
            $page = Wallet::transactions($uid, max(0, (int) Request::query('before')), 30);
            $items = $page['items'];
            $data += [
                'summary'      => WalletService::summary($uid),
                'transactions' => array_map([WalletService::class, 'presentTransaction'], $items),
                'nextUrl'      => $page['hasMore'] && $items !== [] ? url('wallet.php', ['before' => (int) end($items)['id']]) : null,
                'topups'       => array_map([WalletService::class, 'presentTopup'], Wallet::topupsFor($uid, 10)),
                'withdrawals'  => array_map([WalletService::class, 'presentWithdrawal'], Wallet::withdrawalsFor($uid, 10)),
            ];
        } elseif ($tab === 'collaborator') {
            $subscribers = Collaborator::subscribers($uid, max(1, (int) Request::query('page', '1')), 30);
            $data += [
                'summary'     => null,
                'status'      => CollaboratorService::status($user),
                'subscribers' => $subscribers['items'],
                'nextUrl'     => $subscribers['hasMore'] ? url('wallet.php', ['tab' => 'collaborator', 'page' => max(1, (int) Request::query('page', '1')) + 1]) : null,
            ];
        } else {
            $subscriptions = Collaborator::subscriptionsOf($uid, max(1, (int) Request::query('page', '1')), 30);
            $data += [
                'summary'       => null,
                'subscriptions' => $subscriptions['items'],
                'nextUrl'       => $subscriptions['hasMore'] ? url('wallet.php', ['tab' => 'subscriptions', 'page' => max(1, (int) Request::query('page', '1')) + 1]) : null,
            ];
        }
        $this->render('pages/wallet', $data);
    }

    private function act(string $tab): never
    {
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $back = url('wallet.php', ['tab' => $tab === 'wallet' ? null : $tab]);
        $old = [];
        try {
            switch (Request::text('action')) {
                case 'topup':
                    $old = ['method_id' => (int) Request::input('method_id', 0), 'amount' => Request::text('amount'), 'reference' => Request::text('reference'), 'note' => Request::text('note')];
                    WalletService::requestTopup($user, $old);
                    Session::flash('success', 'Enviamos tu recarga a revisión. Te avisaremos cuando se acredite.');
                    break;
                case 'cancel_topup':
                    WalletService::cancelTopup((int) $user['id'], (int) Request::input('id', 0));
                    Session::flash('success', 'Cancelaste la recarga.');
                    break;
                case 'withdraw':
                    $old = ['w_amount' => Request::text('amount'), 'w_method' => Request::text('method'), 'w_account' => Request::text('account')];
                    WalletService::requestWithdrawal($user, ['amount' => $old['w_amount'], 'method' => $old['w_method'], 'account' => $old['w_account']]);
                    Session::flash('success', 'Pediste el retiro. Te avisaremos cuando el equipo lo pague.');
                    break;
                case 'cancel_withdrawal':
                    WalletService::cancelWithdrawal((int) $user['id'], (int) Request::input('id', 0));
                    Session::flash('success', 'Cancelaste el retiro: el dinero volvió a tu monedero.');
                    break;
                case 'save_plan':
                    $old = ['price' => Request::text('price'), 'days' => Request::text('days'), 'description' => Request::text('description')];
                    CollaboratorService::savePlan($user, ['price' => $old['price'], 'days' => (int) $old['days'], 'description' => $old['description']]);
                    Session::flash('success', 'Guardamos tu plan de colaborador.');
                    break;
                case 'pause':
                case 'resume':
                    $resume = Request::text('action') === 'resume';
                    CollaboratorService::setActive($user, $resume);
                    Session::flash('success', $resume ? 'Tu plan vuelve a aceptar suscripciones.' : 'Pausaste tu plan: quien ya pagó conserva su acceso.');
                    break;
                case 'subscribe':
                    $result = CollaboratorService::subscribe($user, (int) Request::input('collaborator_id', 0));
                    Session::flash('success', $result['message']);
                    $this->redirectBack($back);
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (ActionError $e) {
            if ($e->status === 402) {
                Session::flash('error', $e->getMessage());
                Response::redirect(url('wallet.php') . '#recargar');
            }
            if ($e->fields !== [] && $old !== []) {
                $fields = $e->fields;
                if (Request::text('action') === 'withdraw') {
                    $fields = array_combine(array_map(static fn ($k) => 'w_' . $k, array_keys($fields)), $fields);
                }
                $this->backWithErrors($back, $fields, $old);
            }
            Session::flash('error', $e->getMessage());
            $this->redirectBack($back);
        }
        Response::redirect($back);
    }
}
