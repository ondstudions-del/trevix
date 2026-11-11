<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\Gift;
use Trevix\Services\GiftService;
use Trevix\Services\Giphy;

/**
 * Regalos (solo administradores): categorías, regalos con su nombre, GIF o sticker (subido o de GIPHY) y costo,
 * y la comisión de TREVIX sobre cada regalo enviado. La búsqueda de GIPHY se hace en el servidor (sin JavaScript):
 * los resultados aparecen como opciones dentro del formulario de agregar.
 */
final class GiftsController extends AdminController
{
    public const TABS = [
        'gifts'      => 'Regalos',
        'categories' => 'Categorías',
        'settings'   => 'Comisión',
    ];

    public function handle(): void
    {
        $this->guard('gifts');
        if (Request::isPost()) {
            $this->act();
        }
        $tab = $this->filter('tab', array_keys(self::TABS)) ?? 'gifts';
        $staff = $this->staff();
        $live = $staff !== null;
        $data = [
            'tab'        => $tab,
            'totals'     => $live ? Gift::totals() : [],
            'categories' => $live ? Gift::categories(false) : [],
            'commission' => GiftService::commissionPct(),
        ];
        if ($tab === 'gifts') {
            $data['gifts'] = $live ? Gift::adminList() : [];
            $data['giphyQuery'] = trim(mb_substr(Request::query('giphy'), 0, 50));
            $data['giphyKind'] = Request::queryIn('giphy_kind', ['sticker', 'gif'], 'sticker');
            $data['giphyResults'] = [];
            $data['giphyError'] = null;
            $data['giphyEnabled'] = Giphy::enabled();
            if ($live && $data['giphyQuery'] !== '' && $data['giphyEnabled']) {
                try {
                    $data['giphyResults'] = Giphy::search((int) $staff['id'], $data['giphyKind'], $data['giphyQuery'], 0)['items'];
                } catch (ActionError $e) {
                    $data['giphyError'] = $e->getMessage();
                }
            }
        }
        $this->page('gifts', 'gifts', $data);
    }

    private function act(): never
    {
        $tab = $this->filter('tab', array_keys(self::TABS)) ?? 'gifts';
        $fallback = $this->sectionUrl('gifts', ['tab' => $tab === 'gifts' ? null : $tab]);
        $staff = $this->beginAction('admin', $fallback);
        $id = (int) Request::input('id', 0);
        try {
            switch (Request::text('action')) {
                case 'save_gift':
                    $gift = GiftService::saveGift($staff, $id > 0 ? $id : null, [
                        'name'        => Request::text('name', false),
                        'category_id' => (int) Request::input('category_id', 0),
                        'kind'        => Request::text('kind'),
                        'price'       => Request::text('price', false),
                        'position'    => (int) Request::input('position', 0),
                        'active'      => Request::input('active') === '1',
                        'giphy'       => Request::text('giphy_link', false) !== '' ? Request::text('giphy_link', false) : Request::text('giphy', false),
                    ]);
                    Session::flash('success', t($id > 0 ? 'Guardamos «{name}».' : 'Agregaste «{name}» al catálogo.', ['name' => $gift['name'] ?? '']));
                    $fallback = $this->sectionUrl('gifts');
                    break;
                case 'delete_gift':
                    $deleted = GiftService::deleteGift($staff, $id);
                    Session::flash('success', $deleted
                        ? 'Eliminaste el regalo.'
                        : 'Ese regalo ya se compró, así que lo ocultamos del catálogo: quienes lo tienen guardado aún pueden enviarlo.');
                    break;
                case 'save_category':
                    GiftService::saveCategory($staff, $id > 0 ? $id : null, Request::text('name', false), (int) Request::input('position', 0), Request::input('active') === '1');
                    Session::flash('success', $id > 0 ? 'Guardamos la categoría.' : 'Agregaste la categoría.');
                    break;
                case 'delete_category':
                    GiftService::deleteCategory($staff, $id);
                    Session::flash('success', 'Eliminaste la categoría. Sus regalos quedaron en «Otros».');
                    break;
                case 'save_commission':
                    $raw = trim(Request::text('gift_commission', false));
                    if (!preg_match('/^\d{1,2}$/', $raw) || (int) $raw > 90) {
                        throw new DomainException('La comisión debe ser un número entre 0 y 90.');
                    }
                    $changes = AppSetting::save(['gift_commission' => (string) (int) $raw]);
                    if ($changes === []) {
                        Session::flash('info', 'No había cambios que guardar.');
                        break;
                    }
                    AuditLog::record((int) $staff['id'], 'settings.update', 'settings', null, $changes);
                    Session::flash('success', 'Guardamos la comisión de los regalos.');
                    break;
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (DomainException | ActionError $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }
}
