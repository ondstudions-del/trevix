<?php
declare(strict_types=1);

namespace Trevix\Services;

use DateTimeImmutable;
use Trevix\Core\Config;

/**
 * Reglas de validación de los datos de cuenta y perfil, compartidas por registro,
 * edición de perfil y configuración. Cada método devuelve el mensaje de error o null.
 */
final class AccountRules
{
    public const MIN_AGE = 13;

    public static function normalizeName(string $name): string
    {
        return trim((string) preg_replace('/\s+/u', ' ', $name));
    }

    public static function displayName(string $name): ?string
    {
        $length = mb_strlen($name);
        $max = (int) Config::get('app.limits.display_name', 60);
        if ($length < 2 || $length > $max) {
            return 'El nombre debe tener entre 2 y ' . $max . ' caracteres.';
        }
        if (preg_match('/[\p{C}<>]/u', $name)) {
            return 'El nombre contiene caracteres no permitidos.';
        }
        return null;
    }

    public static function username(string $username): ?string
    {
        if (!preg_match('/^[a-z0-9_.]{3,30}$/', $username)) {
            return 'Usa de 3 a 30 caracteres: minúsculas, números, punto o guion bajo.';
        }
        if (in_array($username, (array) Config::get('app.security.reserved_usernames', []), true)) {
            return 'Ese nombre de usuario está reservado.';
        }
        return null;
    }

    public static function email(string $email): ?string
    {
        if (mb_strlen($email) > 190 || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            return 'Escribe un correo electrónico válido.';
        }
        return null;
    }

    public static function birthDate(string $value): ?string
    {
        $birth = DateTimeImmutable::createFromFormat('!Y-m-d', $value);
        if ($birth === false || $birth->format('Y-m-d') !== $value) {
            return 'Indica una fecha de nacimiento válida.';
        }
        $today = new DateTimeImmutable('today');
        $age = $birth->diff($today)->y;
        if ($birth > $today || $age > 120) {
            return 'Indica una fecha de nacimiento válida.';
        }
        if ($age < self::MIN_AGE) {
            return 'Debes tener al menos ' . self::MIN_AGE . ' años para usar TREVIX.';
        }
        return null;
    }

    /** Biografía: se permiten saltos de línea, pero no otros caracteres de control. */
    public static function bio(string $bio): ?string
    {
        $max = (int) Config::get('app.limits.bio', 300);
        if (mb_strlen($bio) > $max) {
            return 'La biografía no puede superar los ' . $max . ' caracteres.';
        }
        if (preg_match('/[^\P{C}\n]/u', $bio)) {
            return 'La biografía contiene caracteres no permitidos.';
        }
        return null;
    }

    public static function normalizeWebsite(string $url): string
    {
        $url = trim($url);
        if ($url !== '' && !preg_match('#^[a-z][a-z0-9+.-]*://#i', $url)) {
            $url = 'https://' . $url;
        }
        return $url;
    }

    /** Solo enlaces http(s) con dominio válido: evita javascript:, data: y similares. */
    public static function website(string $url): ?string
    {
        if ($url === '') {
            return null;
        }
        $scheme = strtolower((string) parse_url($url, PHP_URL_SCHEME));
        $host = (string) parse_url($url, PHP_URL_HOST);
        if (strlen($url) > 255 || !filter_var($url, FILTER_VALIDATE_URL) || !in_array($scheme, ['http', 'https'], true)
            || !preg_match('/^([a-z0-9-]+\.)+[a-z]{2,}$/i', $host)) {
            return 'Escribe una dirección web válida (https://…).';
        }
        return null;
    }
}
