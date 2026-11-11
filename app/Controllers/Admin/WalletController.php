<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\Collaborator;
use Trevix\Models\Wallet;
use Trevix\Services\CollaboratorService;
use Trevix\Services\ImageUpload;
use Trevix\Services\WalletService;

/**
 * Monedero (solo administradores): revisar recargas con su comprobante, pagar o rechazar retiros, medios de pago
 * y colaboradores con sus requisitos y la comisión de TREVIX.
 */
final class WalletController extends AdminController
{
    public const TABS = [
        'topups'        => 'Recargas',
        'withdrawals'   => 'Retiros',
        'methods'       => 'Medios de pago',
        'adjustments'   => 'Ajustes y reembolsos',
        'collaborators' => 'Colaboradores',
    ];

    /** Requisitos y límites editables: clave => [etiqueta, mínimo, máximo, ayuda]. Los importes van en dólares. */
    public const RULES = [
        'collab_min_followers'  => ['Seguidores mínimos', 0, 100000000, null],
        'collab_min_avg_likes'  => ['Promedio mínimo de «Me gusta»', 0, 100000000, 'En las últimas publicaciones propias.'],
        'collab_min_posts'      => ['Publicaciones mínimas para el promedio', 1, 50, null],
        'collab_min_avg_views'  => ['Promedio mínimo de visualizaciones', 0, 100000000, 'Personas distintas que vieron cada publicación.'],
        'collab_views_days'     => ['Días que cuentan para las visualizaciones', 1, 365, null],
        'collab_commission'     => ['Comisión de TREVIX (%)', 0, 90, 'Se descuenta de cada suscripción vendida.'],
        'collab_max_days'       => ['Días máximos por suscripción', 1, 3650, null],
    ];

    public const AMOUNTS = [
        'collab_min_price'      => 'Precio mínimo de suscripción (USD)',
        'collab_max_price'      => 'Precio máximo de suscripción (USD)',
        'wallet_max_topup'      => 'Recarga máxima (USD)',
        'wallet_min_withdrawal' => 'Retiro mínimo (USD)',
    ];

    public function handle(): void
    {
        $this->guard('wallet');
        if (Request::isPost()) {
            $this->act();
        }
        if (Request::query('proof') !== '') {
            $this->proof((int) Request::query('proof'));
        }

        $tab = $this->filter('tab', array_keys(self::TABS)) ?? 'topups';
        $live = $this->staff() !== null;
        $data = [
            'tab'    => $tab,
            'totals' => $live ? Wallet::totals() : [],
            'pending' => $live
                ? ['topups' => Wallet::counts('topups')['pending'], 'withdrawals' => Wallet::counts('withdrawals')['pending']]
                : ['topups' => 0, 'withdrawals' => 0],
            'prevUrl' => null,
            'nextUrl' => null,
        ];
        $page = $this->pageNumber();

        if ($tab === 'topups' || $tab === 'withdrawals') {
            $statuses = $tab === 'withdrawals' ? Wallet::WITHDRAWAL_STATUSES : Wallet::TOPUP_STATUSES;
            $status = $this->filter('status', array_keys($statuses)) ?? 'pending';
            $result = $live ? Wallet::adminList($tab, $status, $page, $this->perPage()) : ['items' => [], 'hasMore' => false];
            $query = ['tab' => $tab, 'status' => $status === 'pending' ? null : $status];
            $data += [
                'status'   => $status,
                'statuses' => $statuses,
                'counts'   => $live ? Wallet::counts($tab) : array_fill_keys(array_keys($statuses), 0),
                'items'    => $result['items'],
            ];
            $data['prevUrl'] = $page > 1 ? $this->sectionUrl('wallet', $query + ['page' => $page - 1]) : null;
            $data['nextUrl'] = $result['hasMore'] ? $this->sectionUrl('wallet', $query + ['page' => $page + 1]) : null;
        } elseif ($tab === 'methods') {
            $data['methods'] = $live ? Wallet::methods(false) : [];
        } elseif ($tab === 'adjustments') {
            $result = $live ? Wallet::adjustments($page, $this->perPage()) : ['items' => [], 'hasMore' => false];
            $data['adjustments'] = $result['items'];
            $data['prevUrl'] = $page > 1 ? $this->sectionUrl('wallet', ['tab' => $tab, 'page' => $page - 1]) : null;
            $data['nextUrl'] = $result['hasMore'] ? $this->sectionUrl('wallet', ['tab' => $tab, 'page' => $page + 1]) : null;
        } else {
            $result = $live ? Collaborator::adminList($page, $this->perPage()) : ['items' => [], 'hasMore' => false];
            $data += [
                'collaborators' => $result['items'],
                'grants'        => $live ? Collaborator::grants() : [],
                'settings'      => AppSetting::all(),
                'rules'         => CollaboratorService::rules(),
            ];
            $data['prevUrl'] = $page > 1 ? $this->sectionUrl('wallet', ['tab' => $tab, 'page' => $page - 1]) : null;
            $data['nextUrl'] = $result['hasMore'] ? $this->sectionUrl('wallet', ['tab' => $tab, 'page' => $page + 1]) : null;
        }

        $this->page('wallet', 'wallet', $data);
    }

    /** Comprobante de una recarga: solo para administradores con sesión, sin caché. */
    private function proof(int $id): never
    {
        $staff = $this->staff();
        if ($staff === null || !Auth::hasRole('admin', $staff)) {
            Response::abort(403, 'No tienes permisos para ver este comprobante.');
        }
        $topup = Wallet::topup($id);
        $path = $topup !== null ? ImageUpload::proofFile((string) $topup['proof_path']) : null;
        if ($path === null) {
            Response::abort(404, 'Este comprobante ya no está disponible.');
        }
        while (ob_get_level() > 0) {
            ob_end_clean();
        }
        header('Content-Type: image/jpeg');
        header('Content-Length: ' . (string) filesize($path));
        header('Cache-Control: private, no-store');
        header('X-Content-Type-Options: nosniff');
        header('Content-Disposition: inline; filename="comprobante-' . $id . '.jpg"');
        readfile($path);
        exit;
    }

    private function act(): never
    {
        $tab = $this->filter('tab', array_keys(self::TABS)) ?? 'topups';
        $fallback = $this->sectionUrl('wallet', ['tab' => $tab === 'topups' ? null : $tab]);
        $staff = $this->beginAction('admin', $fallback);
        $id = (int) Request::input('id', 0);
        try {
            switch (Request::text('action')) {
                case 'approve_topup':
                    $credited = trim(Request::text('credited', false));
                    $cents = $credited === '' ? null : WalletService::parseAmount($credited);
                    if ($credited !== '' && $cents === null) {
                        throw new DomainException('Escribe el monto a acreditar en dólares (por ejemplo 10 o 12.50).');
                    }
                    $topup = WalletService::approveTopup($staff, $id, $cents, $this->note());
                    Session::flash('success', t('Acreditaste {amount}. Le avisamos.', ['amount' => WalletService::money((int) $topup['credited_cents'])]));
                    break;
                case 'reject_topup':
                    WalletService::rejectTopup($staff, $id, (string) $this->note('reason'));
                    Session::flash('success', 'Recarga rechazada. Le avisamos con el motivo.');
                    break;
                case 'pay_withdrawal':
                    WalletService::markWithdrawalPaid($staff, $id, $this->note('reference'), $this->note());
                    Session::flash('success', 'Retiro marcado como pagado. Le avisamos.');
                    break;
                case 'reject_withdrawal':
                    WalletService::rejectWithdrawal($staff, $id, (string) $this->note('reason'));
                    Session::flash('success', 'Retiro rechazado: el dinero volvió a su monedero y le avisamos.');
                    break;
                case 'save_method':
                    WalletService::saveMethod($staff, $id > 0 ? $id : null, [
                        'name'         => Request::text('name', false),
                        'instructions' => Request::text('instructions', false),
                        'min_amount'   => Request::text('min_amount', false),
                        'position'     => (int) Request::input('position', 0),
                        'active'       => Request::input('active') === '1',
                    ]);
                    Session::flash('success', $id > 0 ? 'Guardamos el medio de pago.' : 'Agregaste el medio de pago.');
                    break;
                case 'delete_method':
                    WalletService::deleteMethod($staff, $id);
                    Session::flash('success', 'Eliminaste el medio de pago. Las recargas que ya lo usaron conservan su nombre.');
                    break;
                case 'save_rules':
                    $this->saveRules($staff);
                    break;
                case 'adjust':
                    $result = WalletService::adjust(
                        $staff,
                        Request::text('username'),
                        Request::text('direction'),
                        Request::text('amount', false),
                        Request::text('reason', false)
                    );
                    Session::flash('success', t('{amount} en el monedero de @{username}. Saldo nuevo: {balance}. Le avisamos.', [
                        'amount'   => ($result['amount_cents'] > 0 ? '+' : '') . WalletService::money($result['amount_cents']),
                        'username' => $result['username'],
                        'balance'  => WalletService::money($result['balance']),
                    ]));
                    break;
                case 'grant_collaborator':
                    $user = CollaboratorService::grant($staff, Request::text('username'), Request::text('note', false));
                    Session::flash('success', t('Habilitaste a @{username} como colaborador. Ya puede activar su plan sin cumplir los requisitos.', ['username' => $user['username']]));
                    break;
                case 'revoke_collaborator':
                    CollaboratorService::revokeGrant($staff, $id);
                    Session::flash('success', 'Quitaste la habilitación. Si ya había activado su plan, lo conserva.');
                    break;
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (DomainException | ActionError $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }

    private function saveRules(array $staff): void
    {
        $values = [];
        foreach (self::RULES as $key => [$label, $min, $max]) {
            $raw = trim(Request::text($key, false));
            if (!preg_match('/^\d{1,9}$/', $raw) || (int) $raw < $min || (int) $raw > $max) {
                throw new DomainException(t('«{label}» debe ser un número entre {min} y {max}.', ['label' => t($label), 'min' => $min, 'max' => $max]));
            }
            $values[$key] = (string) (int) $raw;
        }
        $cents = [];
        foreach (self::AMOUNTS as $key => $label) {
            $amount = WalletService::parseAmount(Request::text($key, false));
            if ($amount === null || $amount < 1 || $amount > 1000000) {
                throw new DomainException(t('«{label}» debe ser un importe en dólares (por ejemplo 5 o 9.99).', ['label' => t($label)]));
            }
            $cents[$key] = $amount;
            $values[$key] = $amount % 100 === 0 ? (string) intdiv($amount, 100) : sprintf('%d.%02d', intdiv($amount, 100), $amount % 100);
        }
        if ($cents['collab_max_price'] < $cents['collab_min_price']) {
            throw new DomainException('El precio máximo no puede ser menor que el mínimo.');
        }
        $changes = AppSetting::save($values);
        if ($changes === []) {
            Session::flash('info', 'No había cambios que guardar.');
            return;
        }
        AuditLog::record((int) $staff['id'], 'settings.update', 'settings', null, $changes);
        Session::flash('success', 'Guardamos los requisitos y la comisión.');
    }
}
