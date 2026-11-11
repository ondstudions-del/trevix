<?php
declare(strict_types=1);

namespace Trevix\Core;

/** Hash, verificación y política de contraseñas. */
final class Password
{
    public const MAX_LENGTH = 128;

    /** Hash de una contraseña aleatoria: iguala el tiempo de respuesta cuando el usuario no existe. */
    private const DUMMY_HASH = '$2y$12$bhKADEGDF1.m.EpvDooHHewKop/nIf1AYpsKrzgVz4Z2hlmyQ46fK';

    public static function hash(string $password): string
    {
        return password_hash($password, self::algorithm());
    }

    public static function verify(string $password, ?string $hash): bool
    {
        if ($hash === null || $hash === '') {
            password_verify($password, self::DUMMY_HASH);
            return false;
        }
        return password_verify($password, $hash);
    }

    public static function needsRehash(string $hash): bool
    {
        return password_needs_rehash($hash, self::algorithm());
    }

    /** Devuelve el motivo por el que la contraseña no cumple la política, o null si es válida. */
    public static function policyError(string $password): ?string
    {
        $min = (int) Config::get('app.security.password_min_length', 10);
        $length = mb_strlen($password);

        if ($length < $min) {
            return Lang::t('La contraseña debe tener al menos {n} caracteres.', ['n' => $min]);
        }
        if ($length > self::MAX_LENGTH) {
            return Lang::t('La contraseña no puede superar los {n} caracteres.', ['n' => self::MAX_LENGTH]);
        }
        if (self::algorithm() === PASSWORD_BCRYPT && strlen($password) > 72) {
            return 'La contraseña no puede superar los 72 bytes.';
        }
        if (!preg_match('/\p{Ll}/u', $password) || !preg_match('/\p{Lu}/u', $password)) {
            return 'Combina letras mayúsculas y minúsculas.';
        }
        if (!preg_match('/\d/', $password)) {
            return 'Incluye al menos un número.';
        }
        if (!preg_match('/[^\p{L}\d]/u', $password)) {
            return 'Incluye al menos un símbolo.';
        }
        return null;
    }

    private static function algorithm(): string
    {
        return defined('PASSWORD_ARGON2ID') ? PASSWORD_ARGON2ID : PASSWORD_BCRYPT;
    }
}
