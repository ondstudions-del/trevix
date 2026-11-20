<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Services\OAuthService;

/** Cola de apps OAuth pendientes (moderadores y administradores). */
final class OAuthAppsController extends AdminController
{
    public function handle(): void
    {
        $this->guard('oauth_apps');
        if (Request::isPost()) {
            $this->act();
        }
        $page = $this->pageNumber();
        $staff = $this->staff();
        $result = $staff !== null
            ? OAuthService::pendingForStaff($staff, $page)
            : ['items' => [], 'hasMore' => false];
        $this->page('oauth_apps', 'oauth-apps', [
            'items'   => $result['items'],
            'hasMore' => $result['hasMore'],
            'pageNo'  => $page,
            'prevUrl' => $page > 1 ? $this->sectionUrl('oauth_apps', ['page' => $page - 1]) : null,
            'nextUrl' => $result['hasMore'] ? $this->sectionUrl('oauth_apps', ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('oauth_apps');
        $staff = $this->beginAction('moderator', $fallback);
        $id = (int) Request::input('id', 0);
        try {
            switch (Request::text('action')) {
                case 'approve':
                    OAuthService::approve($staff, $id, (string) $this->note());
                    Session::flash('success', 'App aprobada: la API ya funciona.');
                    break;
                case 'reject':
                    OAuthService::reject($staff, $id, (string) $this->note());
                    Session::flash('success', 'Solicitud rechazada.');
                    break;
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (ActionError $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }
}
