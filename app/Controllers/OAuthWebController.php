<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Services\OAuthService;

/** Consentimiento web: Iniciar sesión con TREVIX (authorize). */
final class OAuthWebController extends Controller
{
    public function authorize(): void
    {
        $clientId = trim((string) Request::query('client_id', ''));
        $redirectUri = trim((string) Request::query('redirect_uri', ''));
        $state = trim((string) Request::query('state', ''));

        if ($clientId === '' || $redirectUri === '') {
            Response::abort(400, t('Faltan client_id o redirect_uri.'));
        }

        try {
            $app = OAuthService::appPublicInfo($clientId);
        } catch (ActionError $e) {
            Response::abort($e->status, $e->getMessage());
        }

        if (($app['status'] ?? '') !== 'approved') {
            Response::abort(403, t('Esta app aún no está aprobada.'));
        }

        $user = $this->requireUser();

        if (Request::isPost()) {
            VerifyCsrf::handle();
            $action = Request::text('action');
            if ($action === 'deny') {
                $sep = str_contains($redirectUri, '?') ? '&' : '?';
                $url = $redirectUri . $sep . 'error=access_denied';
                if ($state !== '') {
                    $url .= '&state=' . rawurlencode($state);
                }
                Response::redirect($url);
            }
            try {
                $result = OAuthService::authorize($user, $clientId, $redirectUri, $state !== '' ? $state : null);
                Response::redirect($result['redirect_url']);
            } catch (ActionError $e) {
                Session::flash('error', $e->getMessage());
                Response::redirect(url('oauth/authorize.php', [
                    'client_id' => $clientId,
                    'redirect_uri' => $redirectUri,
                    'state' => $state !== '' ? $state : null,
                ]));
            }
        }

        $this->render('pages/oauth/authorize', [
            'title'        => t('Iniciar sesión con TREVIX'),
            'app'          => $app,
            'clientId'     => $clientId,
            'redirectUri'  => $redirectUri,
            'state'        => $state,
            'user'         => $user,
        ], 'layouts/auth');
    }
}
