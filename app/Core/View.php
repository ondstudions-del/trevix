<?php
declare(strict_types=1);

namespace Trevix\Core;

use RuntimeException;
use Throwable;

final class View
{
    private static array $shared = [];

    public static function share(string $key, mixed $value): void
    {
        self::$shared[$key] = $value;
    }

    public static function render(string $view, array $data = [], ?string $layout = null): void
    {
        $content = self::capture($view, $data);

        if ($layout === null) {
            echo $content;
            return;
        }

        echo self::capture($layout, array_merge($data, ['content' => $content]));
    }

    public static function capture(string $view, array $data = []): string
    {
        if (!preg_match('#^[a-z0-9/_-]+$#', $view)) {
            throw new RuntimeException('Nombre de vista no válido.');
        }

        $file = APP_PATH . '/Views/' . $view . '.php';
        if (!is_file($file)) {
            throw new RuntimeException('Vista no encontrada: ' . $view);
        }

        $render = static function (string $__file, array $__data): void {
            extract($__data, EXTR_SKIP);
            require $__file;
        };

        ob_start();
        try {
            $render($file, array_merge(self::$shared, $data));
        } catch (Throwable $e) {
            ob_end_clean();
            throw $e;
        }
        return (string) ob_get_clean();
    }

    public static function partial(string $name, array $data = []): void
    {
        echo self::capture('partials/' . $name, $data);
    }
}
