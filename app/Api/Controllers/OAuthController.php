<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Services\MediaUpload;
use Trevix\Services\OAuthService;

/** Apps OAuth de desarrolladores + endpoints públicos token/userinfo. */
final class OAuthController extends ApiController
{
    /** GET /me/oauth/apps */
    public function mine(): never
    {
        Reply::ok(OAuthService::listMine($this->user()));
    }

    /** GET /me/oauth/apps/{id} — detalle, claves, HTML y pasos. */
    public function show(string $id): never
    {
        Reply::ok(OAuthService::showMine($this->user(), (int) $id));
    }

    /** POST /me/oauth/apps/{id}/regenerate-secret */
    public function regenerateSecret(string $id): never
    {
        Reply::ok(OAuthService::regenerateSecret($this->user(), (int) $id));
    }

    /** POST /me/oauth/apps (multipart: name, description, platform, package_name|website_url, redirect_uris, icon?) */
    public function create(): never
    {
        $result = OAuthService::create($this->user(), [
            'name'          => Input::str('name'),
            'description'   => Input::str('description'),
            'platform'      => Input::str('platform'),
            'package_name'  => Input::str('package_name'),
            'website_url'   => Input::str('website_url'),
            'redirect_uris' => Input::str('redirect_uris', false),
        ], MediaUpload::collect('icon'));
        Reply::ok($result, [], 201);
    }

    /** GET /admin/oauth/apps?page=&status=pending|approved|rejected|all — cola (mod/admin). */
    public function pending(): never
    {
        $status = Request::queryIn('status', ['pending', 'approved', 'rejected', 'all'], 'pending');
        $result = OAuthService::pendingForStaff($this->user(), $this->pageNumber(), $status);
        Reply::ok($result['items'], $this->nextPage($result['hasMore']));
    }

    /** POST /admin/oauth/apps/{id}/approve {note?} */
    public function approve(string $id): never
    {
        Reply::ok(OAuthService::approve($this->user(), (int) $id, Input::str('note', false) ?: null));
    }

    /** POST /admin/oauth/apps/{id}/reject {note?} */
    public function reject(string $id): never
    {
        Reply::ok(OAuthService::reject($this->user(), (int) $id, Input::str('note', false) ?: null));
    }

    /**
     * POST /oauth/authorize {client_id, redirect_uri, state?}
     * Usuario TREVIX autenticado concede acceso a la app.
     */
    public function authorize(): never
    {
        Reply::ok(OAuthService::authorize(
            $this->user(),
            Input::str('client_id'),
            Input::str('redirect_uri'),
            Input::str('state') ?: null
        ));
    }

    /**
     * POST /oauth/token {client_id, client_secret, code, redirect_uri}
     * Público (credenciales de la app). Devuelve access_token + perfil público.
     */
    public function token(): never
    {
        Reply::ok(OAuthService::token(
            Input::str('client_id'),
            Input::str('client_secret'),
            Input::str('code'),
            Input::str('redirect_uri')
        ));
    }

    /** GET /oauth/userinfo — Bearer del token de la app. */
    public function userinfo(): never
    {
        $header = (string) Request::header('Authorization');
        if (!preg_match('/^Bearer\s+(\S+)$/i', $header, $m)) {
            throw new ActionError('Falta el token Bearer.', 401);
        }
        Reply::ok(OAuthService::userinfo($m[1]));
    }

    /** GET /oauth/apps/{clientId} — info pública de la app (para pantallas de consentimiento). */
    public function showApp(string $clientId): never
    {
        Reply::ok(OAuthService::appPublicInfo($clientId));
    }
}
