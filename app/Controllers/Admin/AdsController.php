<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\Ad;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Services\AdService;
use Trevix\Services\WalletService;

/**
 * OND-ADS (solo administradores): revisar los anuncios pagados (aprobar o rechazar con devolución), retirar los
 * activos, ver el historial y ajustar el precio por día, las personas por día y los días máximos.
 */
final class AdsController extends AdminController
{
    public const TABS = [
        'pending'  => 'En revisión',
        'active'   => 'Activos',
        'history'  => 'Historial',
        'settings' => 'Ajustes',
    ];

    public function handle(): void
    {
        $this->guard('ads');
        if (Request::isPost()) {
            $this->act();
        }
        $tab = $this->filter('tab', array_keys(self::TABS)) ?? 'pending';
        $live = $this->staff() !== null;
        if ($live) {
            AdService::settleDue();
        }
        $data = [
            'tab'      => $tab,
            'totals'   => $live ? Ad::totals() : null,
            'settings' => AdService::settings(),
            'items'    => [],
            'hasMore'  => false,
            'pageNo'   => $this->pageNumber(),
        ];
        if ($tab !== 'settings' && $live) {
            $page = Ad::adminList($tab, $data['pageNo'], $this->perPage());
            $data['items'] = array_map([AdService::class, 'presentOwn'], $page['items']);
            $data['hasMore'] = $page['hasMore'];
        }
        $this->page('ads', 'ads', $data);
    }

    private function act(): never
    {
        $tab = $this->filter('tab', array_keys(self::TABS)) ?? 'pending';
        $fallback = $this->sectionUrl('ads', ['tab' => $tab === 'pending' ? null : $tab]);
        $staff = $this->beginAction('admin', $fallback);
        $id = (int) Request::input('id', 0);
        try {
            switch (Request::text('action')) {
                case 'approve':
                    AdService::review($staff, $id, true, '');
                    Session::flash('success', 'Aprobaste el anuncio: ya se está mostrando en el feed.');
                    break;
                case 'reject':
                    AdService::review($staff, $id, false, (string) $this->note());
                    Session::flash('success', 'Rechazaste el anuncio y devolvimos el pago a su monedero.');
                    break;
                case 'remove':
                    AdService::remove($staff, $id, (string) $this->note());
                    Session::flash('success', 'Retiraste el anuncio. Devolvimos los días que faltaban.');
                    break;
                case 'save_settings':
                    $this->saveSettings($staff);
                    break;
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (DomainException | ActionError $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }

    private function saveSettings(array $staff): void
    {
        $price = WalletService::parseAmount(Request::text('ads_daily_price', false));
        $min = (int) Request::input('ads_reach_min', 0);
        $max = (int) Request::input('ads_reach_max', 0);
        $days = (int) Request::input('ads_max_days', 0);
        if ($price === null || $price < 10 || $price > 100000) {
            throw new DomainException('El precio por día debe ser de US$ 0,10 a US$ 1.000.');
        }
        if ($min < 1 || $min > 100000 || $max < $min || $max > 100000) {
            throw new DomainException('Las personas por día deben ir de 1 a 100.000, y el máximo no puede ser menor que el mínimo.');
        }
        if ($days < 1 || $days > 365) {
            throw new DomainException('Los días máximos deben ir de 1 a 365.');
        }
        $changes = AppSetting::save([
            'ads_enabled'     => Request::input('ads_enabled') === '1' ? '1' : '0',
            'ads_daily_price' => number_format($price / 100, 2, '.', ''),
            'ads_reach_min'   => (string) $min,
            'ads_reach_max'   => (string) $max,
            'ads_max_days'    => (string) $days,
        ]);
        if ($changes === []) {
            Session::flash('info', 'No había cambios que guardar.');
            return;
        }
        AuditLog::record((int) $staff['id'], 'settings.update', 'settings', null, $changes);
        Session::flash('success', 'Guardamos los ajustes de OND-ADS. Se aplican a las campañas nuevas.');
    }
}
