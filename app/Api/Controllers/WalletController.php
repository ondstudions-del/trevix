<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\Collaborator;
use Trevix\Models\Wallet;
use Trevix\Services\CollaboratorService;
use Trevix\Services\WalletService;

/** Monedero (recargas con comprobante, retiros e historial), plan de colaborador y suscripciones. Importes en USD. */
final class WalletController extends ApiController
{
    /** GET /me/wallet — saldo, lo que se puede retirar, límites, pendientes y medios de pago activos. */
    public function show(): never
    {
        Reply::ok(WalletService::summary($this->uid()));
    }

    /** GET /me/wallet/transactions?before=ID — movimientos, del más reciente al más antiguo. */
    public function transactions(): never
    {
        $page = Wallet::transactions($this->uid(), max(0, (int) Request::query('before')), 30);
        $items = array_map(static function (array $t): array {
            $out = WalletService::presentTransaction($t);
            $out['counterpart'] = $out['counterpart'] !== null ? Present::user($out['counterpart']) : null;
            return $out;
        }, $page['items']);
        Reply::ok($items, ['next' => $page['hasMore'] && $items !== [] ? ['before' => (int) end($items)['id']] : null]);
    }

    /** GET /me/wallet/topups — últimas recargas pedidas. */
    public function topups(): never
    {
        Reply::ok(array_map([WalletService::class, 'presentTopup'], Wallet::topupsFor($this->uid())));
    }

    /** POST /me/wallet/topups (multipart) {method_id, amount, reference, note?, proof (imagen)} */
    public function requestTopup(): never
    {
        $topup = WalletService::requestTopup($this->user(), [
            'method_id' => Input::int('method_id'),
            'amount'    => Input::str('amount'),
            'reference' => Input::str('reference'),
            'note'      => Input::str('note'),
        ]);
        $this->created(['message' => 'Enviamos tu recarga a revisión. Te avisaremos cuando se acredite.', 'topup' => $topup]);
    }

    /**
     * POST /me/wallet/play-purchases {product_id, purchase_token} — compra de saldo hecha con Google Play en la app de
     * Android: se comprueba con Google, se acredita una sola vez (precio menos la comisión) y se consume.
     */
    public function playPurchase(): never
    {
        $result = WalletService::creditPlayPurchase($this->user(), Input::str('product_id'), Input::str('purchase_token'));
        Reply::ok(['message' => t('Se acreditaron {amount} a tu monedero.', ['amount' => $result['credited']['formatted']])] + $result);
    }

    /** DELETE /me/wallet/topups/{id} — cancela una recarga que sigue en revisión. */
    public function cancelTopup(string $id): never
    {
        WalletService::cancelTopup($this->uid(), (int) $id);
        Reply::ok(['message' => 'Cancelaste la recarga.']);
    }

    /** GET /me/wallet/withdrawals — últimos retiros pedidos. */
    public function withdrawals(): never
    {
        Reply::ok(array_map([WalletService::class, 'presentWithdrawal'], Wallet::withdrawalsFor($this->uid())));
    }

    /** POST /me/wallet/withdrawals {amount, method, account} */
    public function requestWithdrawal(): never
    {
        $withdrawal = WalletService::requestWithdrawal($this->user(), [
            'amount'  => Input::str('amount'),
            'method'  => Input::str('method'),
            'account' => Input::str('account'),
        ]);
        $this->created(['message' => 'Pediste el retiro. Te avisaremos cuando el equipo lo pague.', 'withdrawal' => $withdrawal]);
    }

    /** DELETE /me/wallet/withdrawals/{id} — cancela un retiro en revisión y devuelve el dinero al monedero. */
    public function cancelWithdrawal(string $id): never
    {
        WalletService::cancelWithdrawal($this->uid(), (int) $id);
        Reply::ok(['message' => 'Cancelaste el retiro: el dinero volvió a tu monedero.']);
    }

    /**
     * GET /me/collaborator — requisitos con su avance, plan, cifras y límites.
     * PUT {price, days, description?} — activa (si cumple los requisitos) o edita el plan.
     */
    public function collaborator(): never
    {
        $user = $this->user();
        if (Request::method() === 'PUT') {
            $status = CollaboratorService::savePlan($user, [
                'price'       => Input::str('price'),
                'days'        => Input::int('days'),
                'description' => Input::str('description'),
            ]);
            Reply::ok(['message' => 'Guardamos tu plan de colaborador.'] + $status);
        }
        Reply::ok(CollaboratorService::status($user));
    }

    /** POST /me/collaborator/pause | resume — deja de aceptar (o vuelve a aceptar) suscripciones nuevas. */
    public function setActive(bool $active): never
    {
        $status = CollaboratorService::setActive($this->user(), $active);
        Reply::ok(['message' => $active ? 'Tu plan vuelve a aceptar suscripciones.' : 'Pausaste tu plan: quien ya pagó conserva su acceso.'] + $status);
    }

    /** GET /me/collaborator/subscribers?page= — suscriptores, con acceso vigente primero. */
    public function subscribers(): never
    {
        $page = Collaborator::subscribers($this->uid(), $this->pageNumber(), 30);
        Reply::ok(array_map(static fn (array $r) => Present::user($r) + [
            'access_until' => $r['expires_at'],
            'active'       => strtotime((string) $r['expires_at']) > time(),
            'since'        => $r['since'],
            'purchases'    => (int) $r['purchases'],
        ], $page['items']), $this->nextPage($page['hasMore']));
    }

    /** GET /me/subscriptions?page= — colaboradores a los que estoy suscrito. */
    public function subscriptions(): never
    {
        $page = Collaborator::subscriptionsOf($this->uid(), $this->pageNumber(), 30);
        Reply::ok(array_map(static fn (array $r) => Present::user($r) + [
            'access_until' => $r['expires_at'],
            'active'       => strtotime((string) $r['expires_at']) > time(),
            'accepting'    => !empty($r['plan_active']),
            'price'        => $r['price_cents'] !== null ? WalletService::amount((int) $r['price_cents']) : null,
            'days'         => $r['period_days'] !== null ? (int) $r['period_days'] : null,
        ], $page['items']), $this->nextPage($page['hasMore']));
    }

    /** POST /users/{id}/subscribe — compra o extiende la suscripción con el saldo del monedero. */
    public function subscribe(string $id): never
    {
        Reply::ok(CollaboratorService::subscribe($this->user(), (int) $id));
    }
}
