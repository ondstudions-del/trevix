<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Controllers\Admin\AuditController as AdminAudit;
use Trevix\Controllers\Admin\SettingsController as AdminSettings;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\Community;
use Trevix\Models\RateLimit;
use Trevix\Services\Guard;
use Trevix\Services\Moderation;

/** Secciones solo para administradores: comunidades, configuración general y auditoría. */
final class AdminController extends ApiController
{
    /** GET /admin/communities?q=&status=active|suspended&page= */
    public function communities(): never
    {
        $status = Request::query('status');
        $result = Community::adminList(
            mb_substr(Request::query('q'), 0, 100),
            isset(Community::STATUS_LABELS[$status]) ? $status : null,
            $this->pageNumber(),
            $this->limit('admin_page', 25)
        );
        Reply::ok(Present::admin($result['communities']), $this->nextPage($result['hasMore']));
    }

    /** POST /admin/communities/{id}/suspend {reason} */
    public function suspendCommunity(string $id): never
    {
        $staff = $this->begin();
        Moderation::suspendCommunity($staff, $this->community((int) $id), (string) $this->reason());
        Reply::ok(['message' => 'Comunidad suspendida: deja de ser visible y nadie puede publicar en ella.']);
    }

    /** POST /admin/communities/{id}/restore {note?} */
    public function restoreCommunity(string $id): never
    {
        $staff = $this->begin();
        Moderation::restoreCommunity($staff, $this->community((int) $id), $this->reason('note'));
        Reply::ok(['message' => 'Comunidad reactivada.']);
    }

    /** DELETE /admin/communities/{id} {reason} */
    public function deleteCommunity(string $id): never
    {
        $staff = $this->begin();
        Moderation::deleteCommunity($staff, $this->community((int) $id), (string) $this->reason());
        Reply::ok(['message' => 'Comunidad eliminada junto con sus publicaciones.']);
    }

    /** GET /admin/settings */
    public function settings(): never
    {
        $all = AppSetting::all();
        $flags = [];
        foreach (AdminSettings::FLAGS as $key => $flag) {
            $flags[$key] = ['value' => ($all[$key] ?? '0') === '1', 'label' => $flag['label'], 'hint' => $flag['hint']];
        }
        Reply::ok([
            'flags'                 => $flags,
            'site_announcement'     => (string) ($all['site_announcement'] ?? ''),
            'max_announcement'      => (int) Config::get('app.limits.site_announcement', 200),
        ]);
    }

    /** PATCH /admin/settings {registration_open?, require_email_verification?, maintenance_mode?, site_announcement?} */
    public function updateSettings(): never
    {
        $staff = $this->begin();
        $all = AppSetting::all();
        $values = [];
        foreach (array_keys(AdminSettings::FLAGS) as $key) {
            $flag = Input::bool($key);
            $values[$key] = $flag === null ? (($all[$key] ?? '0') === '1' ? '1' : '0') : ($flag ? '1' : '0');
        }
        $announcement = Input::has('site_announcement')
            ? trim((string) preg_replace('/\s+/u', ' ', Guard::cleanText(Input::str('site_announcement', false))))
            : (string) ($all['site_announcement'] ?? '');
        $max = (int) Config::get('app.limits.site_announcement', 200);
        if (mb_strlen($announcement) > $max) {
            throw ActionError::field('site_announcement', 'El aviso puede tener como máximo ' . $max . ' caracteres.');
        }
        $values['site_announcement'] = $announcement;

        $changes = AppSetting::save($values);
        if ($changes !== []) {
            AuditLog::record((int) $staff['id'], 'settings.update', 'settings', null, $changes);
        }
        Reply::ok([
            'message' => $changes !== [] ? 'Configuración guardada.' : 'No había cambios que guardar.',
            'changed' => array_keys($changes),
        ]);
    }

    /** GET /admin/audit?group=&admin=&page= */
    public function audit(): never
    {
        $group = Request::query('group');
        $result = AuditLog::latest(
            isset(AdminAudit::GROUPS[$group]) ? $group : null,
            (int) Request::query('admin') ?: null,
            $this->pageNumber(),
            40
        );
        Reply::ok(Present::admin($result['entries']), $this->nextPage($result['hasMore']) + [
            'groups' => AdminAudit::GROUPS,
            'actors' => Present::admin(AuditLog::actors()),
        ]);
    }

    private function begin(): array
    {
        $staff = $this->user();
        $key = (string) $staff['id'];
        Guard::rateLimit('admin_action', $key, 'Hiciste demasiadas acciones seguidas. Espera {min} min.');
        RateLimit::hit('admin_action', $key);
        return $staff;
    }

    private function community(int $id): array
    {
        $community = $id > 0 ? Community::findAny($id) : null;
        if ($community === null) {
            throw new ActionError('Esta comunidad ya no existe.', 404);
        }
        return $community;
    }

    private function reason(string $field = 'reason'): ?string
    {
        return Guard::singleLine(Input::str($field, false), (int) Config::get('app.limits.moderation_note', 255));
    }
}
