<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\AppSetting;
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
        $staff = $this->staff();

        $this->page('support', 'support', [
            'status'     => $status,
            'category'   => $category,
            'counts'     => $staff !== null ? Support::counts() : array_fill_keys(array_keys(Support::STATUSES), 0),
            'tickets'    => $result['tickets'],
            'account'    => Support::account(),
            'configured' => Gemini::configured(),
            'keyHint'    => Gemini::keyHint(),
            'username'   => (string) Config::get('app.ix.username', ''),
            'canConfigure' => $staff !== null && Auth::hasRole('admin', $staff),
            'ix'         => [
                'replies'      => Ix::repliesOn(),
                'welcome'      => Ix::welcomeOn(),
                'model'        => Ix::model(),
                'pause'        => Ix::pauseHours(),
                'instructions' => AppSetting::get('ix_instructions'),
                'perUser'      => (int) Config::get('app.security.rate_limits.ix_reply.max', 30),
                'daily'        => (int) Config::get('app.security.rate_limits.ix_daily.max', 1500),
            ],
            'activity'   => $staff !== null ? Support::activity() : ['ix_today' => 0, 'people_today' => 0, 'chats' => 0],
            'prevUrl'    => $page > 1 ? $this->sectionUrl('support', $query + ['page' => $page - 1]) : null,
            'nextUrl'    => $result['hasMore'] ? $this->sectionUrl('support', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('support');
        $action = Request::text('action');
        $staff = $this->beginAction(in_array($action, ['settings', 'test'], true) ? 'admin' : 'moderator', $fallback);
        $id = (int) Request::input('id', 0);
        try {
            switch ($action) {
                case 'settings':
                    $this->saveSettings($staff, $fallback);
                    break;
                case 'test':
                    try {
                        $test = Ix::testConnection();
                        Session::flash('success', 'IX está conectado a Gemini (' . $test['model'] . ', ' . $test['ms'] . ' ms).');
                    } catch (RuntimeException $e) {
                        Session::flash('error', 'No se pudo conectar con Gemini: ' . $e->getMessage());
                    }
                    break;
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

    private function saveSettings(array $staff, string $back): never
    {
        $model = Request::text('ix_model');
        if (!isset(Ix::MODELS[$model])) {
            $this->done($back, 'Elige un modelo de la lista.', 'error');
        }
        $pause = Request::text('ix_pause_hours');
        if (!preg_match('/^\d{1,2}$/', $pause) || (int) $pause > 72) {
            $this->done($back, 'La pausa debe ser de 0 a 72 horas.', 'error');
        }
        $instructions = trim(str_replace("\r\n", "\n", $this->cleanText(Request::text('ix_instructions', false))));
        if (mb_strlen($instructions) > Ix::MAX_INSTRUCTIONS) {
            $this->done($back, 'Las indicaciones pueden tener como máximo ' . Ix::MAX_INSTRUCTIONS . ' caracteres.', 'error');
        }
        $changes = AppSetting::save([
            'ix_replies'      => Request::input('ix_replies') === '1' ? '1' : '0',
            'ix_welcome'      => Request::input('ix_welcome') === '1' ? '1' : '0',
            'ix_model'        => $model,
            'ix_pause_hours'  => (string) (int) $pause,
            'ix_instructions' => $instructions,
        ]);
        if ($changes === []) {
            $this->done($back, 'No había cambios que guardar.', 'info');
        }
        AuditLog::record((int) $staff['id'], 'settings.update', 'settings', null, $changes);
        $this->done($back, 'Configuración de IX guardada.');
    }
}
