<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Models\AndroidEarlyAccess;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\RateLimit;

/** Solicitudes públicas de acceso anticipado a Android y aceptación desde el panel. */
final class EarlyAccessService
{
    public const NAME_MAX = 120;
    public const EMAIL_MAX = 190;
    public const INSTRUCTIONS_MAX = 4000;
    public const URL_MAX = 500;

    public static function submit(string $fullName, string $email): void
    {
        $ip = Request::ip();
        if (RateLimit::tooManyAttempts('early_access', $ip) || RateLimit::tooManyAttempts('early_access_ip', $ip)) {
            throw new ActionError(t('Enviaste demasiadas solicitudes. Espera un rato e inténtalo de nuevo.'), 429, ['form' => t('Enviaste demasiadas solicitudes. Espera un rato e inténtalo de nuevo.')]);
        }
        RateLimit::hit('early_access_ip', $ip);

        $name = trim(preg_replace('/\s+/u', ' ', $fullName) ?? '');
        $mail = mb_strtolower(trim($email));
        $errors = [];
        if ($name === '' || mb_strlen($name) < 2) {
            $errors['full_name'] = t('Escribe tu nombre (mínimo 2 caracteres).');
        } elseif (mb_strlen($name) > self::NAME_MAX) {
            $errors['full_name'] = t('El nombre es demasiado largo.');
        }
        if ($mail === '' || !filter_var($mail, FILTER_VALIDATE_EMAIL) || mb_strlen($mail) > self::EMAIL_MAX) {
            $errors['email'] = t('Escribe un correo válido.');
        }
        if ($errors !== []) {
            throw new ActionError(t('Revisa el formulario.'), 422, $errors);
        }

        $existing = AndroidEarlyAccess::findByEmail($mail);
        if ($existing !== null) {
            if ($existing['status'] === 'pending') {
                throw new ActionError(t('Ya tenemos tu solicitud. Cuando el equipo te añada a la lista de verificadores te escribiremos.'), 422, ['form' => t('Ya tenemos tu solicitud. Cuando el equipo te añada a la lista de verificadores te escribiremos.')]);
            }
            if ($existing['status'] === 'accepted') {
                throw new ActionError(t('Este correo ya tiene acceso anticipado. Revisa tu bandeja (y el spam) o escribe a soporte.'), 422, ['form' => t('Este correo ya tiene acceso anticipado. Revisa tu bandeja (y el spam) o escribe a soporte.')]);
            }
            // Rechazada: permitir volver a pedir.
            AndroidEarlyAccess::reopen((int) $existing['id'], $name, @inet_pton($ip) ?: null);
            RateLimit::hit('early_access', $ip);
            return;
        }

        AndroidEarlyAccess::create($name, $mail, @inet_pton($ip) ?: null);
        RateLimit::hit('early_access', $ip);
    }

    /**
     * El administrador ya añadió el correo en Play Console: marca como aceptada y envía el correo con el enlace.
     *
     * @param array{id:int|string} $admin
     * @return array{full_name:string,email:string}
     */
    public static function accept(array $admin, int $id, ?string $note = null): array
    {
        $row = AndroidEarlyAccess::find($id);
        if ($row === null || $row['status'] !== 'pending') {
            throw new DomainException(t('Esta solicitud ya no está pendiente.'));
        }
        $settings = AppSetting::all();
        $url = trim((string) ($settings['android_tester_url'] ?? ''));
        if ($url === '' || !preg_match('#^https://#i', $url)) {
            throw new DomainException(t('Configura primero la URL de testers (debe empezar por https://) en esta misma página.'));
        }
        $instructions = trim((string) ($settings['android_tester_instructions'] ?? ''));
        if ($instructions === '') {
            $instructions = self::defaultInstructions();
        }

        $note = $note !== null && $note !== '' ? mb_substr($note, 0, 500) : null;
        AndroidEarlyAccess::decide($id, 'accepted', (int) $admin['id'], $note);
        AccountMail::androidEarlyAccess(
            (string) $row['email'],
            (string) $row['full_name'],
            $url,
            $instructions
        );
        AuditLog::record((int) $admin['id'], 'early_access.accept', 'android_early_access', $id, [
            'email' => $row['email'],
            'name'  => $row['full_name'],
        ]);

        return ['full_name' => (string) $row['full_name'], 'email' => (string) $row['email']];
    }

    /** @param array{id:int|string} $admin */
    public static function reject(array $admin, int $id, ?string $note = null): void
    {
        $row = AndroidEarlyAccess::find($id);
        if ($row === null || $row['status'] !== 'pending') {
            throw new DomainException(t('Esta solicitud ya no está pendiente.'));
        }
        $note = $note !== null && $note !== '' ? mb_substr($note, 0, 500) : null;
        AndroidEarlyAccess::decide($id, 'rejected', (int) $admin['id'], $note);
        AuditLog::record((int) $admin['id'], 'early_access.reject', 'android_early_access', $id, [
            'email' => $row['email'],
            'name'  => $row['full_name'],
        ]);
    }

    /**
     * Reenvía el correo a una solicitud ya aceptada (misma URL e instrucciones actuales).
     *
     * @param array{id:int|string} $admin
     */
    public static function resend(array $admin, int $id): void
    {
        $row = AndroidEarlyAccess::find($id);
        if ($row === null || $row['status'] !== 'accepted') {
            throw new DomainException(t('Solo se puede reenviar el correo de una solicitud aceptada.'));
        }
        $settings = AppSetting::all();
        $url = trim((string) ($settings['android_tester_url'] ?? ''));
        $instructions = trim((string) ($settings['android_tester_instructions'] ?? ''));
        if ($instructions === '') {
            $instructions = self::defaultInstructions();
        }
        if ($url === '' || !preg_match('#^https://#i', $url)) {
            throw new DomainException(t('Configura la URL de testers antes de reenviar.'));
        }
        if (!AccountMail::androidEarlyAccess((string) $row['email'], (string) $row['full_name'], $url, $instructions)) {
            throw new DomainException(t('No se pudo enviar el correo. Revisa la configuración SMTP.'));
        }
        AuditLog::record((int) $admin['id'], 'early_access.resend', 'android_early_access', $id, [
            'email' => $row['email'],
        ]);
    }

    /** @return array{android_tester_url:string,android_tester_instructions:string} */
    public static function settings(): array
    {
        $all = AppSetting::all();
        return [
            'android_tester_url' => (string) ($all['android_tester_url'] ?? ''),
            'android_tester_instructions' => (string) ($all['android_tester_instructions'] ?? ''),
        ];
    }

    /**
     * @param array{id:int|string} $admin
     * @return list<string> claves cambiadas
     */
    public static function saveSettings(array $admin, string $url, string $instructions): array
    {
        $url = trim($url);
        $instructions = trim(preg_replace("/\r\n?/", "\n", $instructions) ?? '');
        if ($url !== '' && !preg_match('#^https://#i', $url)) {
            throw new DomainException(t('La URL de testers debe empezar por https://.'));
        }
        if (mb_strlen($url) > self::URL_MAX) {
            throw new DomainException(t('La URL es demasiado larga.'));
        }
        if (mb_strlen($instructions) > self::INSTRUCTIONS_MAX) {
            throw new DomainException(t('Las instrucciones son demasiado largas.'));
        }
        $before = AppSetting::all();
        $changes = AppSetting::save([
            'android_tester_url' => $url,
            'android_tester_instructions' => $instructions,
        ]);
        if ($changes !== []) {
            $labels = [];
            foreach ($changes as $key => $pair) {
                $labels[] = AppSetting::describeChange($key, $pair);
            }
            AuditLog::record((int) $admin['id'], 'settings.update', 'app_settings', null, [
                'changes' => $labels,
                'keys'    => array_keys($changes),
                'from'    => [
                    'android_tester_url' => $before['android_tester_url'] ?? '',
                ],
            ]);
        }
        return array_keys($changes);
    }

    public static function defaultInstructions(): string
    {
        return (string) Config::get(
            'app.early_access.default_instructions',
            "1. Abre el enlace del botón (debe ser con la misma cuenta de Google que usaste al pedirnos el acceso).\n"
            . "2. Acepta la invitación de prueba de TREVIX en Google Play.\n"
            . "3. Espera unos minutos y abre Play Store → busca TREVIX (o vuelve a abrir el enlace) e instala la app.\n"
            . "4. Si no ves la versión de prueba, cierra Play Store del todo y vuelve a intentarlo."
        );
    }
}
