<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Models\AppSetting;
use Trevix\Models\RateLimit;

/** Comprobaciones comunes de la web y la API: correo verificado, límites de uso y limpieza de texto. */
final class Guard
{
    /** Partes que una restricción parcial puede bloquear. */
    public const RESTRICT_PARTS = [
        'messages'   => 'enviar mensajes',
        'posts'      => 'publicar',
        'stories'    => 'subir historias',
        'comments'   => 'comentar',
        'gifts'      => 'enviar regalos',
        'profile'    => 'cambiar el perfil',
        'communities'=> 'unirse a grupos o comunidades',
    ];

    /** Si la configuración exige correo verificado, bloquea publicar, comentar, escribir y crear hasta confirmarlo. */
    public static function verifiedEmail(array $user): void
    {
        if (empty($user['email_verified_at']) && AppSetting::flag('require_email_verification')) {
            throw new ActionError('Confirma tu correo para participar. Puedes reenviar el enlace desde Configuración › Cuenta.', 403);
        }
    }

    /**
     * Bloquea una acción si la cuenta tiene restricción activa que incluye $part.
     * La persona sigue pudiendo iniciar sesión; solo se limitan las partes elegidas.
     */
    public static function assertAllowed(array $user, string $part): void
    {
        $info = self::restrictionInfo($user);
        if ($info === null) {
            return;
        }
        $parts = $info['parts'];
        if ($parts !== [] && !in_array($part, $parts, true)) {
            return;
        }
        $label = self::RESTRICT_PARTS[$part] ?? $part;
        $until = $info['until_label'];
        $reason = $info['reason'] !== '' ? $info['reason'] : 'incumplimiento de las normas';
        throw new ActionError(
            t('Tu cuenta está restringida: no puedes {action}. Motivo: {reason}. Hasta: {until}.', [
                'action' => $label,
                'reason' => $reason,
                'until'  => $until,
            ]),
            403
        );
    }

    /**
     * @return array{reason:string,until:string|null,until_label:string,parts:list<string>}|null
     */
    public static function restrictionInfo(array $user): ?array
    {
        $until = $user['restricted_until'] ?? null;
        if ($until === null || $until === '') {
            return null;
        }
        $ts = strtotime((string) $until);
        if ($ts === false || $ts <= time()) {
            return null;
        }
        $parts = [];
        $raw = $user['restriction_parts'] ?? null;
        if (is_string($raw) && $raw !== '') {
            $decoded = json_decode($raw, true);
            $raw = is_array($decoded) ? $decoded : [];
        }
        if (is_array($raw)) {
            foreach ($raw as $p) {
                $p = (string) $p;
                if (isset(self::RESTRICT_PARTS[$p])) {
                    $parts[] = $p;
                }
            }
        }
        return [
            'reason'      => trim((string) ($user['restriction_reason'] ?? '')),
            'until'       => date('c', $ts),
            'until_label' => date('d/m/Y H:i', $ts),
            'parts'       => array_values(array_unique($parts)),
        ];
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
