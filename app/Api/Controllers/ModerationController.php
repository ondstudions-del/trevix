<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Controllers\Admin\ContentController as AdminContent;
use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Models\AdminStats;
use Trevix\Models\AuditLog;
use Trevix\Models\Comment;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\Report;
use Trevix\Models\User;
use Trevix\Models\VerificationRequest;
use Trevix\Models\Warning;
use Trevix\Services\Guard;
use Trevix\Services\Moderation;
use Trevix\Services\ReportDecision;
use Trevix\Services\VerificationService;

/**
 * Panel de moderación (moderadores y administradores): resumen, cola de reportes, contenido y cuentas.
 * Mismas reglas que el panel web: jerarquía de roles, límite de acciones y registro de auditoría.
 */
final class ModerationController extends ApiController
{
    /** GET /admin/dashboard */
    public function dashboard(): never
    {
        $staff = $this->user();
        Reply::ok(Present::admin([
            'stats'        => AdminStats::overview(),
            'open_reports' => Report::openCount(),
            'reports'      => Report::targets('open', null, 1, 5)['targets'],
            'audit'        => Auth::hasRole('admin', $staff) ? AuditLog::latest(null, null, 1, 6)['entries'] : null,
            'pending_verifications' => Auth::hasRole('admin', $staff) ? VerificationRequest::pendingCount() : null,
        ]));
    }

    /** GET /admin/reports?status=open|resolved|dismissed&type=&page= */
    public function reports(): never
    {
        $status = Request::queryIn('status', array_keys(Report::STATUS_GROUPS), 'open');
        $type = Request::query('type');
        $result = Report::targets($status, isset(Report::TYPES[$type]) ? $type : null, $this->pageNumber(), $this->perPage());
        Reply::ok(Present::admin($result['targets']), $this->nextPage($result['hasMore']) + ['open_by_type' => Report::openCountsByType()]);
    }

    /** GET /admin/reports/{type}/{id} — reportes del objetivo, vista previa, medidas posibles e historial. */
    public function report(string $type, string $id): never
    {
        $staff = $this->user();
        $type = $this->reportType($type);
        $reports = Report::forTarget($type, (int) $id);
        if ($reports === []) {
            $this->notFound('Este reporte no existe.');
        }
        $preview = Report::preview($type, (int) $id);
        $pending = array_filter($reports, static fn (array $r) => in_array($r['status'], ['open', 'reviewing'], true));
        Reply::ok(Present::admin([
            'type'      => $type,
            'id'        => (int) $id,
            'preview'   => $preview,
            'reports'   => $reports,
            'pending'   => count($pending),
            'reviewing' => in_array('reviewing', array_column($pending, 'status'), true),
            'measures'  => $preview !== null ? ReportDecision::measures($staff, $type, $preview) : [],
            'durations' => ReportDecision::durations($staff),
            'history'   => AuditLog::forTarget($type, (int) $id),
        ]));
    }

    /** POST /admin/reports/{type}/{id}/take — marcar como «en revisión». */
    public function takeReports(string $type, string $id): never
    {
        $staff = $this->begin();
        Moderation::takeReports($staff, $this->reportType($type), (int) $id);
        Reply::ok(['message' => 'Marcaste estos reportes como "en revisión".']);
    }

    /** POST /admin/reports/{type}/{id}/dismiss {note?} */
    public function dismissReports(string $type, string $id): never
    {
        $staff = $this->begin();
        Moderation::closeReports($staff, $this->reportType($type), (int) $id, 'dismissed', $this->note());
        Reply::ok(['message' => 'Reportes descartados: el contenido se mantiene.']);
    }

    /** POST /admin/reports/{type}/{id}/resolve {measure, days?, note?} — medidas de GET /admin/reports/{type}/{id}. */
    public function resolveReports(string $type, string $id): never
    {
        $staff = $this->begin();
        $measure = Input::str('measure');
        $message = ReportDecision::resolve(
            $staff,
            $this->reportType($type),
            (int) $id,
            $measure !== '' ? $measure : 'none',
            Input::has('days') ? Input::int('days') : 7,
            $this->note()
        );
        Reply::ok(['message' => $message]);
    }

    /** GET /admin/posts?q=&status=published|hidden&page= */
    public function posts(): never
    {
        $status = Request::query('status');
        $result = Post::adminList(
            mb_substr(Request::query('q'), 0, 100),
            isset(AdminContent::POST_STATUSES[$status]) ? $status : null,
            $this->pageNumber(),
            $this->perPage()
        );
        Reply::ok(Present::admin($result['posts']), $this->nextPage($result['hasMore']));
    }

    /** GET /admin/comments?q=&page= */
    public function comments(): never
    {
        $result = Comment::adminList(mb_substr(Request::query('q'), 0, 100), $this->pageNumber(), $this->perPage());
        Reply::ok(Present::admin($result['comments']), $this->nextPage($result['hasMore']));
    }

    /** POST /admin/posts/{id}/hide · /restore {note?} */
    public function postAction(string $id, string $action): never
    {
        $staff = $this->begin();
        $target = Report::preview('post', (int) $id) ?? throw new ActionError('La publicación ya no existe.', 404);
        if ($action === 'hide') {
            Moderation::hidePost($staff, $target, $this->note());
            Reply::ok(['message' => 'Publicación ocultada: ya no aparece en TREVIX.']);
        }
        Moderation::restorePost($staff, $target, $this->note());
        Reply::ok(['message' => 'Publicación restaurada.']);
    }

    /** POST|DELETE /admin/posts/{id}/feature — destacar (solo administradores). */
    public function feature(string $id, bool $feature): never
    {
        Moderation::featurePost($this->begin(), (int) $id, $feature);
        Reply::ok([
            'featured' => $feature,
            'message'  => $feature ? 'Publicación destacada.' : 'La publicación ya no está destacada.',
        ]);
    }

    /** DELETE /admin/posts/{id} {note?} */
    public function deletePost(string $id): never
    {
        $staff = $this->begin();
        $target = Report::preview('post', (int) $id) ?? throw new ActionError('La publicación ya no existe.', 404);
        Moderation::deletePost($staff, $target, $this->note());
        Reply::ok(['message' => 'Publicación eliminada definitivamente.']);
    }

    /** DELETE /admin/comments/{id} {note?} */
    public function deleteComment(string $id): never
    {
        $staff = $this->begin();
        $target = Report::preview('comment', (int) $id);
        if ($target === null || $target['status'] !== 'published') {
            throw new ActionError('El comentario ya no existe.', 404);
        }
        Moderation::deleteComment($staff, $target, $this->note());
        Reply::ok(['message' => 'Comentario eliminado.']);
    }

    /** GET /admin/users?q=&role=&status=&page= */
    public function users(): never
    {
        $role = Request::query('role');
        $status = Request::query('status');
        $result = User::adminList(
            mb_substr(Request::query('q'), 0, 100),
            isset(User::ROLE_LABELS[$role]) ? $role : null,
            isset(User::STATUS_LABELS[$status]) ? $status : null,
            $this->pageNumber(),
            $this->perPage()
        );
        Reply::ok(Present::admin($result['users']), $this->nextPage($result['hasMore']));
    }

    /** GET /admin/users/{id} */
    public function showUser(string $id): never
    {
        $staff = $this->user();
        $target = User::findForAdmin((int) $id) ?? throw new ActionError('Esta cuenta no existe.', 404);
        Reply::ok(Present::admin([
            'user'         => $target,
            'can_act'      => Moderation::canActOnUser($staff, $target),
            'is_self'      => (int) $staff['id'] === (int) $target['id'],
            'open_reports' => Report::openAgainstUser((int) $id),
            'posts'        => Post::adminList('@' . $target['username'], null, 1, 5)['posts'],
            'history'      => AuditLog::forTarget('user', (int) $id),
            'durations'    => ReportDecision::durations($staff),
            'warnings'     => Warning::forUser((int) $id, true),
        ]));
    }

    /** POST /admin/users/{id}/suspend {days: 0 = sin fecha de fin, reason} — cierra sus sesiones web y de la app. */
    public function suspend(string $id): never
    {
        $staff = $this->begin();
        $target = $this->target((int) $id);
        $days = Input::has('days') ? Input::int('days') : 7;
        Moderation::suspendUser($staff, $target, $days > 0 ? $days : null, (string) $this->note('reason'));
        Reply::ok(['message' => t('Cuenta de @{username} suspendida. Sus sesiones abiertas se cerraron.', ['username' => $target['username']])]);
    }

    /** POST /admin/users/{id}/unsuspend {note?} */
    public function unsuspend(string $id): never
    {
        $staff = $this->begin();
        $target = $this->target((int) $id);
        Moderation::unsuspendUser($staff, $target, $this->note());
        Reply::ok(['message' => t('Suspensión levantada: @{username} ya puede entrar.', ['username' => $target['username']])]);
    }

    /** PUT /admin/users/{id}/role {role: user|moderator|admin} (solo administradores). */
    public function role(string $id): never
    {
        $staff = $this->begin();
        $target = $this->target((int) $id);
        $role = Input::str('role');
        Moderation::setRole($staff, $target, $role);
        Reply::ok(['message' => t('Rol actualizado a {role}.', ['role' => t(User::ROLE_LABELS[$role] ?? $role)])]);
    }

    /** POST|DELETE /admin/users/{id}/verification — insignia de verificación. */
    public function verification(string $id): never
    {
        $staff = $this->begin();
        $verify = Request::method() !== 'DELETE';
        Moderation::setVerified($staff, $this->target((int) $id), $verify);
        Reply::ok(['message' => $verify ? 'Insignia de verificación añadida.' : 'Insignia de verificación retirada.']);
    }

    /** POST /admin/users/{id}/warn {reason} — advertencia con aviso a la persona. */
    public function warn(string $id): never
    {
        $staff = $this->begin();
        $target = $this->target((int) $id);
        Moderation::warnUser($staff, $target, (string) $this->note('reason'));
        Reply::ok(['message' => t('Advertimos a @{username}. Le llegó un aviso con el motivo.', ['username' => $target['username']])]);
    }

    /** DELETE /admin/warnings/{id} {note?} — retirar una advertencia. */
    public function revokeWarning(string $id): never
    {
        Moderation::revokeWarning($this->begin(), (int) $id, $this->note());
        Reply::ok(['message' => 'Advertencia retirada.']);
    }

    /** GET /admin/verification?status=pending|approved|rejected|cancelled&page= (solo administradores) */
    public function verifications(): never
    {
        $status = Request::queryIn('status', array_keys(VerificationRequest::STATUSES), 'pending');
        $rules = VerificationService::rules();
        $result = VerificationRequest::adminList($status, $this->pageNumber(), $this->perPage(), $rules['warning_days']);
        $rows = array_map(static function (array $r) use ($status): array {
            $now = $status === 'pending'
                ? VerificationService::eligibility(['id' => $r['user_id'], 'followers_count' => $r['current_followers']])
                : null;
            return $r + [
                'category_label' => t(VerificationRequest::CATEGORIES[$r['category']] ?? $r['category']),
                'eligible_now'   => $now['eligible'] ?? null,
                'checks_now'     => $now['checks'] ?? null,
            ];
        }, $result['requests']);
        Reply::ok(Present::admin($rows), $this->nextPage($result['hasMore']) + ['counts' => VerificationRequest::counts(), 'rules' => $rules]);
    }

    /** POST /admin/verification/{id}/approve {note?} — pone la insignia y avisa. */
    public function approveVerification(string $id): never
    {
        $request = VerificationService::approve($this->begin(), (int) $id, $this->note());
        Reply::ok(['message' => t('Verificaste a {name}. Le avisamos.', ['name' => $request['full_name']])]);
    }

    /** POST /admin/verification/{id}/reject {reason} — la persona ve el motivo. */
    public function rejectVerification(string $id): never
    {
        VerificationService::reject($this->begin(), (int) $id, (string) $this->note('reason'));
        Reply::ok(['message' => 'Solicitud rechazada. Le avisamos con el motivo.']);
    }

    /** Escritura: límite de acciones del panel por persona (el mismo que en la web). */
    private function begin(): array
    {
        $staff = $this->user();
        $key = (string) $staff['id'];
        Guard::rateLimit('admin_action', $key, 'Hiciste demasiadas acciones seguidas. Espera {min} min.');
        RateLimit::hit('admin_action', $key);
        return $staff;
    }

    private function target(int $id): array
    {
        $target = $id > 0 ? User::findForAdmin($id) : null;
        if ($target === null) {
            throw new ActionError('Esta cuenta ya no existe.', 404);
        }
        return $target;
    }

    private function reportType(string $type): string
    {
        if (!isset(Report::TYPES[$type])) {
            throw new ActionError('Tipo de reporte no válido.', 400);
        }
        return $type;
    }

    private function note(string $field = 'note'): ?string
    {
        return Guard::singleLine(Input::str($field, false), (int) Config::get('app.limits.moderation_note', 255));
    }

    private function perPage(): int
    {
        return $this->limit('admin_page', 25);
    }
}
