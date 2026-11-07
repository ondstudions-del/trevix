<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Models\AuditLog;
use Trevix\Models\Post;
use Trevix\Models\Report;
use Trevix\Models\User;
use Trevix\Services\Moderation;
use Trevix\Services\ReportDecision;

/** Listado y ficha de cuentas: suspensiones, roles y verificación. */
final class UsersController extends AdminController
{
    public function handle(): void
    {
        $this->guard('users');
        if (Request::isPost()) {
            $this->act();
        }
        $id = (int) Request::query('id');
        if ($id > 0) {
            $this->detail($id);
            return;
        }

        $q = mb_substr(Request::query('q'), 0, 100);
        $role = $this->filter('role', array_keys(User::ROLE_LABELS));
        $status = $this->filter('status', array_keys(User::STATUS_LABELS));
        $page = $this->pageNumber();
        $result = $this->staff() !== null
            ? User::adminList($q, $role, $status, $page, $this->perPage())
            : ['users' => [], 'hasMore' => false];
        $query = ['q' => $q, 'role' => $role, 'status' => $status];

        $this->page('users', 'users', [
            'q'       => $q,
            'role'    => $role,
            'status'  => $status,
            'users'   => $result['users'],
            'prevUrl' => $page > 1 ? $this->sectionUrl('users', $query + ['page' => $page - 1]) : null,
            'nextUrl' => $result['hasMore'] ? $this->sectionUrl('users', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function detail(int $id): void
    {
        $staff = $this->staff();
        $user = $staff !== null ? User::findForAdmin($id) : null;
        if ($user === null) {
            Response::abort(404, 'Esta cuenta no existe.');
        }
        $canAct = Moderation::canActOnUser($staff, $user);

        $this->page('users', 'user', [
            'user'        => $user,
            'canAct'      => $canAct,
            'isAdmin'     => Moderation::isAdmin($staff),
            'isSelf'      => (int) $staff['id'] === (int) $user['id'],
            'openReports' => Report::openAgainstUser($id),
            'posts'       => Post::adminList('@' . $user['username'], null, 1, 5)['posts'],
            'history'     => AuditLog::forTarget('user', $id),
            'durations'   => $this->durations($staff),
        ]);
    }

    private function durations(array $staff): array
    {
        return ReportDecision::durations($staff);
    }

    private function act(): never
    {
        $id = (int) Request::input('id', 0);
        $back = $this->sectionUrl('users', ['id' => $id]);
        $staff = $this->beginAction('moderator', $back);
        $target = User::findForAdmin($id);
        if ($target === null) {
            $this->done($this->sectionUrl('users'), 'Esta cuenta ya no existe.', 'error');
        }

        try {
            switch (Request::text('action')) {
                case 'suspend':
                    $days = (int) Request::input('days', 7);
                    Moderation::suspendUser($staff, $target, $days > 0 ? $days : null, (string) $this->note('reason'));
                    $this->done($back, 'Cuenta de @' . $target['username'] . ' suspendida. Sus sesiones abiertas se cerraron.');
                    // no break
                case 'unsuspend':
                    Moderation::unsuspendUser($staff, $target, $this->note());
                    $this->done($back, 'Suspensión levantada: @' . $target['username'] . ' ya puede entrar.');
                    // no break
                case 'role':
                    $role = Request::text('role');
                    Moderation::setRole($staff, $target, $role);
                    $this->done($back, 'Rol actualizado a ' . (User::ROLE_LABELS[$role] ?? $role) . '.');
                    // no break
                case 'verify':
                case 'unverify':
                    $verify = Request::text('action') === 'verify';
                    Moderation::setVerified($staff, $target, $verify);
                    $this->done($back, $verify ? 'Insignia de verificación añadida.' : 'Insignia de verificación retirada.');
                    // no break
                default:
                    Response::abort(400, 'Acción no válida.');
            }
        } catch (DomainException $e) {
            $this->done($back, $e->getMessage(), 'error');
        }
    }
}
