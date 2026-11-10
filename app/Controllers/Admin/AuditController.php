<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Models\AuditLog;

/** Registro de auditoría (solo administradores, solo lectura). */
final class AuditController extends AdminController
{
    public const GROUPS = [
        'report'    => 'Reportes',
        'post'      => 'Publicaciones',
        'comment'   => 'Comentarios',
        'message'   => 'Mensajes',
        'story'     => 'Historias',
        'user'      => 'Cuentas',
        'community' => 'Comunidades',
        'support'   => 'Soporte',
        'settings'  => 'Configuración',
    ];

    public function index(): void
    {
        $this->guard('audit');
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Esta página no acepta envíos.');
        }

        $group = $this->filter('group', array_keys(self::GROUPS));
        $adminId = (int) Request::query('admin') ?: null;
        $page = $this->pageNumber();
        $staff = $this->staff();
        $result = $staff !== null ? AuditLog::latest($group, $adminId, $page, 40) : ['entries' => [], 'hasMore' => false];
        $query = ['group' => $group, 'admin' => $adminId];

        $this->page('audit', 'audit', [
            'group'   => $group,
            'adminId' => $adminId,
            'actors'  => $staff !== null ? AuditLog::actors() : [],
            'entries' => $result['entries'],
            'prevUrl' => $page > 1 ? $this->sectionUrl('audit', $query + ['page' => $page - 1]) : null,
            'nextUrl' => $result['hasMore'] ? $this->sectionUrl('audit', $query + ['page' => $page + 1]) : null,
        ]);
    }
}
