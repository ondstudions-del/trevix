<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use PDOException;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Password;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\RedirectIfAuthenticated;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\ApiToken;
use Trevix\Models\AppSetting;
use Trevix\Models\DeviceLink;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Models\UserToken;
use Trevix\Services\AccountMail;
use Trevix\Services\AccountRules;
use Trevix\Services\AccountService;

/** Registro, inicio y cierre de sesión, recuperación de contraseña y confirmación de correo. */
final class AuthController extends Controller
{
    public function login(): void
    {
        RedirectIfAuthenticated::handle();

        if (Request::isPost()) {
            VerifyCsrf::handle();
            $this->attemptLogin();
        }

        $this->render('pages/auth/login', [
            'title'  => t('Iniciar sesión') . ' · TREVIX',
            'errors' => Session::pull('_errors', []),
            'old'    => Session::pull('_old', []),
        ], 'layouts/auth');
    }

    public function register(): void
    {
        RedirectIfAuthenticated::handle();
        $open = AccountService::registrationOpen();

        if (Request::isPost()) {
            VerifyCsrf::handle();
            if (!$open) {
                $this->backTo('register.php', ['form' => 'El registro de cuentas nuevas está cerrado en este momento.'], []);
            }
            $this->attemptRegister();
        }

        $this->render('pages/auth/register', [
            'title'       => t('Crear cuenta') . ' · TREVIX',
            'closed'      => !$open,
            'maintenance' => AppSetting::flag('maintenance_mode'),
            'passwordMin' => (int) Config::get('app.security.password_min_length'),
            'errors'      => Session::pull('_errors', []),
            'old'         => Session::pull('_old', []),
        ], 'layouts/auth');
    }

    public function forgotPassword(): void
    {
        RedirectIfAuthenticated::handle();

        if (Request::isPost()) {
            VerifyCsrf::handle();
            $this->sendResetLink();
        }

        $this->render('pages/auth/forgot-password', [
            'title'  => t('Recuperar contraseña') . ' · TREVIX',
            'errors' => Session::pull('_errors', []),
            'old'    => Session::pull('_old', []),
        ], 'layouts/auth');
    }

    public function resetPassword(): void
    {
        $token = Request::isPost() ? Request::text('token') : Request::query('token');
        $record = UserToken::findValid($token, ['password_reset']);

        if (Request::isPost()) {
            VerifyCsrf::handle();
            if ($record !== null) {
                $this->applyNewPassword($record, $token);
            }
        }

        $this->render('pages/auth/reset-password', [
            'title'       => t('Nueva contraseña') . ' · TREVIX',
            'valid'       => $record !== null,
            'token'       => $record !== null ? $token : '',
            'passwordMin' => (int) Config::get('app.security.password_min_length'),
            'errors'      => Session::pull('_errors', []),
        ], 'layouts/auth');
    }

    /** Confirma el correo de la cuenta o un cambio de correo, según el tipo de token. */
    public function verifyEmail(): void
    {
        $record = UserToken::findValid(Request::query('token'), ['email_verification', 'email_change']);
        $destination = Auth::check() ? url('settings.php', ['section' => 'account']) : url('login.php');

        if ($record === null || !UserToken::consume((int) $record['id'])) {
            Session::flash('error', 'El enlace no es válido o ya venció. Solicita uno nuevo desde Configuración › Cuenta.');
            Response::redirect($destination);
        }

        $userId = (int) $record['user_id'];

        if ($record['type'] === 'email_verification') {
            User::markEmailVerified($userId);
            Session::flash('success', 'Tu correo quedó confirmado. ¡Gracias!');
            Response::redirect($destination);
        }

        $newEmail = (string) $record['payload'];
        $user = User::findBasicById($userId);
        if ($user === null || AccountRules::email($newEmail) !== null || User::emailExists($newEmail, $userId)) {
            Session::flash('error', 'No se pudo cambiar el correo: esa dirección ya está en uso.');
            Response::redirect($destination);
        }

        try {
            User::updateEmail($userId, $newEmail);
        } catch (PDOException $e) {
            if ($e->getCode() !== '23000') {
                throw $e;
            }
            Session::flash('error', 'No se pudo cambiar el correo: esa dirección ya está en uso.');
            Response::redirect($destination);
        }

        AccountMail::securityNotice((string) $user['email'], (string) $user['display_name'],
            t('El correo de tu cuenta se cambió a {email}.', ['email' => $newEmail]));
        Session::flash('success', t('Tu correo ahora es {email}.', ['email' => $newEmail]));
        Response::redirect($destination);
    }

    public function logout(): void
    {
        if (!Request::isPost()) {
            Response::abort(405, 'Usa el botón “Cerrar sesión” para salir de tu cuenta.');
        }
        VerifyCsrf::handle();
        Auth::logout();
        Response::redirect(url('login.php'));
    }

    /** Vinculación rápida por código/QR (anfitrión autenticado o guest en login). */
    public function link(): void
    {
        if (Auth::check()) {
            $this->linkHost();
            return;
        }
        $this->linkGuest();
    }

    private function linkHost(): void
    {
        $user = Auth::user();
        $uid = (int) $user['id'];
        $challenge = Session::get('_link_challenge');

        if (Request::isPost()) {
            VerifyCsrf::handle();
            $action = Request::text('action');
            if ($action === 'start' || $challenge === null) {
                if (RateLimit::tooManyAttempts('device_link_start', (string) $uid)) {
                    Session::flash('error', 'Espera un momento antes de generar otro código.');
                    Response::redirect(url('link.php'));
                }
                RateLimit::hit('device_link_start', (string) $uid);
                $challenge = DeviceLink::start($uid);
                Session::set('_link_challenge', $challenge);
                Response::redirect(url('link.php'));
            }
            if ($action === 'approve' && is_array($challenge)) {
                $row = DeviceLink::findForHost((int) $challenge['id'], $uid);
                if ($row === null || $row['status'] !== 'claimed') {
                    Session::flash('error', 'Todavía nadie ha pedido vincularse, o el código ya no vale.');
                    Response::redirect(url('link.php'));
                }
                $full = User::findForSession($uid);
                $issued = ApiToken::issue($uid, (string) $full['password_hash'], (string) ($row['guest_device_name'] ?: 'Dispositivo vinculado'), $row['guest_device_type'] ?? 'other');
                if (!DeviceLink::approve((int) $challenge['id'], $issued['id'], $issued['token'])) {
                    ApiToken::revoke($issued['id']);
                    Session::flash('error', 'Esa vinculación ya no está disponible.');
                } else {
                    Session::flash('success', 'Dispositivo vinculado.');
                    Session::forget('_link_challenge');
                }
                Response::redirect(url('settings.php', ['section' => 'security']));
            }
            if ($action === 'cancel' && is_array($challenge)) {
                DeviceLink::cancel((int) $challenge['id'], $uid);
                Session::forget('_link_challenge');
                Response::redirect(url('link.php'));
            }
        }

        if ($challenge === null) {
            if (RateLimit::tooManyAttempts('device_link_start', (string) $uid)) {
                $challenge = null;
            } else {
                RateLimit::hit('device_link_start', (string) $uid);
                $challenge = DeviceLink::start($uid);
                Session::set('_link_challenge', $challenge);
            }
        }

        $status = null;
        if (is_array($challenge)) {
            $row = DeviceLink::findByCode((string) $challenge['code']);
            $status = $row;
            if ($row === null || in_array($row['status'], ['expired', 'cancelled', 'approved'], true)) {
                Session::forget('_link_challenge');
                if ($row === null || $row['status'] === 'expired') {
                    $challenge = DeviceLink::start($uid);
                    Session::set('_link_challenge', $challenge);
                    $status = DeviceLink::findByCode((string) $challenge['code']);
                }
            }
        }

        $this->render('pages/auth/link', [
            'title'     => t('Vincular dispositivo') . ' · TREVIX',
            'mode'      => 'host',
            'challenge' => $challenge,
            'status'    => $status,
            'errors'    => Session::pull('_errors', []),
        ], 'layouts/auth');
    }

    private function linkGuest(): void
    {
        $code = Session::get('_link_guest_code');
        $status = is_string($code) && $code !== '' ? DeviceLink::findByCode($code) : null;

        if (Request::isPost()) {
            VerifyCsrf::handle();
            $action = Request::text('action');
            if ($action === 'claim') {
                $ip = Request::ip();
                if (RateLimit::tooManyAttempts('device_link_claim', $ip)) {
                    $this->backTo('link.php', ['code' => 'Demasiados intentos. Espera un momento.'], []);
                }
                RateLimit::hit('device_link_claim', $ip);
                $entered = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', Request::text('code')) ?? '');
                $row = DeviceLink::findByCode($entered);
                if ($row === null || $row['status'] !== 'pending') {
                    $this->backTo('link.php', ['code' => 'Ese código no es válido o ya se usó.'], ['code' => $entered]);
                }
                if (!DeviceLink::claim((int) $row['id'], 'Navegador · TREVIX', 'web', $ip)) {
                    $this->backTo('link.php', ['code' => 'Ese código ya no está disponible.'], ['code' => $entered]);
                }
                Session::set('_link_guest_code', $row['code']);
                Response::redirect(url('link.php'));
            }
        }

        if (is_array($status) && $status['status'] === 'approved') {
            $plain = DeviceLink::takeToken((int) $status['id']);
            Session::forget('_link_guest_code');
            $user = User::findForSession((int) $status['host_user_id']);
            if ($user !== null) {
                Auth::login($user);
                Session::flash('success', 'Dispositivo vinculado. Ya estás dentro.');
                Response::redirect(url('feed.php'));
            }
            unset($plain);
        }

        $this->render('pages/auth/link', [
            'title'  => t('Vincular') . ' · TREVIX',
            'mode'   => 'guest',
            'status' => $status,
            'code'   => is_string($code) ? $code : '',
            'errors' => Session::pull('_errors', []),
            'old'    => Session::pull('_old', []),
        ], 'layouts/auth');
    }

    private function attemptLogin(): never
    {
        $identifier = mb_strtolower(Request::text('identifier'));
        $old = ['identifier' => mb_substr($identifier, 0, 190)];

        try {
            $result = AccountService::authenticate($identifier, Request::text('password', false));
        } catch (ActionError $e) {
            $this->backTo('login.php', $e->fields ?: ['form' => $e->getMessage()], $old);
        }

        if ($result['reactivated']) {
            Session::flash('success', 'Tu cuenta volvió a estar activa. ¡Qué bueno verte de nuevo!');
        }
        Auth::login($result['user']);
        Response::redirect($this->intendedUrl());
    }

    private function attemptRegister(): never
    {
        $old = [
            'display_name' => AccountRules::normalizeName(Request::text('display_name')),
            'username'     => mb_strtolower(Request::text('username')),
            'email'        => mb_strtolower(Request::text('email')),
            'birth_date'   => Request::text('birth_date'),
        ];

        try {
            $result = AccountService::register($old + [
                'password'              => Request::text('password', false),
                'password_confirmation' => Request::text('password_confirmation', false),
                'terms'                 => Request::text('terms') === '1',
            ]);
        } catch (ActionError $e) {
            $this->backTo('register.php', $e->fields ?: ['form' => $e->getMessage()], $old);
        }

        $data = $result['data'];
        $sent = $result['mail_sent'];
        Auth::login(['id' => $result['id'], 'password_hash' => $result['password_hash']]);
        Session::flash('success', t('¡Bienvenido a TREVIX, {name}!', ['name' => $data['display_name']]));
        Session::flash($sent ? 'info' : 'error', $sent
            ? t('Te enviamos un enlace a {email} para confirmar tu correo.', ['email' => $data['email']])
            : 'No pudimos enviar el correo de confirmación. Puedes reenviarlo desde Configuración › Cuenta.');
        Response::redirect(url('feed.php'));
    }

    /** La respuesta es la misma exista o no la cuenta, para no revelar qué correos están registrados. */
    private function sendResetLink(): never
    {
        $email = mb_strtolower(Request::text('email'));
        try {
            $message = AccountService::sendResetLink($email);
        } catch (ActionError $e) {
            $this->backTo('forgot-password.php', $e->fields ?: ['form' => $e->getMessage()], ['email' => mb_substr($email, 0, 190)]);
        }
        Session::flash('success', $message);
        Response::redirect(url('forgot-password.php'));
    }

    private function applyNewPassword(array $record, string $token): never
    {
        $password = Request::text('password', false);
        $back = 'reset-password.php?token=' . $token;

        $error = Password::policyError($password);
        if ($error !== null) {
            $this->backTo($back, ['password' => $error], []);
        }
        if (!hash_equals($password, Request::text('password_confirmation', false))) {
            $this->backTo($back, ['password_confirmation' => 'Las contraseñas no coinciden.'], []);
        }

        if (!UserToken::consume((int) $record['id'])) {
            Session::flash('error', 'El enlace ya se utilizó. Solicita uno nuevo.');
            Response::redirect(url('forgot-password.php'));
        }

        $userId = (int) $record['user_id'];
        User::updatePasswordHash($userId, Password::hash($password));
        User::markEmailVerified($userId);
        UserToken::revoke($userId, 'password_reset');

        $user = User::findBasicById($userId);
        if ($user !== null) {
            AccountMail::securityNotice((string) $user['email'], (string) $user['display_name'],
                t('La contraseña de tu cuenta se restableció y se cerraron las sesiones abiertas.'));
        }

        Auth::logout();
        Session::start();
        Session::flash('success', 'Tu contraseña se actualizó. Ya puedes iniciar sesión.');
        Response::redirect(url('login.php'));
    }

    /** Solo se aceptan rutas internas, nunca URLs absolutas a otro dominio. */
    private function intendedUrl(): string
    {
        $intended = (string) Session::pull('_intended', '');
        $basePath = rtrim((string) parse_url(base_path(), PHP_URL_PATH), '/');
        if ($intended !== '' && str_starts_with($intended, '/') && !str_starts_with($intended, '//')
            && !str_contains($intended, '\\') && str_starts_with($intended, $basePath . '/')) {
            $origin = $basePath === '' ? base_path() : substr(base_path(), 0, -strlen($basePath));
            return $origin . $intended;
        }
        return url('feed.php');
    }

    private function backTo(string $page, array $errors, array $old): never
    {
        $this->backWithErrors(url($page), $errors, $old);
    }
}
