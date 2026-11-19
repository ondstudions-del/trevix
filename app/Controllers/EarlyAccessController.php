<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Services\EarlyAccessService;

/** Formulario público: nombre y correo para el acceso anticipado de Android. */
final class EarlyAccessController extends Controller
{
    public function index(): void
    {
        if (Request::isPost()) {
            VerifyCsrf::handle();
            $fullName = Request::text('full_name', false);
            $email = Request::text('email', false);
            try {
                EarlyAccessService::submit($fullName, $email);
            } catch (ActionError $e) {
                $this->backWithErrors(url('early-access.php'), $e->fields ?: ['form' => $e->getMessage()], [
                    'full_name' => mb_substr(trim($fullName), 0, EarlyAccessService::NAME_MAX),
                    'email'     => mb_substr(mb_strtolower(trim($email)), 0, EarlyAccessService::EMAIL_MAX),
                ]);
            }
            Response::redirect(url('early-access.php', ['sent' => 1]));
        }

        $this->render('pages/auth/early-access', [
            'title'  => t('Acceso anticipado para Android') . ' · TREVIX',
            'sent'   => Request::query('sent') === '1',
            'errors' => Session::pull('_errors', []),
            'old'    => Session::pull('_old', []),
        ], 'layouts/auth');
    }
}
