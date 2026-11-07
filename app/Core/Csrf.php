<?php
declare(strict_types=1);

namespace Trevix\Core;

final class Csrf
{
    private const SESSION_KEY = '_csrf_token';
    public const FIELD = '_csrf';
    public const HEADER = 'X-CSRF-Token';

    public static function token(): string
    {
        if (empty($_SESSION[self::SESSION_KEY]) || !is_string($_SESSION[self::SESSION_KEY])) {
            $_SESSION[self::SESSION_KEY] = bin2hex(random_bytes(32));
        }
        return $_SESSION[self::SESSION_KEY];
    }

    public static function field(): string
    {
        return '<input type="hidden" name="' . self::FIELD . '" value="' . e(self::token()) . '">';
    }

    public static function verify(mixed $token): bool
    {
        return is_string($token)
            && !empty($_SESSION[self::SESSION_KEY])
            && hash_equals($_SESSION[self::SESSION_KEY], $token);
    }

    public static function tokenFromRequest(): ?string
    {
        $token = $_POST[self::FIELD] ?? Request::header(self::HEADER);
        return is_string($token) ? $token : null;
    }
}
