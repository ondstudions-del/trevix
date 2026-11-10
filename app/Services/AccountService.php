<?php
declare(strict_types=1);

namespace Trevix\Services;

use PDOException;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Password;
use Trevix\Core\Request;
use Trevix\Models\AppSetting;
use Trevix\Models\RateLimit;
use Trevix\Models\User;

/**
 * Inicio de sesión, registro y enlace de recuperación (compartido por la web y la API).
 * Los errores generales van en el campo «form»; los de un dato concreto, en su campo.
 */
final class AccountService
{
    /**
     * Comprueba las credenciales con los mismos límites, suspensiones y mantenimiento que la web.
     * Reactiva cuentas desactivadas y suspensiones vencidas.
     *
     * @return array{user: array, reactivated: bool}
     */
    public static function authenticate(string $identifier, string $password): array
    {
        $identifier = mb_strtolower(trim($identifier));
        if ($identifier === '' || $password === '') {
            throw new ActionError('Escribe tu correo o usuario y tu contraseña.', 422, ['form' => 'Escribe tu correo o usuario y tu contraseña.']);
        }

        $ip = Request::ip();
        $accountKey = $ip . '|' . $identifier;
        if (RateLimit::tooManyAttempts('login', $accountKey) || RateLimit::tooManyAttempts('login_ip', $ip)) {
            $wait = max(RateLimit::availableIn('login', $accountKey), RateLimit::availableIn('login_ip', $ip));
            $message = 'Demasiados intentos. Inténtalo de nuevo en ' . max(1, (int) ceil($wait / 60)) . ' min.';
            throw new ActionError($message, 429, ['form' => $message], max(1, $wait));
        }

        $user = mb_strlen($identifier) <= 190 ? User::findForLogin($identifier) : null;
        if (!Password::verify($password, $user['password_hash'] ?? null)) {
            RateLimit::hit('login', $accountKey);
            RateLimit::hit('login_ip', $ip);
            $message = 'El correo, usuario o contraseña no son correctos.';
            throw new ActionError($message, 401, ['form' => $message]);
        }

        $id = (int) $user['id'];
        if ($user['status'] === 'suspended') {
            $until = $user['suspended_until'] ? strtotime((string) $user['suspended_until']) : false;
            if ($until === false || $until > time()) {
                $message = $until
                    ? 'Tu cuenta está suspendida hasta el ' . full_date((string) $user['suspended_until']) . '.'
                    : 'Tu cuenta está suspendida. Contacta con el equipo de TREVIX.';
                if (!empty($user['suspension_reason'])) {
                    $message .= ' Motivo: ' . $user['suspension_reason'];
                }
                throw new ActionError($message, 403, ['form' => $message]);
            }
            User::reactivate($id);
        }

        if (AppSetting::flag('maintenance_mode') && !Auth::hasRole('moderator', $user)) {
            $message = 'TREVIX está en mantenimiento. Vuelve a intentarlo en un rato.';
            throw new ActionError($message, 503, ['form' => $message]);
        }

        $reactivated = $user['status'] === 'deactivated';
        if ($reactivated) {
            User::reactivate($id);
        }
        if (Password::needsRehash($user['password_hash'])) {
            $user['password_hash'] = Password::hash($password);
            User::updatePasswordHash($id, $user['password_hash']);
        }

        RateLimit::clear('login', $accountKey);
        User::touchLastSeen($id);
        return ['user' => $user, 'reactivated' => $reactivated];
    }

    public static function registrationOpen(): bool
    {
        return AppSetting::flag('registration_open') && !AppSetting::flag('maintenance_mode');
    }

    /**
     * Crea una cuenta y envía el correo de confirmación.
     *
     * @param array{display_name:string, username:string, email:string, birth_date:string,
     *              password:string, password_confirmation:string, terms:bool} $input
     * @return array{id:int, password_hash:string, data:array, mail_sent:bool}
     */
    public static function register(array $input): array
    {
        if (!self::registrationOpen()) {
            $message = 'El registro de cuentas nuevas está cerrado en este momento.';
            throw new ActionError($message, 403, ['form' => $message]);
        }
        $ip = Request::ip();
        $data = [
            'display_name' => AccountRules::normalizeName((string) $input['display_name']),
            'username'     => mb_strtolower(trim((string) $input['username'])),
            'email'        => mb_strtolower(trim((string) $input['email'])),
            'birth_date'   => trim((string) $input['birth_date']),
        ];
        $password = (string) $input['password'];

        if (RateLimit::tooManyAttempts('register_attempt', $ip) || RateLimit::tooManyAttempts('register', $ip)) {
            $message = 'Se alcanzó el límite de registros desde tu conexión. Inténtalo más tarde.';
            throw new ActionError($message, 429, ['form' => $message], max(RateLimit::availableIn('register_attempt', $ip), RateLimit::availableIn('register', $ip)));
        }
        RateLimit::hit('register_attempt', $ip);

        $errors = array_filter([
            'display_name' => AccountRules::displayName($data['display_name']),
            'username'     => AccountRules::username($data['username']),
            'email'        => AccountRules::email($data['email']),
            'birth_date'   => AccountRules::birthDate($data['birth_date']),
            'password'     => Password::policyError($password),
        ]);
        if (!isset($errors['password']) && !hash_equals($password, (string) $input['password_confirmation'])) {
            $errors['password_confirmation'] = 'Las contraseñas no coinciden.';
        }
        if (empty($input['terms'])) {
            $errors['terms'] = 'Debes aceptar los términos para continuar.';
        }
        if ($errors === []) {
            if (User::usernameExists($data['username'])) {
                $errors['username'] = 'Ese nombre de usuario ya está en uso.';
            }
            if (User::emailExists($data['email'])) {
                $errors['email'] = 'Ya existe una cuenta con ese correo.';
            }
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        $hash = Password::hash($password);
        try {
            $id = User::create($data + ['password_hash' => $hash]);
        } catch (PDOException $e) {
            if ($e->getCode() === '23000') {
                $message = 'El usuario o el correo ya están registrados.';
                throw new ActionError($message, 409, ['form' => $message]);
            }
            throw $e;
        }
        RateLimit::hit('register', $ip);

        $sent = AccountMail::verification(['id' => $id, 'email' => $data['email'], 'display_name' => $data['display_name']]);
        Ix::welcome($id, $data);
        return ['id' => $id, 'password_hash' => $hash, 'data' => $data, 'mail_sent' => $sent];
    }

    /** La respuesta es la misma exista o no la cuenta, para no revelar qué correos están registrados. */
    public static function sendResetLink(string $email): string
    {
        $email = mb_strtolower(trim($email));
        $error = AccountRules::email($email);
        if ($error !== null) {
            throw ActionError::field('email', $error);
        }

        $ip = Request::ip();
        $key = $ip . '|' . $email;
        if (RateLimit::tooManyAttempts('password_reset', $key) || RateLimit::tooManyAttempts('password_reset_ip', $ip)) {
            $message = 'Ya solicitaste varios enlaces. Revisa tu bandeja de entrada o inténtalo más tarde.';
            throw new ActionError($message, 429, ['form' => $message]);
        }
        RateLimit::hit('password_reset', $key);
        RateLimit::hit('password_reset_ip', $ip);

        $user = User::findForPasswordReset($email);
        if ($user !== null && !AccountMail::passwordReset($user)) {
            error_log('[Auth] No se pudo enviar el enlace de recuperación a la cuenta ' . $user['id']);
        }
        return 'Si existe una cuenta con ' . $email . ', te enviamos un enlace para crear una nueva contraseña. Revisa también la carpeta de spam.';
    }
}
