<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\AuditLog;
use Trevix\Models\Support;
use Trevix\Services\Gemini;
use Trevix\Services\Ix;

/**
 * Soporte IX: solicitudes que IX clasificó en el chat de @soport (errores, sugerencias, reportes, quejas, reclamos,
 * peticiones y las que piden a una persona). El equipo responde desde aquí como la cuenta de soporte (IX se pausa en
 * ese chat) y las cierra o reabre.
 */
final class SupportController extends AdminController
{
    public function handle(): void
    {
        $this->guard('support');
        if (Request::isPost()) {
            $this->act();
        }

        $status = $this->filter('status', array_keys(Support::STATUSES)) ?? 'open';
        $category = $this->filter('category', array_keys(Support::CATEGORIES));
        $page = $this->pageNumber();
        $result = $this->staff() !== null
            ? Support::adminList($status, $category, $page, $this->perPage())
            : ['tickets' => [], 'hasMore' => false];
        $query = ['status' => $status === 'open' ? null : $status, 'category' => $category];

        $this->page('support', 'support', [
            'status'     => $status,
            'category'   => $category,
            'counts'     => $this->staff() !== null ? Support::counts() : array_fill_keys(array_keys(Support::STATUSES), 0),
            'tickets'    => $result['tickets'],
            'account'    => Support::account(),
            'configured' => Gemini::configured(),
            'username'   => (string) Config::get('app.ix.username', ''),
            'prevUrl'    => $page > 1 ? $this->sectionUrl('support', $query + ['page' => $page - 1]) : null,
            'nextUrl'    => $result['hasMore'] ? $this->sectionUrl('support', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('support');
        $staff = $this->beginAction('moderator', $fallback);
        $id = (int) Request::input('id', 0);
        try {
            switch (Request::text('action')) {
                case 'reply':
                    $ticket = Ix::staffReply($staff, $id, $this->cleanText(Request::text('reply', false)));
                    Session::flash('success', 'Respuesta enviada a @' . $ticket['username'] . '. IX queda en pausa en ese chat.');
                    break;
                case 'close':
                    $ticket = Support::findTicket($id);
                    if ($ticket !== null && Support::close($id, (int) $staff['id'])) {
                        AuditLog::record((int) $staff['id'], 'support.close', 'user', (int) $ticket['user_id'], ['username' => $ticket['username'], 'ticket' => $id]);
                    }
                    Session::flash('success', 'Solicitud cerrada.');
                    break;
                case 'reopen':
                    $ticket = Support::findTicket($id);
                    if ($ticket !== null && Support::reopen($id)) {
                        AuditLog::record((int) $staff['id'], 'support.reopen', 'user', (int) $ticket['user_id'], ['username' => $ticket['username'], 'ticket' => $id]);
                    }
                    Session::flash('success', 'Solicitud reabierta.');
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
