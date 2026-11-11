<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\Appeal;
use Trevix\Models\AuditLog;
use Trevix\Models\Post;
use Trevix\Models\Report;
use Trevix\Models\User;
use Trevix\Models\Warning;
use Trevix\Services\Moderation;
use Trevix\Services\ReportDecision;
use Trevix\Services\UserRecord;
use Trevix\Services\VerificationService;

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
            'warnings'    => Warning::forUser($id, true),
            'warningDays' => VerificationService::rules()['warning_days'],
            'record'      => UserRecord::summary($user),
            'reportsReceived' => Report::againstUser($id, 15),
            'reportsMade' => Report::byReporter($id, 10),
            'appeals'     => Appeal::forUser($id, 20),
            'errors'      => Session::pull('_errors', []),
            'old'         => Session::pull('_old', []),
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
                    $this->done($back, t('Cuenta de @{username} suspendida. Sus sesiones abiertas se cerraron.', ['username' => $target['username']]));
                    // no break
                case 'ban':
                    Moderation::banUser($staff, $target, (string) $this->note('reason'));
                    $this->done($back, t('Cuenta de @{username} baneada sin fecha de fin. Sus sesiones abiertas se cerraron.', ['username' => $target['username']]));
                    // no break
                case 'edit':
                    $this->edit($staff, $target, $back);
                    // no break
                case 'unsuspend':
                    Moderation::unsuspendUser($staff, $target, $this->note());
                    $this->done($back, t('Suspensión levantada: @{username} ya puede entrar.', ['username' => $target['username']]));
                    // no break
                case 'role':
                    $role = Request::text('role');
                    Moderation::setRole($staff, $target, $role);
                    $this->done($back, t('Rol actualizado a {role}.', ['role' => t(User::ROLE_LABELS[$role] ?? $role)]));
                    // no break
                case 'warn':
                    Moderation::warnUser($staff, $target, (string) $this->note('reason'));
                    $this->done($back, t('Advertimos a @{username}. Le llegó un aviso con el motivo.', ['username' => $target['username']]));
                    // no break
                case 'revoke_warning':
                    Moderation::revokeWarning($staff, (int) Request::input('warning_id', 0), $this->note());
                    $this->done($back, 'Advertencia retirada.');
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

    private function edit(array $staff, array $target, string $back): never
    {
        $input = [
            'display_name'   => Request::text('display_name'),
            'username'       => Request::text('username'),
            'email'          => Request::text('email'),
            'phone'          => Request::text('phone'),
            'password'       => Request::text('new_password', false),
            'email_verified' => Request::text('email_verified') === '1',
        ];
        try {
            $changed = Moderation::updateAccount($staff, $target, $input);
        } catch (ActionError $e) {
            $old = $input;
            unset($old['password']);
            $this->backWithErrors($back . '#editar', $e->fields ?: ['display_name' => $e->getMessage()], $old);
        }
        $changed === []
            ? $this->done($back, 'No hiciste cambios.', 'info')
            : $this->done($back, t('Datos actualizados: {fields}.', ['fields' => implode(', ', array_map('t', $changed))]));
    }
}
