<?php
declare(strict_types=1);

namespace Trevix\Api;

/**
 * Formato único de respuesta de la API v1:
 *   éxito  {"ok": true,  "data": …, "meta": {…}}
 *   error  {"ok": false, "error": {"code": "…", "message": "…", "fields": {…}}}
 */
final class Reply
{
    public const CODES = [
        400 => 'bad_request',
        401 => 'unauthenticated',
        403 => 'forbidden',
        404 => 'not_found',
        405 => 'method_not_allowed',
        409 => 'conflict',
        413 => 'payload_too_large',
        415 => 'unsupported_media_type',
        419 => 'bad_request',
        422 => 'validation_error',
        429 => 'too_many_requests',
        500 => 'server_error',
        503 => 'unavailable',
    ];

    public static function ok(mixed $data = null, array $meta = [], int $status = 200): never
    {
        $body = ['ok' => true, 'data' => $data];
        if ($meta !== []) {
            $body['meta'] = $meta;
        }
        self::send($body, $status);
    }

    public static function error(int $status, string $message, array $fields = [], ?string $code = null): never
    {
        $error = ['code' => $code ?? (self::CODES[$status] ?? 'error'), 'message' => $message];
        if ($fields !== []) {
            $error['fields'] = $fields;
        }
        self::send(['ok' => false, 'error' => $error], $status);
    }

    private static function send(array $body, int $status): never
    {
        while (ob_get_level() > 0) {
            ob_end_clean();
        }
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
        exit;
    }
}
