<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Appeal;
use Trevix\Models\Warning;
use Trevix\Services\AppealService;

/** Apelar una suspensión (sin sesión, con usuario y contraseña) o una advertencia (con la sesión iniciada). */
final class AppealController extends Controller
{
    public function suspension(): void
    {
        if (Auth::check()) {
            Response::redirect(url('appeals.php'));
        }
        if (Request::isPost()) {
            VerifyCsrf::handle();
            $identifier = mb_strtolower(Request::text('identifier'));
            $message = Request::text('message', false);
            try {
                AppealService::appealSuspension($identifier, Request::text('password', false), $message);
            } catch (ActionError $e) {
                $this->backWithErrors(url('appeal.php'), $e->fields ?: ['form' => $e->getMessage()], [
                    'identifier' => mb_substr($identifier, 0, 190),
                    'message'    => mb_substr($message, 0, AppealService::MESSAGE_MAX),
                ]);
            }
            Response::redirect(url('appeal.php', ['sent' => 1]));
        }

        $this->render('pages/auth/appeal', [
            'title'  => t('Apelar una suspensión') . ' · TREVIX',
            'sent'   => Request::query('sent') === '1',
            'errors' => Session::pull('_errors', []),
            'old'    => Session::pull('_old', []),
        ], 'layouts/auth');
    }

    public function mine(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            VerifyCsrf::handle();
            $user = $this->requireUser();
            $warningId = (int) Request::input('warning_id', 0);
            $message = Request::text('message', false);
            $back = url('appeals.php') . '#advertencia-' . $warningId;
            try {
                AppealService::appealWarning($user, $warningId, $message);
            } catch (ActionError $e) {
                $this->backWithErrors($back, ['warning_' . $warningId => $e->fields['message'] ?? $e->getMessage()], [
                    'warning_id' => $warningId,
                    'message'    => mb_substr($message, 0, AppealService::MESSAGE_MAX),
                ]);
            }
            Session::flash('success', 'Enviamos tu apelación. El equipo la revisará y te avisaremos.');
            Response::redirect($back);
        }

        $uid = (int) Auth::id();
        $appeals = Appeal::forUser($uid);
        $pendingWarnings = [];
        foreach ($appeals as $a) {
            if ($a['type'] === 'warning' && $a['status'] === 'pending') {
                $pendingWarnings[(int) $a['warning_id']] = true;
            }
        }
        $this->render('pages/appeals', [
            'title'           => t('Advertencias y apelaciones') . ' · TREVIX',
            'activeNav'       => 'settings',
            'warnings'        => Warning::forUser($uid),
            'appeals'         => $appeals,
            'pendingWarnings' => $pendingWarnings,
            'errors'          => Session::pull('_errors', []),
            'old'             => Session::pull('_old', []),
        ]);
    }
}
