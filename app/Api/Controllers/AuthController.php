<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Kernel;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Request;
use Trevix\Models\ApiToken;
use Trevix\Models\DeviceLink;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Services\AccountService;
use Trevix\Services\AppealService;
use Trevix\Services\SettingsService;

/** Inicio de sesión con token Bearer, registro, cierre de sesión, sesiones y vinculación por QR. */
final class AuthController extends ApiController
{
    /** POST /auth/login {identifier, password, device_name?, device_type?} */
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

    /** POST /auth/appeal {identifier, password, message} — una cuenta suspendida apela sin iniciar sesión. */
    public function appeal(): never
    {
        $id = AppealService::appealSuspension(Input::str('identifier'), Input::str('password', false), Input::str('message', false));
        Reply::ok([
            'appeal_id' => $id,
            'message'   => 'Recibimos tu apelación. Te escribiremos al correo de tu cuenta cuando el equipo la revise.',
        ], [], 201);
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
            'device_type'  => $t['device_type'] ?? 'other',
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

    /** Alias antiguos auth/link/* → usar VINCRIPTAR. */
    public function linkDeprecated(string $code = ''): never
    {
        unset($code);
        throw new ActionError('La vinculación por QR ya no está disponible. Usa VINCRIPTAR.', 410);
    }

    /** POST /auth/vincriptar/start — dispositivo nuevo genera VINCODE. */
    public function vincriptarStart(): never
    {
        $ip = (string) (Request::ip() ?? '0.0.0.0');
        if (RateLimit::tooManyAttempts('device_link_start', $ip)) {
            throw new ActionError('Espera un momento antes de generar otro VINCODE.', 429);
        }
        RateLimit::hit('device_link_start', $ip);
        $name = Input::str('device_name');
        if ($name === '') {
            $name = 'Dispositivo TREVIX';
        }
        $challenge = DeviceLink::startGuest($name, Input::str('device_type') ?: null, $ip);
        Reply::ok([
            'id'         => $challenge['id'],
            'code'       => $challenge['code'],
            'payload'    => $challenge['payload'],
            'seed'       => $challenge['seed'],
            'expires_at' => Present::date($challenge['expires_at']),
            'ttl'        => DeviceLink::TTL_SECONDS,
            'status'     => 'pending',
        ], [], 201);
    }

    /** GET /auth/vincriptar/{code}/status — poll del dispositivo nuevo. */
    public function vincriptarStatus(string $code): never
    {
        $row = DeviceLink::findByCode($code);
        if ($row === null) {
            throw new ActionError('Ese VINCODE no existe o ya venció.', 404);
        }
        $payload = [
            'id'                => $row['id'],
            'code'              => $row['code'],
            'status'            => $row['status'],
            'expires_at'        => Present::date($row['expires_at']),
            'guest_device_name' => $row['guest_device_name'],
            'guest_device_type' => $row['guest_device_type'],
            'ttl'               => DeviceLink::TTL_SECONDS,
        ];

        if ($row['status'] === 'approved' && $row['host_user_id'] !== null) {
            $plain = DeviceLink::takeToken((int) $row['id']);
            if ($plain !== null) {
                $user = User::findForSession((int) $row['host_user_id']);
                if ($user === null) {
                    throw new ActionError('No se pudo completar la vinculación.', 500);
                }
                unset($user['password_hash']);
                Auth::actingAs($user);
                $payload['token'] = $plain;
                $payload['token_type'] = 'Bearer';
                $payload['user'] = Present::me($user);
            }
        }
        Reply::ok($payload);
    }

    /** POST /auth/vincriptar/scan {code} — cuenta autenticada lee el VINCODE o el código manual. */
    public function vincriptarScan(): never
    {
        $uid = $this->uid();
        if (RateLimit::tooManyAttempts('device_link_scan', (string) $uid)) {
            throw new ActionError('Demasiados intentos. Espera un momento.', 429);
        }
        RateLimit::hit('device_link_scan', (string) $uid);

        $row = DeviceLink::scan(Input::str('code'), $uid);
        if ($row === null) {
            throw ActionError::field('code', 'Ese VINCODE no es válido, ya se usó o venció.');
        }
        Reply::ok([
            'id'                => $row['id'],
            'code'              => $row['code'],
            'status'            => $row['status'],
            'expires_at'        => Present::date($row['expires_at']),
            'guest_device_name' => $row['guest_device_name'],
            'guest_device_type' => $row['guest_device_type'],
            'message'           => 'Confirma para vincular este dispositivo a tu cuenta.',
        ]);
    }

    /** POST /auth/vincriptar/approve {id} */
    public function vincriptarApprove(): never
    {
        $id = (int) Input::int('id');
        $row = DeviceLink::findForHost($id, $this->uid());
        if ($row === null) {
            throw new ActionError('Esa vinculación no existe.', 404);
        }
        if ($row['status'] !== 'claimed') {
            throw new ActionError('Esa vinculación ya no se puede confirmar.', 409);
        }
        $user = User::findForSession($this->uid()) ?? throw new ActionError('No se pudo vincular.', 500);
        $issued = ApiToken::issue(
            (int) $user['id'],
            (string) $user['password_hash'],
            (string) ($row['guest_device_name'] ?: 'Dispositivo vinculado'),
            $row['guest_device_type'] ?? 'other'
        );
        if (!DeviceLink::approve($id, $issued['id'], $issued['token'])) {
            ApiToken::revoke($issued['id']);
            throw new ActionError('Esa vinculación ya no está disponible.', 409);
        }
        Reply::ok([
            'id'                => $id,
            'status'            => 'approved',
            'message'           => 'Dispositivo vinculado.',
            'guest_device_name' => $row['guest_device_name'],
        ]);
    }

    /** POST /auth/vincriptar/reject {id} — la cuenta autenticada rechaza. */
    public function vincriptarReject(): never
    {
        $id = (int) Input::int('id');
        DeviceLink::cancel($id, $this->uid());
        Reply::ok(['message' => 'Rechazaste la vinculación.', 'status' => 'cancelled']);
    }

    /** POST /auth/vincriptar/cancel {id, code} — el dispositivo nuevo cancela su VINCODE. */
    public function vincriptarCancelGuest(): never
    {
        $id = (int) Input::int('id');
        $code = Input::str('code');
        DeviceLink::cancelByGuest($id, $code);
        Reply::ok(['message' => 'Cancelaste la vinculación.', 'status' => 'cancelled']);
    }

    /** Emite el token y devuelve la cuenta completa. */
    private function session(int $userId, string $passwordHash): array
    {
        $device = Input::str('device_name');
        $type = Input::str('device_type') ?: null;
        $issued = ApiToken::issue($userId, $passwordHash, $device !== '' ? $device : 'App TREVIX', $type);
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
