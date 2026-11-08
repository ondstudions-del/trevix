<?php
declare(strict_types=1);

namespace Trevix\Services;

use PDOException;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Database;
use Trevix\Core\Password;
use Trevix\Models\Community;
use Trevix\Models\Conversation;
use Trevix\Models\Event;
use Trevix\Models\Follow;
use Trevix\Models\Message;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\Song;
use Trevix\Models\Story;
use Trevix\Models\User;

/**
 * Configuración de la cuenta (compartida por la web y la API): usuario y correo, privacidad,
 * avisos, contraseña, desactivar y eliminar. Cerrar la sesión web o renovar el token es cosa de cada capa.
 */
final class SettingsService
{
    /** Interruptores de notificaciones: campo => columna de users. */
    public const NOTIFY_FIELDS = ['notify_follows', 'notify_likes', 'notify_comments', 'notify_mentions'];

    /**
     * Cambia el usuario y/o pide el cambio de correo (requiere la contraseña actual).
     * Se envían ambos valores: el que no cambia va con su valor actual.
     *
     * @return array{changed: bool, messages: list<string>, error: ?string}
     */
    public static function updateAccount(array $user, string $username, string $email, string $password, string $passwordField = 'current_password'): array
    {
        $id = (int) $user['id'];
        $username = mb_strtolower(trim($username));
        $email = mb_strtolower(trim($email));
        $usernameChanged = $username !== $user['username'];
        $emailChanged = $email !== mb_strtolower((string) $user['email']);
        if (!$usernameChanged && !$emailChanged) {
            return ['changed' => false, 'messages' => [], 'error' => null];
        }

        $errors = array_filter([
            'username' => $usernameChanged ? AccountRules::username($username) : null,
            'email'    => $emailChanged ? AccountRules::email($email) : null,
        ]);
        if (!isset($errors['username']) && $usernameChanged && User::usernameExists($username, $id)) {
            $errors['username'] = 'Ese nombre de usuario ya está en uso.';
        }
        if (!isset($errors['email']) && $emailChanged && User::emailExists($email, $id)) {
            $errors['email'] = 'Ya existe una cuenta con ese correo.';
        }
        if ($errors === [] && $emailChanged) {
            if (RateLimit::tooManyAttempts('email_change', (string) $id)) {
                $errors['email'] = 'Ya solicitaste varios cambios de correo. Inténtalo más tarde.';
            } else {
                self::confirmPassword($user, $password, $passwordField);
            }
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        $messages = [];
        $error = null;
        if ($usernameChanged) {
            try {
                User::updateUsername($id, $username);
            } catch (PDOException $e) {
                if ($e->getCode() !== '23000') {
                    throw $e;
                }
                throw ActionError::field('username', 'Ese nombre de usuario ya está en uso.');
            }
            $messages[] = 'Tu nombre de usuario ahora es @' . $username . '.';
        }
        if ($emailChanged) {
            RateLimit::hit('email_change', (string) $id);
            if (AccountMail::emailChange($user, $email)) {
                $messages[] = 'Te enviamos un enlace a ' . $email . '. Tu correo cambiará cuando lo confirmes.';
            } else {
                $error = 'No pudimos enviar el correo de confirmación a ' . $email . '. Inténtalo más tarde.';
            }
        }
        return ['changed' => true, 'messages' => $messages, 'error' => $error];
    }

    /**
     * Cuenta privada o pública (al volverla pública se aprueban las solicitudes pendientes),
     * estado de actividad y quién puede iniciar una conversación. Un null conserva el valor actual.
     * Devuelve el mensaje para mostrar o null si no hubo cambios.
     */
    public static function updatePrivacy(array $user, ?bool $private, ?bool $showActivity, ?string $messagePrivacy): ?string
    {
        $id = (int) $user['id'];
        $private ??= !empty($user['is_private']);
        $showActivity = $showActivity === null ? (int) $user['show_activity'] : ($showActivity ? 1 : 0);
        $messagePrivacy ??= (string) $user['message_privacy'];
        if (!in_array($messagePrivacy, User::MESSAGE_PRIVACY, true)) {
            throw ActionError::field('message_privacy', 'Elige quién puede enviarte mensajes.');
        }

        $privacyChanged = $private !== !empty($user['is_private']);
        $activityChanged = $showActivity !== (int) $user['show_activity'] || $messagePrivacy !== $user['message_privacy'];
        if (!$privacyChanged && !$activityChanged) {
            return null;
        }

        $messages = [];
        if ($activityChanged) {
            User::updateActivityPrivacy($id, $showActivity, $messagePrivacy);
            $messages[] = 'Guardamos tus preferencias de actividad y mensajes.';
        }
        if ($privacyChanged) {
            User::setPrivate($id, $private);
            if ($private) {
                $messages[] = 'Tu cuenta ahora es privada. Las nuevas personas tendrán que enviarte una solicitud.';
            } else {
                $accepted = Follow::acceptAll($id);
                $messages[] = 'Tu cuenta ahora es pública.'
                    . ($accepted > 0 ? ' Aprobamos ' . ($accepted === 1 ? 'la solicitud pendiente' : 'las ' . $accepted . ' solicitudes pendientes') . '.' : '');
            }
        }
        return implode(' ', $messages);
    }

    /** @param array<string, bool|null> $prefs campo notify_* => valor (null conserva el actual). Devuelve true si cambió algo. */
    public static function updateNotifications(array $user, array $prefs): bool
    {
        $values = [];
        foreach (self::NOTIFY_FIELDS as $field) {
            $value = $prefs[$field] ?? null;
            $values[$field] = $value === null ? (int) $user[$field] : ($value ? 1 : 0);
        }
        $changed = array_filter($values, static fn (int $value, string $field) => $value !== (int) $user[$field], ARRAY_FILTER_USE_BOTH);
        if ($changed === []) {
            return false;
        }
        User::updateNotificationPrefs((int) $user['id'], $values);
        return true;
    }

    /** @return array{type: string, message: string} type = success | info | error */
    public static function resendVerification(array $user): array
    {
        if (!empty($user['email_verified_at'])) {
            return ['type' => 'info', 'message' => 'Tu correo ya está confirmado.'];
        }
        $key = (string) $user['id'];
        if (RateLimit::tooManyAttempts('verify_email', $key)) {
            throw new ActionError('Ya enviamos varios correos de confirmación. Revisa tu bandeja de entrada y la carpeta de spam.', 429);
        }
        RateLimit::hit('verify_email', $key);
        return AccountMail::verification($user)
            ? ['type' => 'success', 'message' => 'Te enviamos un nuevo enlace de confirmación a ' . $user['email'] . '.']
            : ['type' => 'error', 'message' => 'No pudimos enviar el correo. Inténtalo de nuevo en unos minutos.'];
    }

    /** Cambia la contraseña y avisa por correo. Devuelve el nuevo hash (las demás sesiones dejan de valer). */
    public static function changePassword(array $user, string $current, string $password, string $confirmation): string
    {
        $id = (int) $user['id'];
        self::confirmPassword($user, $current, 'current_password');

        $error = Password::policyError($password);
        if ($error !== null) {
            throw ActionError::field('password', $error);
        }
        if (!hash_equals($password, $confirmation)) {
            throw ActionError::field('password_confirmation', 'Las contraseñas no coinciden.');
        }
        if (Password::verify($password, User::passwordHash($id))) {
            throw ActionError::field('password', 'La nueva contraseña debe ser distinta de la actual.');
        }

        $hash = Password::hash($password);
        User::updatePasswordHash($id, $hash);
        AccountMail::securityNotice((string) $user['email'], (string) $user['display_name'],
            'La contraseña de tu cuenta se cambió y se cerraron las sesiones de otros dispositivos.');
        return $hash;
    }

    /** Volver a generar el hash invalida la huella de las sesiones abiertas en otros dispositivos. Devuelve el hash nuevo. */
    public static function rehashPassword(array $user, string $password, string $field): string
    {
        self::confirmPassword($user, $password, $field);
        $hash = Password::hash($password);
        User::updatePasswordHash((int) $user['id'], $hash);
        return $hash;
    }

    public static function deactivate(array $user, string $password, string $field): void
    {
        self::guardAdminAccount($user);
        self::confirmPassword($user, $password, $field);
        User::deactivate((int) $user['id']);
    }

    /** Eliminación definitiva de la cuenta y de todo su contenido. */
    public static function deleteAccount(array $user, string $password, string $confirm, string $passwordField, string $confirmField): void
    {
        self::guardAdminAccount($user);
        self::confirmPassword($user, $password, $passwordField);
        if (!hash_equals((string) $user['username'], mb_strtolower(trim($confirm)))) {
            throw ActionError::field($confirmField, 'Escribe tu nombre de usuario exactamente para confirmar.');
        }

        $userId = (int) $user['id'];
        $account = User::findBasicById($userId);
        $mediaPaths = array_merge(Post::mediaPathsByUser($userId), Story::mediaPathsByUser($userId));
        $songFiles = Song::filesByArtist($userId);
        $eventCovers = Event::coverPathsByUser($userId);
        try {
            Database::transaction(static function () use ($userId, &$mediaPaths): void {
                Post::releaseCountersForUser($userId);
                Event::releaseCountersForUser($userId);
                Follow::releaseCountersForUser($userId);
                Community::releaseCountersForUser($userId);
                Story::releaseViewsForUser($userId);
                $mediaPaths = array_merge($mediaPaths, Message::deleteAllFrom($userId));
                User::deletePermanently($userId);
                Conversation::deleteOrphans();
            });
        } catch (PDOException $e) {
            if ($e->getCode() !== '23000') {
                throw $e;
            }
            throw ActionError::field($confirmField, 'Antes de eliminar tu cuenta transfiere o elimina las comunidades que administras. Si alguna está suspendida, el equipo de moderación debe resolverla primero.', 409);
        }

        ImageUpload::delete($account['avatar_path'] ?? null);
        ImageUpload::delete($account['cover_path'] ?? null);
        array_walk($mediaPaths, static fn (string $path) => MediaUpload::delete($path));
        array_walk($songFiles['audio'], static fn (string $path) => AudioUpload::delete($path));
        array_walk($songFiles['covers'], static fn (string $path) => ImageUpload::delete($path));
        array_walk($eventCovers, static fn (string $path) => ImageUpload::delete($path));
    }

    /**
     * Exige la contraseña actual para acciones sensibles, con límite de intentos por usuario.
     * Si no es correcta, el error va en el campo indicado.
     */
    public static function confirmPassword(array $user, string $password, string $field = 'current_password'): void
    {
        $key = (string) $user['id'];
        if (RateLimit::tooManyAttempts('password_confirm', $key)) {
            $seconds = RateLimit::availableIn('password_confirm', $key);
            $message = 'Demasiados intentos. Inténtalo de nuevo en ' . max(1, (int) ceil($seconds / 60)) . ' min.';
            throw new ActionError($message, 429, [$field => $message], max(1, $seconds));
        }
        if ($password === '' || !Password::verify($password, User::passwordHash((int) $user['id']))) {
            RateLimit::hit('password_confirm', $key);
            throw ActionError::field($field, 'La contraseña actual no es correcta.');
        }
        RateLimit::clear('password_confirm', $key);
    }

    /** Evita que la administración se quede sin acceso por una baja accidental. */
    private static function guardAdminAccount(array $user): void
    {
        if (Auth::hasRole('admin', $user)) {
            throw new ActionError('Las cuentas de administración no se pueden desactivar ni eliminar desde aquí.', 403);
        }
    }
}
