<?php
declare(strict_types=1);

namespace Trevix\Core;

final class Request
{
    public static function method(): string
    {
        return strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
    }

    public static function isPost(): bool
    {
        return self::method() === 'POST';
    }

    public static function isHttps(): bool
    {
        return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (int) ($_SERVER['SERVER_PORT'] ?? 0) === 443;
    }

    public static function ip(): string
    {
        return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    }

    public static function header(string $name): ?string
    {
        $key = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
        return isset($_SERVER[$key]) ? (string) $_SERVER[$key] : null;
    }

    public static function input(string $key, mixed $default = null): mixed
    {
        return $_POST[$key] ?? $default;
    }

    /** Campo POST como texto; descarta arreglos y texto con codificación inválida. */
    public static function text(string $key, bool $trim = true): string
    {
        $value = $_POST[$key] ?? '';
        if (!is_string($value) || !mb_check_encoding($value, 'UTF-8')) {
            return '';
        }
        return $trim ? trim($value) : $value;
    }

    /** Lee un parámetro GET como texto plano recortado. */
    public static function query(string $key, string $default = ''): string
    {
        $value = $_GET[$key] ?? $default;
        return is_string($value) ? trim($value) : $default;
    }

    /** Devuelve el valor GET solo si pertenece a la lista permitida. */
    public static function queryIn(string $key, array $allowed, string $default): string
    {
        $value = self::query($key, $default);
        return in_array($value, $allowed, true) ? $value : $default;
    }

    public static function wantsJson(): bool
    {
        if (defined('TREVIX_API')) {
            return true;
        }
        $accept = $_SERVER['HTTP_ACCEPT'] ?? '';
        return str_contains($accept, 'application/json')
            || self::header('X-Requested-With') === 'XMLHttpRequest';
    }
}
