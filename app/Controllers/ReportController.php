<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Report;
use Trevix\Services\ReportService;

/**
 * Reportar contenido o cuentas: report.php (formulario completo, funciona sin JavaScript) y
 * api/reports.php (envío). Solo se puede reportar lo que uno puede ver y que no es propio.
 */
final class ReportController extends Controller
{
    public function page(): void
    {
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Envía el reporte desde el formulario.');
        }
        $user = $this->requireUser();
        $type = Request::queryIn('type', array_keys(Report::TYPES), '');
        $target = $type !== '' ? ReportService::target($type, (int) Request::query('id'), (int) $user['id']) : null;
        if ($target === null) {
            Response::abort(404, 'No encontramos ese contenido o no puedes reportarlo.');
        }

        $this->render('pages/report', [
            'title'   => t('Reportar') . ' · TREVIX',
            'type'    => $type,
            'id'      => (int) Request::query('id'),
            'target'  => $target,
            'errors'  => Session::pull('_errors', []),
            'old'     => Session::pull('_old', []),
            'maxDetails' => (int) Config::get('app.limits.report_details', 1000),
        ]);
    }

    public function api(): void
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $uid = (int) $this->requireUser()['id'];

        $type = (string) Request::input('type', '');
        $id = (int) Request::input('id', 0);
        $reason = Request::text('reason');
        $details = Request::text('details', false);

        try {
            $result = ReportService::submit($uid, $type, $id, $reason, $details);
        } catch (ActionError $e) {
            if ($e->fields === []) {
                $this->fail($e->getMessage(), $e->status, $e->status === 404 ? url('feed.php') : url('report.php', ['type' => $type, 'id' => $id]));
            }
            if (Request::wantsJson()) {
                Response::json(['ok' => false, 'error' => $e->getMessage(), 'errors' => $e->fields], 422);
            }
            $this->backWithErrors(url('report.php', ['type' => $type, 'id' => $id]), $e->fields, [
                'reason'  => $reason,
                'details' => $this->cleanText($details),
            ]);
        }

        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'message' => $result['message'], 'status' => $result['status']]);
        }
        Session::flash('success', $result['message']);
        Response::redirect($result['target']['url']);
    }
}
