<?php
declare(strict_types=1);

namespace Trevix\Core;

use Throwable;

final class ErrorHandler
{
    private static bool $debug = false;

    public static function register(bool $debug): void
    {
        self::$debug = $debug;

        error_reporting(E_ALL);
        ini_set('display_errors', $debug ? '1' : '0');
        ini_set('log_errors', '1');
        ini_set('error_log', BASE_PATH . '/storage/logs/php-error.log');

        set_exception_handler([self::class, 'handleException']);
    }

    public static function handleException(Throwable $e): void
    {
        error_log(sprintf('[%s] %s in %s:%d', $e::class, $e->getMessage(), $e->getFile(), $e->getLine()));

        while (ob_get_level() > 0) {
            ob_end_clean();
        }

        if (!headers_sent()) {
            http_response_code(500);
        }

        if (Request::wantsJson()) {
            header('Content-Type: application/json; charset=utf-8');
            $error = defined('TREVIX_API')
                ? ['code' => 'server_error', 'message' => 'Error interno del servidor.']
                : 'Error interno del servidor.';
            echo json_encode(['ok' => false, 'error' => $error], JSON_UNESCAPED_UNICODE);
            return;
        }

        try {
            View::render('pages/error', [
                'title'   => 'Error del servidor',
                'code'    => 500,
                'message' => 'Algo salió mal de nuestro lado. Inténtalo de nuevo en unos minutos.',
                'detail'  => self::$debug ? $e->getMessage() . ' — ' . $e->getFile() . ':' . $e->getLine() : null,
            ], 'layouts/auth');
        } catch (Throwable) {
            echo 'Error interno del servidor.';
        }
    }
}
