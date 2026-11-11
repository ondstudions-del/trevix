<?php
declare(strict_types=1);

namespace Trevix\Models;

use Throwable;

/**
 * Configuración general editable desde el panel (tabla app_settings). Se lee una sola vez por petición;
 * si la base no responde (por ejemplo en la vista previa sin MySQL) se usan los valores por defecto.
 */
final class AppSetting extends Model
{
    public const DEFAULTS = [
        'site_name'                  => 'TREVIX',
        'registration_open'          => '1',
        'require_email_verification' => '0',
        'maintenance_mode'           => '0',
        'site_announcement'          => '',
        // IX (panel › Soporte IX). Vacío = el valor de config/app.php › ix.
        'ix_replies'                 => '1',
        'ix_welcome'                 => '1',
        'ix_model'                   => '',
        'ix_pause_hours'             => '',
        'ix_instructions'            => '',
        // Colaboradores y monedero (panel › Monedero). Importes en dólares (USD).
        'collab_min_followers'       => '1000',
        'collab_min_avg_likes'       => '100',
        'collab_min_avg_views'       => '300',
        'collab_min_posts'           => '5',
        'collab_views_days'          => '30',
        'collab_commission'          => '20',
        'collab_min_price'           => '1',
        'collab_max_price'           => '500',
        'collab_max_days'            => '365',
        'wallet_max_topup'           => '1000',
        'wallet_min_withdrawal'      => '10',
    ];

    /** Claves que el panel puede modificar. */
    public const EDITABLE = ['registration_open', 'require_email_verification', 'maintenance_mode', 'site_announcement',
        'ix_replies', 'ix_welcome', 'ix_model', 'ix_pause_hours', 'ix_instructions',
        'collab_min_followers', 'collab_min_avg_likes', 'collab_min_avg_views', 'collab_min_posts', 'collab_views_days',
        'collab_commission', 'collab_min_price', 'collab_max_price', 'collab_max_days', 'wallet_max_topup', 'wallet_min_withdrawal'];

    /** Nombre corto y textos de cada valor (null = mostrar el valor tal cual), para mostrar cambios en la auditoría. */
    public const CHANGE_LABELS = [
        'registration_open'          => ['Registro', ['0' => 'cerrado', '1' => 'abierto']],
        'require_email_verification' => ['Correo verificado', ['0' => 'opcional', '1' => 'obligatorio']],
        'maintenance_mode'           => ['Mantenimiento', ['0' => 'desactivado', '1' => 'activado']],
        'site_announcement'          => ['Aviso general', []],
        'ix_replies'                 => ['Respuestas de IX', ['0' => 'en pausa', '1' => 'activas']],
        'ix_welcome'                 => ['Bienvenida de IX', ['0' => 'desactivada', '1' => 'activada']],
        'ix_model'                   => ['Modelo de IX', null],
        'ix_pause_hours'             => ['Horas de pausa de IX', null],
        'ix_instructions'            => ['Indicaciones para IX', []],
        'collab_min_followers'       => ['Colaborador: seguidores mínimos', null],
        'collab_min_avg_likes'       => ['Colaborador: promedio de «Me gusta»', null],
        'collab_min_avg_views'       => ['Colaborador: promedio de visualizaciones', null],
        'collab_min_posts'           => ['Colaborador: publicaciones mínimas', null],
        'collab_views_days'          => ['Colaborador: días para las visualizaciones', null],
        'collab_commission'          => ['Comisión de TREVIX (%)', null],
        'collab_min_price'           => ['Precio mínimo de suscripción (USD)', null],
        'collab_max_price'           => ['Precio máximo de suscripción (USD)', null],
        'collab_max_days'            => ['Días máximos por suscripción', null],
        'wallet_max_topup'           => ['Recarga máxima (USD)', null],
        'wallet_min_withdrawal'      => ['Retiro mínimo (USD)', null],
    ];

    /** Describe un cambio de configuración, p. ej. "Registro: abierto → cerrado". */
    public static function describeChange(string $key, array $change): string
    {
        [$label, $values] = self::CHANGE_LABELS[$key] ?? [$key, []];
        $label = t($label);
        if ($values === null) {
            return $label . ': ' . ((string) ($change[0] ?? '') ?: t('predeterminado')) . ' → ' . ((string) ($change[1] ?? '') ?: t('predeterminado'));
        }
        if ($values === []) {
            $new = (string) ($change[1] ?? '');
            return $label . ': ' . ($new === '' ? t('quitado') : t('actualizado'));
        }
        return $label . ': ' . t($values[(string) ($change[0] ?? '')] ?? '?') . ' → ' . t($values[(string) ($change[1] ?? '')] ?? '?');
    }

    private static ?array $cache = null;

    /** @return array<string, string> */
    public static function all(): array
    {
        if (self::$cache !== null) {
            return self::$cache;
        }
        $values = self::DEFAULTS;
        try {
            foreach (self::fetchAll('SELECT setting_key, setting_value FROM app_settings') as $row) {
                if (array_key_exists($row['setting_key'], $values)) {
                    $values[$row['setting_key']] = (string) ($row['setting_value'] ?? '');
                }
            }
        } catch (Throwable) {
            // Sin base de datos se mantienen los valores por defecto.
        }
        return self::$cache = $values;
    }

    public static function get(string $key): string
    {
        return self::all()[$key] ?? '';
    }

    public static function flag(string $key): bool
    {
        return self::get($key) === '1';
    }

    /**
     * Guarda los valores que cambiaron y devuelve [clave => [antes, después]].
     * @param array<string, string> $values
     */
    public static function save(array $values): array
    {
        $current = self::all();
        $changes = [];
        foreach (self::EDITABLE as $key) {
            if (!array_key_exists($key, $values) || $values[$key] === $current[$key]) {
                continue;
            }
            self::execute(
                'INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?)
                 ON DUPLICATE KEY UPDATE setting_value = ?',
                [$key, $values[$key], $values[$key]]
            );
            $changes[$key] = [$current[$key], $values[$key]];
        }
        self::$cache = null;
        return $changes;
    }
}
