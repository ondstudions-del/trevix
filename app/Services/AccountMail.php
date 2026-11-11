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
            t('Confirma tu correo en TREVIX'),
            t('Confirma tu correo, {name}', ['name' => $user['display_name']]),
            [
                t('Gracias por unirte a TREVIX. Confirma que esta dirección es tuya para proteger tu cuenta y poder recuperarla si olvidas tu contraseña.'),
                t('El enlace vence en {time}.', ['time' => self::hours('email_verification')]),
            ],
            t('Confirmar correo'),
            absolute_url('verify-email.php', ['token' => $token])
        );
    }

    /** @param array{id:int|string, email:string, display_name:string} $user */
    public static function passwordReset(array $user): bool
    {
        $token = UserToken::issue((int) $user['id'], 'password_reset');
        return Mailer::send(
            (string) $user['email'],
            t('Restablece tu contraseña de TREVIX'),
            t('Restablece tu contraseña'),
            [
                t('Hola, {name}. Recibimos una solicitud para crear una nueva contraseña para tu cuenta.', ['name' => $user['display_name']]),
                t('El enlace funciona una sola vez y vence en {time}. Si no lo pediste, ignora este correo: tu contraseña no cambiará.', ['time' => self::hours('password_reset')]),
            ],
            t('Crear nueva contraseña'),
            absolute_url('reset-password.php', ['token' => $token])
        );
    }

    /** @param array{id:int|string, display_name:string} $user */
    public static function emailChange(array $user, string $newEmail): bool
    {
        $token = UserToken::issue((int) $user['id'], 'email_change', $newEmail);
        return Mailer::send(
            $newEmail,
            t('Confirma tu nuevo correo en TREVIX'),
            t('Confirma tu nuevo correo'),
            [
                t('Hola, {name}. Pediste usar esta dirección en tu cuenta de TREVIX.', ['name' => $user['display_name']]),
                t('Tu correo no cambiará hasta que lo confirmes. El enlace vence en {time}.', ['time' => self::hours('email_change')]),
            ],
            t('Confirmar nuevo correo'),
            absolute_url('verify-email.php', ['token' => $token])
        );
    }

    /** Aviso de seguridad a la dirección actual tras un cambio importante en la cuenta. */
    public static function securityNotice(string $email, string $displayName, string $what): bool
    {
        return Mailer::send(
            $email,
            t('Aviso de seguridad de TREVIX'),
            t('Hubo un cambio en tu cuenta'),
            [
                t('Hola, {name}.', ['name' => $displayName]) . ' ' . t($what),
                t('Fecha: {date}.', ['date' => full_date(date('Y-m-d H:i:s'))]),
                t('Si no fuiste tú, recupera tu cuenta desde «¿Olvidaste tu contraseña?» y contacta con el equipo de TREVIX.'),
            ],
            t('Ir a TREVIX'),
            absolute_url('login.php')
        );
    }

    /** Respuesta del equipo a una apelación (llega aunque la cuenta siga suspendida y no pueda ver sus avisos). */
    public static function appealDecision(string $email, string $displayName, string $type, bool $accepted, ?string $note): bool
    {
        $lines = [
            $type === 'suspension'
                ? t('Hola, {name}. El equipo de TREVIX revisó tu apelación sobre la suspensión de tu cuenta.', ['name' => $displayName])
                : t('Hola, {name}. El equipo de TREVIX revisó tu apelación sobre una advertencia.', ['name' => $displayName]),
            $accepted
                ? ($type === 'suspension' ? t('La aceptamos: levantamos la suspensión y ya puedes volver a entrar.') : t('La aceptamos: retiramos la advertencia de tu cuenta.'))
                : t('No la aceptamos: la sanción se mantiene.'),
        ];
        if ($note !== null && $note !== '') {
            $lines[] = t('Nota del equipo: {note}', ['note' => $note]);
        }
        return Mailer::send(
            $email,
            $accepted ? t('Aceptamos tu apelación en TREVIX') : t('Respuesta a tu apelación en TREVIX'),
            $accepted ? t('Aceptamos tu apelación') : t('Revisamos tu apelación'),
            $lines,
            t('Ir a TREVIX'),
            absolute_url($accepted || $type === 'warning' ? 'login.php' : 'appeal.php')
        );
    }

    private static function hours(string $type): string
    {
        $hours = (int) round((int) Config::get('app.security.token_ttl.' . $type, 3600) / 3600);
        return tn($hours, '{n} hora', '{n} horas');
    }
}
