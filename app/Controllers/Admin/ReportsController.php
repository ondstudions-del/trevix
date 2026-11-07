<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Models\AuditLog;
use Trevix\Models\Report;
use Trevix\Services\Moderation;
use Trevix\Services\ReportDecision;

/** Cola de reportes agrupados por objetivo y ficha de cada objetivo con las medidas disponibles. */
final class ReportsController extends AdminController
{
    /** Duraciones de suspensión que ofrece el formulario (días; 0 = sin fecha de fin). */
    public const DURATIONS = ReportDecision::DURATIONS;

    public function handle(): void
    {
        $this->guard('reports');
        if (Request::isPost()) {
            $this->act();
        }
        $type = $this->filter('type', array_keys(Report::TYPES));
        $id = (int) Request::query('id');
        if ($type !== null && $id > 0) {
            $this->detail($type, $id);
            return;
        }
        $this->index($type);
    }

    private function index(?string $type): void
    {
        $status = Request::queryIn('status', array_keys(Report::STATUS_GROUPS), 'open');
        $page = $this->pageNumber();
        $staff = $this->staff();
        $result = $staff !== null ? Report::targets($status, $type, $page, $this->perPage()) : ['targets' => [], 'hasMore' => false];

        $this->page('reports', 'reports', [
            'status'  => $status,
            'type'    => $type,
            'targets' => $result['targets'],
            'counts'  => $staff !== null ? Report::openCountsByType() : array_fill_keys(array_keys(Report::TYPES), 0),
            'prevUrl' => $page > 1 ? $this->sectionUrl('reports', ['status' => $status, 'type' => $type, 'page' => $page - 1]) : null,
            'nextUrl' => $result['hasMore'] ? $this->sectionUrl('reports', ['status' => $status, 'type' => $type, 'page' => $page + 1]) : null,
        ]);
    }

    private function detail(string $type, int $id): void
    {
        $staff = $this->staff();
        if ($staff === null) {
            Response::abort(404, 'Este reporte no existe.');
        }
        $reports = Report::forTarget($type, $id);
        if ($reports === []) {
            Response::abort(404, 'Este reporte no existe.');
        }
        $preview = Report::preview($type, $id);
        $pending = array_filter($reports, static fn (array $r) => in_array($r['status'], ['open', 'reviewing'], true));

        $this->page('reports', 'report', [
            'type'      => $type,
            'id'        => $id,
            'preview'   => $preview,
            'reports'   => $reports,
            'pending'   => count($pending),
            'reviewing' => in_array('reviewing', array_column($pending, 'status'), true),
            'measures'  => $preview !== null ? $this->measures($staff, $type, $preview) : [],
            'durations' => $this->durations($staff),
            'history'   => AuditLog::forTarget($type, $id),
        ]);
    }

    /** Medidas que quien revisa puede aplicar a este objetivo. */
    private function measures(array $staff, string $type, array $preview): array
    {
        return ReportDecision::measures($staff, $type, $preview);
    }

    private function durations(array $staff): array
    {
        return ReportDecision::durations($staff);
    }

    private function act(): never
    {
        $type = (string) Request::input('type', '');
        $id = (int) Request::input('id', 0);
        if (!isset(Report::TYPES[$type]) || $id < 1) {
            Response::abort(400, 'Reporte no válido.');
        }
        $detailUrl = $this->sectionUrl('reports', ['type' => $type, 'id' => $id]);
        $staff = $this->beginAction('moderator', $detailUrl);
        $action = Request::text('action');
        $note = $this->note();

        try {
            switch ($action) {
                case 'take':
                    Moderation::takeReports($staff, $type, $id);
                    $this->done($detailUrl, 'Marcaste estos reportes como "en revisión".');
                    // no break
                case 'dismiss':
                    Moderation::closeReports($staff, $type, $id, 'dismissed', $note);
                    $this->done($this->sectionUrl('reports'), 'Reportes descartados: el contenido se mantiene.');
                    // no break
                case 'resolve':
                    $message = ReportDecision::resolve($staff, $type, $id, Request::text('measure') ?: 'none', (int) Request::input('days', 7), $note);
                    $this->done($this->sectionUrl('reports'), $message);
                    // no break
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (DomainException $e) {
            $this->done($detailUrl, $e->getMessage(), 'error');
        }
    }
}
