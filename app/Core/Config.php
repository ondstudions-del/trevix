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

        // Credenciales PayPal fuera del repo (config/paypal.credentials.php en el servidor).
        $paypal = $directory . '/paypal.credentials.php';
        if (is_file($paypal)) {
            self::$items = array_replace_recursive(self::$items, require $paypal);
        }

        $livekit = $directory . '/livekit.credentials.php';
        if (is_file($livekit)) {
            self::$items = array_replace_recursive(self::$items, require $livekit);
        }

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
}
