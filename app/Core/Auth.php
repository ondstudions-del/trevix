<?php
declare(strict_types=1);

namespace Trevix\Core;

use Trevix\Models\User;

final class Auth
{
    public const ROLES = ['user' => 1, 'moderator' => 2, 'admin' => 3];

    private static ?array $user = null;
    private static bool $resolved = false;
    private static bool $acting = false;

    public static function id(): ?int
    {
        if (self::$acting) {
            return self::$user !== null ? (int) self::$user['id'] : null;
        }
        $id = $_SESSION['user_id'] ?? null;
        return is_int($id) && $id > 0 ? $id : null;
    }

    /** API: la persona ya se validó con su token Bearer; no hay sesión ni cookie. */
    public static function actingAs(?array $user): void
    {
        self::$acting = true;
        self::$resolved = true;
        self::$user = $user;
    }

    /** Usuario autenticado y activo; la base de datos solo se consulta si existe una sesión. */
    public static function user(): ?array
    {
        if (!self::$resolved && !self::$acting) {
            self::$resolved = true;
            $id = self::id();
            if ($id !== null) {
                $user = User::findForSession($id);
                if ($user === null || !hash_equals((string) ($_SESSION['_pwd'] ?? ''), self::fingerprint($user['password_hash']))) {
                    self::logout();
                    return null;
                }
                unset($user['password_hash']);
                self::$user = $user;
                // Cada 20 segundos como máximo; la presencia "en línea" usa una ventana de app.presence_window.
                if (time() - (int) ($_SESSION['_seen_at'] ?? 0) >= 20) {
                    User::touchLastSeen($id);
                    $_SESSION['_seen_at'] = time();
                }
            }
        }
        return self::$user;
    }

    /**
     * Cada sesión guarda una huella del hash de la contraseña. Si el hash cambia (nueva contraseña
     * o «cerrar las demás sesiones»), las sesiones abiertas en otros dispositivos dejan de ser válidas.
     */
    public static function refreshFingerprint(string $passwordHash): void
    {
        Session::regenerate();
        $_SESSION['_pwd'] = self::fingerprint($passwordHash);
        self::$user = null;
        self::$resolved = false;
    }

    public static function fingerprint(string $passwordHash): string
    {
        return hash('sha256', $passwordHash);
    }

    public static function check(): bool
    {
        return self::user() !== null;
    }

    public static function login(array $user): void
    {
        $id = (int) $user['id'];
        $hash = $user['password_hash'] ?? User::passwordHash($id) ?? '';

        Session::regenerate();
        $_SESSION['user_id'] = $id;
        $_SESSION['_pwd'] = self::fingerprint($hash);
        $_SESSION['_seen_at'] = time();
        self::$user = null;
        self::$resolved = false;
    }

    public static function logout(): void
    {
        self::$user = null;
        self::$resolved = true;
        Session::destroy();
    }

    public static function hasRole(string $minimumRole, ?array $user = null): bool
    {
        $user ??= self::user();
        if ($user === null) {
            return false;
        }
        $current = self::ROLES[$user['role'] ?? 'user'] ?? 0;
        return $current >= (self::ROLES[$minimumRole] ?? PHP_INT_MAX);
    }
}
