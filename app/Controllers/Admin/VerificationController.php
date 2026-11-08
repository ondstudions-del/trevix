<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\VerificationRequest;
use Trevix\Services\VerificationService;

/** Verificación: aprobar o rechazar las solicitudes de verificado que llegan desde la app (solo administradores). */
final class VerificationController extends AdminController
{
    public function handle(): void
    {
        $this->guard('verification');
        if (Request::isPost()) {
            $this->act();
        }

        $status = $this->filter('status', array_keys(VerificationRequest::STATUSES)) ?? 'pending';
        $page = $this->pageNumber();
        $rules = VerificationService::rules();
        $result = $this->staff() !== null
            ? VerificationRequest::adminList($status, $page, $this->perPage(), $rules['warning_days'])
            : ['requests' => [], 'hasMore' => false];
        $requests = array_map(static fn (array $r) => $r + [
            'now' => $status === 'pending'
                ? VerificationService::eligibility(['id' => $r['user_id'], 'followers_count' => $r['current_followers']])
                : null,
        ], $result['requests']);
        $query = ['status' => $status === 'pending' ? null : $status];

        $this->page('verification', 'verification', [
            'status'   => $status,
            'counts'   => $this->staff() !== null ? VerificationRequest::counts() : array_fill_keys(array_keys(VerificationRequest::STATUSES), 0),
            'requests' => $requests,
            'rules'    => $rules,
            'prevUrl'  => $page > 1 ? $this->sectionUrl('verification', $query + ['page' => $page - 1]) : null,
            'nextUrl'  => $result['hasMore'] ? $this->sectionUrl('verification', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('verification');
        $staff = $this->beginAction('admin', $fallback);
        $id = (int) Request::input('id', 0);
        try {
            switch (Request::text('action')) {
                case 'approve':
                    $request = VerificationService::approve($staff, $id, $this->note());
                    Session::flash('success', 'Verificaste a ' . $request['full_name'] . '. Le avisamos.');
                    break;
                case 'reject':
                    VerificationService::reject($staff, $id, (string) $this->note('reason'));
                    Session::flash('success', 'Solicitud rechazada. Le avisamos con el motivo.');
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
