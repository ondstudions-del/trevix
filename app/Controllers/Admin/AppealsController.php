<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\Appeal;
use Trevix\Services\AppealService;
use Trevix\Services\Moderation;
use Trevix\Services\UserRecord;

/** Apelaciones de suspensiones y advertencias: aceptarlas (se levanta la sanción) o rechazarlas con motivo. */
final class AppealsController extends AdminController
{
    public function handle(): void
    {
        $this->guard('appeals');
        if (Request::isPost()) {
            $this->act();
        }

        $status = $this->filter('status', array_keys(Appeal::STATUSES)) ?? 'pending';
        $page = $this->pageNumber();
        $staff = $this->staff();
        $result = $staff !== null ? Appeal::adminList($status, $page, $this->perPage()) : ['appeals' => [], 'hasMore' => false];
        $appeals = array_map(static fn (array $a): array => $a + [
            'record' => UserRecord::summary(['id' => $a['user_id'], 'username' => $a['username']]),
            'can_act' => $staff !== null && Moderation::canActOnUser($staff, ['id' => $a['user_id'], 'role' => $a['role']]),
        ], $result['appeals']);
        $query = ['status' => $status === 'pending' ? null : $status];

        $this->page('appeals', 'appeals', [
            'status'  => $status,
            'counts'  => $staff !== null ? Appeal::counts() : array_fill_keys(array_keys(Appeal::STATUSES), 0),
            'appeals' => $appeals,
            'prevUrl' => $page > 1 ? $this->sectionUrl('appeals', $query + ['page' => $page - 1]) : null,
            'nextUrl' => $result['hasMore'] ? $this->sectionUrl('appeals', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('appeals');
        $staff = $this->beginAction('moderator', $fallback);
        $action = Request::text('action');
        if (!in_array($action, ['accept', 'reject'], true)) {
            Response::abort(400, 'Acción no válida.');
        }
        try {
            Session::flash('success', AppealService::resolve($staff, (int) Request::input('id', 0), $action === 'accept', $this->note()));
        } catch (DomainException $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }
}
