<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use Trevix\Core\Auth;
use Trevix\Core\Response;
use Trevix\Core\Request;
use Trevix\Models\AdminStats;
use Trevix\Models\AuditLog;
use Trevix\Models\Report;

final class DashboardController extends AdminController
{
    public function index(): void
    {
        $this->guard('dashboard');
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Esta página no acepta envíos.');
        }

        $staff = $this->staff();
        $this->page('dashboard', 'dashboard', [
            'stats'   => $staff !== null ? AdminStats::overview() : null,
            'reports' => $staff !== null ? Report::targets('open', null, 1, 5)['targets'] : [],
            'audit'   => $staff !== null && Auth::hasRole('admin', $staff) ? AuditLog::latest(null, null, 1, 6)['entries'] : null,
        ]);
    }
}
