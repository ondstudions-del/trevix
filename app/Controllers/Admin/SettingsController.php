<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;

/** Configuración general (solo administradores): registro, verificación de correo, mantenimiento y aviso. */
final class SettingsController extends AdminController
{
    public const FLAGS = [
        'registration_open' => [
            'label' => 'Registro abierto',
            'hint'  => 'Si lo desactivas, nadie puede crear cuentas nuevas. Quienes ya tienen cuenta siguen entrando.',
        ],
        'require_email_verification' => [
            'label' => 'Exigir correo verificado para participar',
            'hint'  => 'Sin verificar el correo no se puede publicar, comentar, enviar mensajes, crear historias ni comunidades.',
        ],
        'maintenance_mode' => [
            'label' => 'Modo mantenimiento',
            'hint'  => 'Solo moderadores y administradores pueden usar TREVIX; el resto ve un aviso de mantenimiento.',
        ],
    ];

    public function handle(): void
    {
        $this->guard('settings');
        if (Request::isPost()) {
            $this->save();
        }
        $this->page('settings', 'settings', [
            'settings' => AppSetting::all(),
            'flags'    => self::FLAGS,
            'maxAnnouncement' => (int) Config::get('app.limits.site_announcement', 200),
        ]);
    }

    private function save(): never
    {
        $back = $this->sectionUrl('settings');
        $staff = $this->beginAction('admin', $back);

        $values = [];
        foreach (array_keys(self::FLAGS) as $key) {
            $values[$key] = Request::input($key) === '1' ? '1' : '0';
        }
        $announcement = trim((string) preg_replace('/\s+/u', ' ', $this->cleanText(Request::text('site_announcement', false))));
        $max = (int) Config::get('app.limits.site_announcement', 200);
        if (mb_strlen($announcement) > $max) {
            $this->done($back, 'El aviso puede tener como máximo ' . $max . ' caracteres.', 'error');
        }
        $values['site_announcement'] = $announcement;

        $changes = AppSetting::save($values);
        if ($changes === []) {
            $this->done($back, 'No había cambios que guardar.', 'info');
        }
        AuditLog::record((int) $staff['id'], 'settings.update', 'settings', null, $changes);
        $this->done($back, 'Configuración guardada.');
    }
}
