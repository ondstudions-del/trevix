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
    ];

    /** Claves que el panel puede modificar. */
    public const EDITABLE = ['registration_open', 'require_email_verification', 'maintenance_mode', 'site_announcement'];

    /** Nombre corto y textos de cada valor, para mostrar cambios en la auditoría. */
    public const CHANGE_LABELS = [
        'registration_open'          => ['Registro', ['0' => 'cerrado', '1' => 'abierto']],
        'require_email_verification' => ['Correo verificado', ['0' => 'opcional', '1' => 'obligatorio']],
        'maintenance_mode'           => ['Mantenimiento', ['0' => 'desactivado', '1' => 'activado']],
        'site_announcement'          => ['Aviso general', []],
    ];

    /** Describe un cambio de configuración, p. ej. "Registro: abierto → cerrado". */
    public static function describeChange(string $key, array $change): string
    {
        [$label, $values] = self::CHANGE_LABELS[$key] ?? [$key, []];
        if ($values === []) {
            $new = (string) ($change[1] ?? '');
            return $label . ': ' . ($new === '' ? 'quitado' : 'actualizado');
        }
        return $label . ': ' . ($values[(string) ($change[0] ?? '')] ?? '?') . ' → ' . ($values[(string) ($change[1] ?? '')] ?? '?');
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
