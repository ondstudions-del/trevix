<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use Trevix\Controllers\Controller;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\RequireRole;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Appeal;
use Trevix\Models\RateLimit;
use Trevix\Models\Report;
use Trevix\Models\Song;
use Trevix\Models\Support;
use Trevix\Models\VerificationRequest;
use Trevix\Models\Wallet;

/**
 * Base de las secciones del panel. Lectura: rol mínimo de la sección (la vista previa sin sesión muestra
 * la estructura vacía). Escritura: CSRF, sesión real con el rol exigido y límite de acciones por persona.
 */
abstract class AdminController extends Controller
{
    public const SECTIONS = [
        'dashboard'   => ['label' => 'Dashboard', 'icon' => 'layout-dashboard', 'path' => 'admin/', 'role' => 'moderator'],
        'reports'     => ['label' => 'Reportes', 'icon' => 'flag', 'path' => 'admin/reports.php', 'role' => 'moderator'],
        'content'     => ['label' => 'Contenido', 'icon' => 'file-text', 'path' => 'admin/content.php', 'role' => 'moderator'],
        'music'       => ['label' => 'Música', 'icon' => 'music', 'path' => 'admin/music.php', 'role' => 'moderator'],
        'users'       => ['label' => 'Usuarios', 'icon' => 'users', 'path' => 'admin/users.php', 'role' => 'moderator'],
        'appeals'     => ['label' => 'Apelaciones', 'icon' => 'scale', 'path' => 'admin/appeals.php', 'role' => 'moderator'],
        'support'     => ['label' => 'Soporte IX', 'icon' => 'sparkles', 'path' => 'admin/support.php', 'role' => 'moderator'],
        'verification' => ['label' => 'Verificación', 'icon' => 'badge-check', 'path' => 'admin/verification.php', 'role' => 'admin'],
        'wallet'      => ['label' => 'Monedero', 'icon' => 'wallet', 'path' => 'admin/wallet.php', 'role' => 'admin'],
        'communities' => ['label' => 'Comunidades', 'icon' => 'users-round', 'path' => 'admin/communities.php', 'role' => 'admin'],
        'settings'    => ['label' => 'Configuración', 'icon' => 'sliders-horizontal', 'path' => 'admin/settings.php', 'role' => 'admin'],
        'audit'       => ['label' => 'Auditoría', 'icon' => 'history', 'path' => 'admin/audit.php', 'role' => 'admin'],
    ];

    protected function guard(string $section): void
    {
        RequireRole::handle(self::SECTIONS[$section]['role']);
    }

    /** Persona del equipo con sesión real (null en la vista previa). */
    protected function staff(): ?array
    {
        return Auth::user();
    }

    protected function page(string $section, string $view, array $data = []): void
    {
        $staff = $this->staff();
        $sections = array_filter(
            self::SECTIONS,
            static fn (array $item) => $staff === null || Auth::hasRole($item['role'], $staff)
        );
        $this->render('admin/' . $view, $data + [
            'title'       => t('{section} · Administración · TREVIX', ['section' => t(self::SECTIONS[$section]['label'] ?? 'Panel')]),
            'section'     => $section,
            'sections'    => $sections,
            'staff'       => $staff,
            'openReports' => $staff !== null ? Report::openCount() : 0,
            'pendingSongs' => $staff !== null ? Song::pendingCount() : 0,
            'openTickets' => $staff !== null ? Support::openCount() : 0,
            'pendingAppeals' => $staff !== null ? Appeal::pendingCount() : 0,
            'pendingVerifications' => $staff !== null && Auth::hasRole('admin', $staff) ? VerificationRequest::pendingCount() : 0,
            'pendingWallet' => $staff !== null && Auth::hasRole('admin', $staff) ? Wallet::pendingCount() : 0,
        ], 'layouts/admin');
    }

    /** Valida un envío del panel y devuelve a quien actúa. */
    protected function beginAction(string $role, string $back): array
    {
        VerifyCsrf::handle();
        $user = $this->requireUser();
        if (!Auth::hasRole($role, $user)) {
            Response::abort(403, 'No tienes permisos para esta acción.');
        }
        $key = (string) $user['id'];
        if (RateLimit::tooManyAttempts('admin_action', $key)) {
            $minutes = (int) ceil(RateLimit::availableIn('admin_action', $key) / 60);
            $this->done($back, t('Hiciste demasiadas acciones seguidas. Espera {min} min.', ['min' => $minutes]), 'error');
        }
        RateLimit::hit('admin_action', $key);
        return $user;
    }

    protected function done(string $back, string $message, string $type = 'success'): never
    {
        Session::flash($type, $message);
        Response::redirect($back);
    }

    /** Nota o motivo escrito en el formulario, en una línea y con el largo máximo permitido; null si está vacío. */
    protected function note(string $field = 'note'): ?string
    {
        $text = trim((string) preg_replace('/\s+/u', ' ', $this->cleanText(Request::text($field, false))));
        $max = (int) Config::get('app.limits.moderation_note', 255);
        return $text !== '' ? mb_substr($text, 0, $max) : null;
    }

    protected function pageNumber(): int
    {
        return max(1, min(1000, (int) Request::query('page', '1')));
    }

    protected function perPage(): int
    {
        return (int) Config::get('app.limits.admin_page', 25);
    }

    /** URL de la sección conservando los filtros dados (los vacíos se omiten). */
    protected function sectionUrl(string $section, array $query = []): string
    {
        return url(self::SECTIONS[$section]['path'], $query);
    }

    /** Valor de un filtro GET solo si es una clave permitida; si no, null. */
    protected function filter(string $key, array $allowed): ?string
    {
        $value = Request::query($key);
        return in_array($value, $allowed, true) ? $value : null;
    }
}
