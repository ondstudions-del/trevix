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
use Trevix\Models\AppSetting;
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
            'title'  => 'Iniciar sesión · TREVIX',
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
            'title'       => 'Crear cuenta · TREVIX',
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
            'title'  => 'Recuperar contraseña · TREVIX',
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
            'title'       => 'Nueva contraseña · TREVIX',
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
            'El correo de tu cuenta se cambió a ' . $newEmail . '.');
        Session::flash('success', 'Tu correo ahora es ' . $newEmail . '.');
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
        Session::flash('success', '¡Bienvenido a TREVIX, ' . $data['display_name'] . '!');
        Session::flash($sent ? 'info' : 'error', $sent
            ? 'Te enviamos un enlace a ' . $data['email'] . ' para confirmar tu correo.'
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
                'La contraseña de tu cuenta se restableció y se cerraron las sesiones abiertas.');
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
