<?php
declare(strict_types=1);

namespace Trevix\Core;

final class Response
{
    public static function sendSecurityHeaders(): void
    {
        if (headers_sent()) {
            return;
        }

        header_remove('X-Powered-By');
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: strict-origin-when-cross-origin');
        // Micrófono solo para grabar notas de voz en los chats.
        header('Permissions-Policy: geolocation=(self), microphone=(self), camera=(), payment=()');
        header('Cross-Origin-Opener-Policy: same-origin');
        // img/media https:: portadas y audio de Audius y Free To Use (servidos por sus nodos) y GIF de GIPHY.
        header(
            "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; "
            . "img-src 'self' data: blob: https:; media-src 'self' blob: https:; font-src 'self'; connect-src 'self'; "
            . "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'"
        );

        if (Request::isHttps()) {
            header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
        }
    }

    public static function redirect(string $to, int $status = 302): never
    {
        header('Location: ' . $to, true, $status);
        exit;
    }

    public static function json(array $data, int $status = 200): never
    {
        // Los mensajes de los servicios se escriben en español: se traducen aquí para el JavaScript de la web.
        foreach (['error', 'message'] as $key) {
            if (isset($data[$key]) && is_string($data[$key])) {
                $data[$key] = Lang::t($data[$key]);
            }
        }
        if (isset($data['errors']) && is_array($data['errors'])) {
            $data['errors'] = array_map(static fn ($m) => is_string($m) ? Lang::t($m) : $m, $data['errors']);
        }
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    public static function abort(int $status, string $message = ''): never
    {
        $titles = [
            400 => 'Solicitud no válida',
            403 => 'Acceso denegado',
            404 => 'Página no encontrada',
            405 => 'Método no permitido',
            419 => 'Sesión expirada',
            429 => 'Demasiadas solicitudes',
            503 => 'Función no disponible',
        ];
        $title = Lang::t($titles[$status] ?? 'Error');
        $message = Lang::t($message);

        if (defined('TREVIX_API')) {
            throw new ActionError($message ?: $title, $status);
        }
        if (Request::wantsJson()) {
            self::json(['ok' => false, 'error' => $message ?: $title], $status);
        }

        http_response_code($status);
        View::render('pages/error', [
            'title'   => $title,
            'code'    => $status,
            'message' => $message ?: $title,
        ], 'layouts/auth');
        exit;
    }
}
