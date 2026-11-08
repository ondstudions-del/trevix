<?php
declare(strict_types=1);

namespace Trevix\Api;

use Trevix\Core\ActionError;
use Trevix\Core\Config;

/**
 * Datos enviados a la API. Acepta JSON (application/json), formularios (x-www-form-urlencoded) y
 * multipart/form-data (obligatorio para subir archivos, siempre con POST). Los valores escalares se
 * copian también a $_POST como texto para que el código compartido con la web los lea igual.
 */
final class Input
{
    private static array $data = [];

    public static function boot(string $method): void
    {
        $type = strtolower((string) ($_SERVER['CONTENT_TYPE'] ?? ''));
        if (str_contains($type, 'application/json')) {
            $max = (int) Config::get('app.api.max_json_bytes', 262144);
            $raw = (string) file_get_contents('php://input', false, null, 0, $max + 1);
            if (strlen($raw) > $max) {
                throw new ActionError('El cuerpo de la solicitud es demasiado grande.', 413);
            }
            if (trim($raw) === '') {
                $data = [];
            } else {
                $data = json_decode($raw, true);
                if (!is_array($data) || array_is_list($data) && $data !== []) {
                    throw new ActionError('El cuerpo debe ser un objeto JSON válido.', 400);
                }
            }
        } elseif ($method === 'POST') {
            $data = $_POST;
        } else {
            parse_str((string) file_get_contents('php://input', false, null, 0, 65536), $data);
        }

        self::$data = $data;
        $_POST = [];
        foreach ($data as $key => $value) {
            if (is_bool($value)) {
                $_POST[$key] = $value ? '1' : '0';
            } elseif (is_int($value) || is_float($value)) {
                $_POST[$key] = (string) $value;
            } elseif (is_string($value)) {
                $_POST[$key] = $value;
            }
        }
    }

    public static function has(string $key): bool
    {
        return array_key_exists($key, self::$data) && self::$data[$key] !== null;
    }

    /** Texto (recortado salvo $trim = false); los arreglos y el UTF-8 inválido cuentan como vacío. */
    public static function str(string $key, bool $trim = true): string
    {
        $value = self::$data[$key] ?? '';
        if (is_int($value) || is_float($value)) {
            $value = (string) $value;
        }
        if (!is_string($value) || !mb_check_encoding($value, 'UTF-8')) {
            return '';
        }
        return $trim ? trim($value) : $value;
    }

    /** Objeto de textos (p. ej. event[title], event[place]…); se ignoran las claves o valores que no sean texto. */
    public static function map(string $key): array
    {
        $value = self::$data[$key] ?? null;
        if (!is_array($value)) {
            return [];
        }
        $out = [];
        foreach ($value as $k => $v) {
            if (is_string($k) && (is_string($v) || is_int($v) || is_float($v)) && mb_check_encoding((string) $v, 'UTF-8')) {
                $out[$k] = (string) $v;
            }
        }
        return $out;
    }

    public static function int(string $key, int $default = 0): int
    {
        $value = self::$data[$key] ?? null;
        if (is_int($value)) {
            return $value;
        }
        if (is_string($value) && preg_match('/^-?\d{1,18}$/', trim($value))) {
            return (int) trim($value);
        }
        return $default;
    }

    /** true / false, 1 / 0, "true" / "false", "on" / "off"; null si no se envió o no es reconocible. */
    public static function bool(string $key): ?bool
    {
        $value = self::$data[$key] ?? null;
        if (is_bool($value)) {
            return $value;
        }
        if (is_int($value)) {
            return $value !== 0;
        }
        if (is_string($value)) {
            return match (strtolower(trim($value))) {
                '1', 'true', 'on', 'yes' => true,
                '0', 'false', 'off', 'no', '' => false,
                default => null,
            };
        }
        return null;
    }

    /** Valor de texto solo si pertenece a la lista; si no se envió devuelve $default; si es otro valor, error 422. */
    public static function in(string $key, array $allowed, ?string $default = null, string $message = 'Valor no válido.'): ?string
    {
        if (!self::has($key)) {
            return $default;
        }
        $value = self::str($key);
        if (!in_array($value, $allowed, true)) {
            throw ActionError::field($key, $message);
        }
        return $value;
    }
}
