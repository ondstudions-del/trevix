<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Kernel;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Models\ApiToken;
use Trevix\Models\User;
use Trevix\Services\AccountService;
use Trevix\Services\SettingsService;

/** Inicio de sesión con token Bearer, registro, cierre de sesión y sesiones de la app. */
final class AuthController extends ApiController
{
    /** POST /auth/login {identifier, password, device_name?} */
    public function login(): never
    {
        $result = AccountService::authenticate(Input::str('identifier'), Input::str('password', false));
        $user = $result['user'];
        Reply::ok($this->session((int) $user['id'], (string) $user['password_hash']) + ['reactivated' => $result['reactivated']]);
    }

    /** POST /auth/register {display_name, username, email, birth_date, password, password_confirmation, terms, device_name?} */
    public function register(): never
    {
        $result = AccountService::register([
            'display_name'          => Input::str('display_name'),
            'username'              => Input::str('username'),
            'email'                 => Input::str('email'),
            'birth_date'            => Input::str('birth_date'),
            'password'              => Input::str('password', false),
            'password_confirmation' => Input::str('password_confirmation', false),
            'terms'                 => Input::bool('terms') === true,
        ]);
        Reply::ok($this->session($result['id'], $result['password_hash']) + ['verification_email_sent' => $result['mail_sent']], [], 201);
    }

    /** POST /auth/password/forgot {email} — misma respuesta exista o no la cuenta. */
    public function forgotPassword(): never
    {
        Reply::ok(['message' => AccountService::sendResetLink(Input::str('email'))]);
    }

    /** POST /auth/logout — cierra la sesión de este dispositivo. */
    public function logout(): never
    {
        ApiToken::revoke((int) Kernel::token()['id']);
        Reply::ok(['message' => 'Cerraste la sesión.']);
    }

    /** GET /auth/sessions — sesiones abiertas de la app (la actual va marcada). */
    public function sessions(): never
    {
        $current = (int) Kernel::token()['id'];
        Reply::ok(array_map(static fn (array $t): array => [
            'id'           => $t['id'],
            'name'         => $t['name'],
            'current'      => $t['id'] === $current,
            'last_used_at' => Present::date($t['last_used_at']),
            'last_ip'      => $t['last_ip'],
            'expires_at'   => Present::date($t['expires_at']),
            'created_at'   => Present::date($t['created_at']),
        ], ApiToken::listFor($this->uid())));
    }

    /** DELETE /auth/sessions/{id} */
    public function revokeSession(string $id): never
    {
        if (!ApiToken::revokeFor($this->uid(), (int) $id)) {
            $this->notFound('Esa sesión no existe o ya se cerró.');
        }
        Reply::ok(['message' => 'Cerraste esa sesión.', 'current' => (int) $id === (int) Kernel::token()['id']]);
    }

    /**
     * POST /auth/sessions/logout-others {password} — igual que en la web: renueva el hash de la contraseña,
     * con lo que se cierran las sesiones web y de la app en los demás dispositivos. Esta sigue abierta.
     */
    public function logoutOthers(): never
    {
        $user = $this->user();
        $hash = SettingsService::rehashPassword($user, Input::str('password', false), 'password');
        $tokenId = (int) Kernel::token()['id'];
        ApiToken::refreshFingerprint($tokenId, $hash);
        ApiToken::revokeAllFor((int) $user['id'], $tokenId);
        Reply::ok(['message' => 'Cerramos la sesión en todos tus otros dispositivos.']);
    }

    /** Emite el token y devuelve la cuenta completa. */
    private function session(int $userId, string $passwordHash): array
    {
        $device = Input::str('device_name');
        $issued = ApiToken::issue($userId, $passwordHash, $device !== '' ? $device : 'App TREVIX');
        $user = User::findForSession($userId) ?? throw new ActionError('No se pudo iniciar sesión.', 500);
        unset($user['password_hash']);
        Auth::actingAs($user);
        return [
            'token'      => $issued['token'],
            'token_type' => 'Bearer',
            'expires_at' => Present::date($issued['expires_at']),
            'user'       => Present::me($user),
        ];
    }
}
