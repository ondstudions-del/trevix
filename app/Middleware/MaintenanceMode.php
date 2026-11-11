<?php
declare(strict_types=1);

namespace Trevix\Middleware;

use Trevix\Core\Auth;
use Trevix\Core\Request;
use Trevix\Core\View;
use Trevix\Models\AppSetting;

/**
 * Modo mantenimiento: con una sesión abierta, solo moderadores y administradores usan la aplicación.
 * Sin sesión no se consulta la base: el inicio de sesión y el registro aplican la regla por su cuenta,
 * y las páginas públicas (portada, legales) siguen disponibles.
 */
final class MaintenanceMode
{
    /** Scripts que siguen funcionando para que la persona pueda salir de su cuenta. */
    private const ALLOWED = ['logout.php'];

    public static function handle(): void
    {
        if (Auth::id() === null || in_array(basename((string) ($_SERVER['SCRIPT_NAME'] ?? '')), self::ALLOWED, true)) {
            return;
        }
        if (!AppSetting::flag('maintenance_mode') || Auth::user() === null || Auth::hasRole('moderator')) {
            return;
        }

        $message = t('TREVIX está en mantenimiento. Vuelve a intentarlo en un rato.');
        http_response_code(503);
        header('Retry-After: 600');
        if (Request::wantsJson()) {
            header('Content-Type: application/json; charset=utf-8');
            echo json_encode(['ok' => false, 'error' => $message], JSON_UNESCAPED_UNICODE);
            exit;
        }
        View::render('pages/maintenance', [
            'title'   => t('En mantenimiento') . ' · TREVIX',
            'message' => $message,
            'notice'  => AppSetting::get('site_announcement'),
        ], 'layouts/auth');
        exit;
    }
}
