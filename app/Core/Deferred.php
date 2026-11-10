<?php
declare(strict_types=1);

namespace Trevix\Core;

use Throwable;

/**
 * Tareas que se ejecutan después de entregar la respuesta (el hosting compartido no tiene colas ni tareas
 * programadas): se cierra la sesión para no bloquear las demás peticiones de la persona, se envía la respuesta con
 * litespeed_finish_request / fastcgi_finish_request y luego corre cada tarea. Sin esas funciones corren al final.
 */
final class Deferred
{
    /** @var list<callable(): void> */
    private static array $tasks = [];

    public static function run(callable $task): void
    {
        if (self::$tasks === []) {
            register_shutdown_function([self::class, 'flush']);
        }
        self::$tasks[] = $task;
    }

    /** @internal Llamada al terminar la petición. */
    public static function flush(): void
    {
        ignore_user_abort(true);
        @set_time_limit(90);
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }
        while (ob_get_level() > 0 && @ob_end_flush()) {
        }
        flush();
        if (function_exists('litespeed_finish_request')) {
            litespeed_finish_request();
        } elseif (function_exists('fastcgi_finish_request')) {
            fastcgi_finish_request();
        }
        while (self::$tasks !== []) {
            $task = array_shift(self::$tasks);
            try {
                $task();
            } catch (Throwable $e) {
                error_log('[Deferred] ' . $e::class . ': ' . $e->getMessage());
            }
        }
    }
}
