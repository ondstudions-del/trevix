<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\AndroidEarlyAccess;
use Trevix\Services\EarlyAccessService;

/** Acceso anticipado Android: cola de solicitudes, URL/instrucciones y aceptación (envía el correo). */
final class EarlyAccessController extends AdminController
{
    public function handle(): void
    {
        $this->guard('early_access');
        if (Request::isPost()) {
            $this->act();
        }

        $status = $this->filter('status', array_keys(AndroidEarlyAccess::STATUSES)) ?? 'pending';
        $page = $this->pageNumber();
        $staff = $this->staff();
        $result = $staff !== null
            ? AndroidEarlyAccess::adminList($status, $page, $this->perPage())
            : ['requests' => [], 'hasMore' => false];
        $settings = EarlyAccessService::settings();
        if ($settings['android_tester_instructions'] === '') {
            $settings['android_tester_instructions'] = EarlyAccessService::defaultInstructions();
        }
        $query = ['status' => $status === 'pending' ? null : $status];

        $this->page('early_access', 'early-access', [
            'status'   => $status,
            'counts'   => $staff !== null ? AndroidEarlyAccess::counts() : array_fill_keys(array_keys(AndroidEarlyAccess::STATUSES), 0),
            'requests' => $result['requests'],
            'settings' => $settings,
            'prevUrl'  => $page > 1 ? $this->sectionUrl('early_access', $query + ['page' => $page - 1]) : null,
            'nextUrl'  => $result['hasMore'] ? $this->sectionUrl('early_access', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('early_access');
        $staff = $this->beginAction('admin', $fallback);
        $action = Request::text('action');
        try {
            switch ($action) {
                case 'save_settings':
                    $changed = EarlyAccessService::saveSettings(
                        $staff,
                        Request::text('android_tester_url', false),
                        Request::text('android_tester_instructions', false)
                    );
                    if ($changed === []) {
                        $this->done($fallback, 'No había cambios que guardar.', 'info');
                    }
                    $this->done($fallback, 'Guardamos la URL y las instrucciones del acceso anticipado.');
                case 'accept':
                    $row = EarlyAccessService::accept($staff, (int) Request::input('id', 0), $this->note());
                    Session::flash('success', t('Aceptaste a {name}. Le enviamos el correo con el enlace de testers.', ['name' => $row['full_name']]));
                    break;
                case 'reject':
                    EarlyAccessService::reject($staff, (int) Request::input('id', 0), $this->note());
                    Session::flash('success', 'Solicitud rechazada.');
                    break;
                case 'resend':
                    EarlyAccessService::resend($staff, (int) Request::input('id', 0));
                    Session::flash('success', 'Reenviamos el correo con el enlace de testers.');
                    break;
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (DomainException $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }
}
