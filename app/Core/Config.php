<?php
declare(strict_types=1);

namespace Trevix\Core;

final class Config
{
    private static array $items = [];

    public static function load(string $directory): void
    {
        foreach (['app', 'database'] as $name) {
            self::$items[$name] = require $directory . '/' . $name . '.php';
        }

        $local = $directory . '/local.php';
        if (is_file($local)) {
            self::$items = array_replace_recursive(self::$items, require $local);
        }

        self::mergeOptionalPhp($directory . '/paypal.credentials.php');
        self::mergeOptionalPhp($directory . '/livekit.credentials.php');

        if (self::isProduction()) {
            self::$items['app']['debug'] = false;
        }
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        $value = self::$items;
        foreach (explode('.', $key) as $segment) {
            if (!is_array($value) || !array_key_exists($segment, $value)) {
                return $default;
            }
            $value = $value[$segment];
        }
        return $value;
    }

    public static function isProduction(): bool
    {
        return self::get('app.env') === 'production';
    }

    /** El modo vista previa nunca se activa en producción. */
    public static function previewEnabled(): bool
    {
        return (bool) self::get('app.preview_mode', false) && !self::isProduction();
    }

    /** Credenciales opcionales: un archivo roto no debe tumbar todo el sitio. */
    private static function mergeOptionalPhp(string $path): void
    {
        if (!is_file($path)) {
            return;
        }
        try {
            $data = require $path;
            if (is_array($data)) {
                self::$items = array_replace_recursive(self::$items, $data);
            }
        } catch (Throwable $e) {
            error_log(sprintf('[Config] Ignorando %s: %s', basename($path), $e->getMessage()));
        }
    }
}
