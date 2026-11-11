<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Models\AppSetting;
use Trevix\Models\RateLimit;

/** Comprobaciones comunes de la web y la API: correo verificado, límites de uso y limpieza de texto. */
final class Guard
{
    /** Si la configuración exige correo verificado, bloquea publicar, comentar, escribir y crear hasta confirmarlo. */
    public static function verifiedEmail(array $user): void
    {
        if (empty($user['email_verified_at']) && AppSetting::flag('require_email_verification')) {
            throw new ActionError('Confirma tu correo para participar. Puedes reenviar el enlace desde Configuración › Cuenta.', 403);
        }
    }

    /**
     * Lanza un 429 si se superó el límite. En $message, «{min}» se reemplaza por los minutos de espera.
     * No registra el intento: eso se hace con RateLimit::hit cuando la acción pasa las validaciones.
     */
    public static function rateLimit(string $action, string $key, string $message): void
    {
        if (RateLimit::tooManyAttempts($action, $key)) {
            $seconds = RateLimit::availableIn($action, $key);
            $minutes = (string) max(1, (int) ceil($seconds / 60));
            throw new ActionError(t($message, ['min' => $minutes]), 429, [], max(1, $seconds));
        }
    }

    /** Texto multilínea escrito por el usuario: normaliza saltos y quita caracteres de control. */
    public static function cleanText(string $text): string
    {
        $text = str_replace(["\r\n", "\r"], "\n", $text);
        $text = (string) preg_replace('/[\x{0000}-\x{0008}\x{000B}-\x{001F}\x{007F}\x{2028}\x{2029}]/u', '', $text);
        $text = (string) preg_replace("/\n{3,}/", "\n\n", $text);
        return trim($text);
    }

    /** Texto de una sola línea (notas y motivos), recortado al largo máximo; null si queda vacío. */
    public static function singleLine(string $text, int $max): ?string
    {
        $text = trim((string) preg_replace('/\s+/u', ' ', self::cleanText($text)));
        return $text !== '' ? mb_substr($text, 0, $max) : null;
    }
}
