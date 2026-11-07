<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\Config;
use Trevix\Models\UserToken;

/** Correos de la cuenta: cada enlace lleva un token de un solo uso con vencimiento. */
final class AccountMail
{
    /** @param array{id:int|string, email:string, display_name:string} $user */
    public static function verification(array $user): bool
    {
        $token = UserToken::issue((int) $user['id'], 'email_verification');
        return Mailer::send(
            (string) $user['email'],
            'Confirma tu correo en TREVIX',
            'Confirma tu correo, ' . $user['display_name'],
            [
                'Gracias por unirte a TREVIX. Confirma que esta dirección es tuya para proteger tu cuenta y poder recuperarla si olvidas tu contraseña.',
                'El enlace vence en ' . self::hours('email_verification') . '.',
            ],
            'Confirmar correo',
            absolute_url('verify-email.php', ['token' => $token])
        );
    }

    /** @param array{id:int|string, email:string, display_name:string} $user */
    public static function passwordReset(array $user): bool
    {
        $token = UserToken::issue((int) $user['id'], 'password_reset');
        return Mailer::send(
            (string) $user['email'],
            'Restablece tu contraseña de TREVIX',
            'Restablece tu contraseña',
            [
                'Hola, ' . $user['display_name'] . '. Recibimos una solicitud para crear una nueva contraseña para tu cuenta.',
                'El enlace funciona una sola vez y vence en ' . self::hours('password_reset') . '. Si no lo pediste, ignora este correo: tu contraseña no cambiará.',
            ],
            'Crear nueva contraseña',
            absolute_url('reset-password.php', ['token' => $token])
        );
    }

    /** @param array{id:int|string, display_name:string} $user */
    public static function emailChange(array $user, string $newEmail): bool
    {
        $token = UserToken::issue((int) $user['id'], 'email_change', $newEmail);
        return Mailer::send(
            $newEmail,
            'Confirma tu nuevo correo en TREVIX',
            'Confirma tu nuevo correo',
            [
                'Hola, ' . $user['display_name'] . '. Pediste usar esta dirección en tu cuenta de TREVIX.',
                'Tu correo no cambiará hasta que lo confirmes. El enlace vence en ' . self::hours('email_change') . '.',
            ],
            'Confirmar nuevo correo',
            absolute_url('verify-email.php', ['token' => $token])
        );
    }

    /** Aviso de seguridad a la dirección actual tras un cambio importante en la cuenta. */
    public static function securityNotice(string $email, string $displayName, string $what): bool
    {
        return Mailer::send(
            $email,
            'Aviso de seguridad de TREVIX',
            'Hubo un cambio en tu cuenta',
            [
                'Hola, ' . $displayName . '. ' . $what,
                'Fecha: ' . full_date(date('Y-m-d H:i:s')) . '.',
                'Si no fuiste tú, recupera tu cuenta desde «¿Olvidaste tu contraseña?» y contacta con el equipo de TREVIX.',
            ],
            'Ir a TREVIX',
            absolute_url('login.php')
        );
    }

    private static function hours(string $type): string
    {
        $hours = (int) round((int) Config::get('app.security.token_ttl.' . $type, 3600) / 3600);
        return $hours === 1 ? '1 hora' : $hours . ' horas';
    }
}
