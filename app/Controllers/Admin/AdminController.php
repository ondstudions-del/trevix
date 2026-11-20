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
use Trevix\Models\Ad;
use Trevix\Models\AndroidEarlyAccess;
use Trevix\Models\Appeal;
use Trevix\Models\OAuthApp;
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
    private const BADGE_TTL = 45;
    private const BADGE_CACHE = '/storage/cache/admin-badges.json';

    public const SECTIONS = [
        'dashboard'   => ['label' => 'Dashboard', 'icon' => 'layout-dashboard', 'path' => 'admin/', 'role' => 'moderator'],
        'reports'     => ['label' => 'Reportes', 'icon' => 'flag', 'path' => 'admin/reports.php', 'role' => 'moderator'],
        'content'     => ['label' => 'Contenido', 'icon' => 'file-text', 'path' => 'admin/content.php', 'role' => 'moderator'],
        'music'       => ['label' => 'Música', 'icon' => 'music', 'path' => 'admin/music.php', 'role' => 'moderator'],
        'oauth_apps'  => ['label' => 'Apps OAuth', 'icon' => 'app-window', 'path' => 'admin/oauth-apps.php', 'role' => 'moderator'],
        'users'       => ['label' => 'Usuarios', 'icon' => 'users', 'path' => 'admin/users.php', 'role' => 'moderator'],
        'appeals'     => ['label' => 'Apelaciones', 'icon' => 'scale', 'path' => 'admin/appeals.php', 'role' => 'moderator'],
        'support'     => ['label' => 'Soporte IX', 'icon' => 'sparkles', 'path' => 'admin/support.php', 'role' => 'moderator'],
        'verification' => ['label' => 'Verificación', 'icon' => 'badge-check', 'path' => 'admin/verification.php', 'role' => 'admin'],
        'wallet'      => ['label' => 'Monedero', 'icon' => 'wallet', 'path' => 'admin/wallet.php', 'role' => 'admin'],
        'gifts'       => ['label' => 'Regalos', 'icon' => 'gift', 'path' => 'admin/gifts.php', 'role' => 'admin'],
        'ads'         => ['label' => 'OND-ADS', 'icon' => 'megaphone', 'path' => 'admin/ads.php', 'role' => 'admin'],
        'push'        => ['label' => 'Avisos push', 'icon' => 'bell-ring', 'path' => 'admin/push.php', 'role' => 'admin'],
        'livekit'     => ['label' => 'LiveKit', 'icon' => 'video', 'path' => 'admin/livekit.php', 'role' => 'admin'],
        'early_access'=> ['label' => 'Acceso Anticipado', 'icon' => 'smartphone', 'path' => 'admin/early-access.php', 'role' => 'admin'],
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
            'title'   => t('{section} · Administración · TREVIX', ['section' => t(self::SECTIONS[$section]['label'] ?? 'Panel')]),
            'section' => $section,
            'sections'=> $sections,
            'staff'   => $staff,
        ] + $this->menuBadges($staff), 'layouts/admin');
    }

    /**
     * Paquete de badges del menú. Caché en disco ~45 s; se invalida al escribir.
     *
     * @return array{
     *   openReports:int,pendingSongs:int,openTickets:int,pendingAppeals:int,
     *   pendingVerifications:int,pendingWallet:int,pendingAds:int,pendingEarlyAccess:int,pendingOauthApps:int
     * }
     */
    protected function menuBadges(?array $staff): array
    {
        $empty = [
            'openReports' => 0,
            'pendingSongs' => 0,
            'openTickets' => 0,
            'pendingAppeals' => 0,
            'pendingVerifications' => 0,
            'pendingWallet' => 0,
            'pendingAds' => 0,
            'pendingEarlyAccess' => 0,
            'pendingOauthApps' => 0,
        ];
        if ($staff === null) {
            return $empty;
        }

        $isAdmin = Auth::hasRole('admin', $staff);
        $cached = self::readBadgeCache();
        if ($cached !== null) {
            return self::scopeBadges($cached + $empty, $isAdmin);
        }

        $badges = [
            'openReports' => Report::openCount(),
            'pendingSongs' => Song::pendingCount(),
            'openTickets' => Support::openCount(),
            'pendingAppeals' => Appeal::pendingCount(),
            'pendingVerifications' => VerificationRequest::pendingCount(),
            'pendingWallet' => Wallet::pendingCount(),
            'pendingAds' => Ad::reviewCount(),
            'pendingEarlyAccess' => 0,
            'pendingOauthApps' => 0,
        ];
        try {
            $badges['pendingEarlyAccess'] = AndroidEarlyAccess::pendingCount();
        } catch (\Throwable) {
            // Tabla aún no migrada.
        }
        try {
            $badges['pendingOauthApps'] = OAuthApp::pendingCount();
        } catch (\Throwable) {
            // Tabla aún no migrada.
        }
        self::writeBadgeCache($badges);

        return self::scopeBadges($badges, $isAdmin);
    }

    /** @param array<string,int> $badges */
    private static function scopeBadges(array $badges, bool $isAdmin): array
    {
        if (!$isAdmin) {
            $badges['pendingVerifications'] = 0;
            $badges['pendingWallet'] = 0;
            $badges['pendingAds'] = 0;
            $badges['pendingEarlyAccess'] = 0;
        }

        return $badges;
    }

    /** @return array<string,int>|null */
    private static function readBadgeCache(): ?array
    {
        $file = BASE_PATH . self::BADGE_CACHE;
        if (!is_file($file)) {
            return null;
        }
        $raw = @file_get_contents($file);
        if (!is_string($raw) || $raw === '') {
            return null;
        }
        $data = json_decode($raw, true);
        if (!is_array($data) || !isset($data['at'], $data['badges']) || !is_array($data['badges'])) {
            return null;
        }
        if ((time() - (int) $data['at']) >= self::BADGE_TTL) {
            return null;
        }

        $out = [];
        foreach ($data['badges'] as $key => $value) {
            $out[(string) $key] = (int) $value;
        }

        return $out;
    }

    /** @param array<string,int> $badges */
    private static function writeBadgeCache(array $badges): void
    {
        $file = BASE_PATH . self::BADGE_CACHE;
        $dir = dirname($file);
        if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
            return;
        }
        $payload = json_encode(['at' => time(), 'badges' => $badges], JSON_UNESCAPED_UNICODE);
        if ($payload === false) {
            return;
        }
        $tmp = $file . '.' . bin2hex(random_bytes(4));
        if (@file_put_contents($tmp, $payload) !== false) {
            @rename($tmp, $file);
        }
    }

    protected static function forgetBadges(): void
    {
        @unlink(BASE_PATH . self::BADGE_CACHE);
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
        self::forgetBadges();
        Session::flash($type, $message);
        Response::redirect($back);
    }

    protected function redirectBack(string $fallback): never
    {
        self::forgetBadges();
        parent::redirectBack($fallback);
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
