<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Password;
use Trevix\Core\Request;
use Trevix\Models\Appeal;
use Trevix\Models\AuditLog;
use Trevix\Models\Notification;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Models\Warning;

/**
 * Apelaciones (compartido por la web y la API). Una cuenta suspendida apela con su usuario y contraseña, sin sesión;
 * una advertencia se apela con la sesión iniciada. El equipo la acepta (se levanta la sanción) o la rechaza con motivo,
 * y la persona recibe el aviso en TREVIX y por correo.
 */
final class AppealService
{
    public const MESSAGE_MIN = 20;
    public const MESSAGE_MAX = 1000;
    /** Tras un rechazo, días que hay que esperar para volver a apelar la misma sanción. */
    public const RETRY_DAYS = 7;

    /** @return int id de la apelación */
    public static function appealSuspension(string $identifier, string $password, string $message): int
    {
        $identifier = mb_strtolower(trim($identifier));
        $message = self::cleanMessage($message);
        if ($identifier === '' || $password === '') {
            throw ActionError::field('form', 'Escribe tu correo o usuario y tu contraseña.');
        }

        $ip = Request::ip();
        $accountKey = $ip . '|' . $identifier;
        if (RateLimit::tooManyAttempts('login', $accountKey) || RateLimit::tooManyAttempts('login_ip', $ip)) {
            $wait = max(RateLimit::availableIn('login', $accountKey), RateLimit::availableIn('login_ip', $ip));
            $text = t('Demasiados intentos. Inténtalo de nuevo en {n} min.', ['n' => max(1, (int) ceil($wait / 60))]);
            throw new ActionError($text, 429, ['form' => $text], max(1, $wait));
        }
        $user = mb_strlen($identifier) <= 190 ? User::findForLogin($identifier) : null;
        if (!Password::verify($password, $user['password_hash'] ?? null)) {
            RateLimit::hit('login', $accountKey);
            RateLimit::hit('login_ip', $ip);
            throw new ActionError('El correo, usuario o contraseña no son correctos.', 401, ['form' => 'El correo, usuario o contraseña no son correctos.']);
        }
        RateLimit::clear('login', $accountKey);

        $until = $user['suspended_until'] ? strtotime((string) $user['suspended_until']) : false;
        if ($user['status'] !== 'suspended' || ($until !== false && $until <= time())) {
            throw new ActionError('Tu cuenta no está suspendida: ya puedes iniciar sesión.', 409, ['form' => 'Tu cuenta no está suspendida: ya puedes iniciar sesión.']);
        }
        $id = (int) $user['id'];
        self::guardRepeat($id, 'suspension', null, 'form');
        self::hitLimit($id, 'form');
        return Appeal::create($id, 'suspension', null, $user['suspension_reason'] ?? null, $message);
    }

    /** @return int id de la apelación */
    public static function appealWarning(array $user, int $warningId, string $message): int
    {
        $message = self::cleanMessage($message);
        $id = (int) $user['id'];
        $warning = Warning::find($warningId);
        if ($warning === null || (int) $warning['user_id'] !== $id) {
            throw new ActionError('Esta advertencia no existe.', 404);
        }
        if ($warning['revoked_at'] !== null) {
            throw new ActionError('Esta advertencia ya se retiró: no hace falta apelarla.', 409);
        }
        self::guardRepeat($id, 'warning', $warningId, 'message');
        self::hitLimit($id, 'message');
        return Appeal::create($id, 'warning', $warningId, (string) $warning['reason'], $message);
    }

    /**
     * Acepta o rechaza una apelación pendiente. Aceptar levanta la suspensión o retira la advertencia;
     * rechazar exige un motivo, que ve la persona. Devuelve el mensaje para mostrar.
     *
     * @throws DomainException con un mensaje listo para mostrar
     */
    public static function resolve(array $actor, int $appealId, bool $accept, ?string $note): string
    {
        $appeal = Appeal::find($appealId) ?? throw new DomainException('Esta apelación no existe.');
        if ($appeal['status'] !== 'pending') {
            throw new DomainException('Esta apelación ya se resolvió.');
        }
        $target = User::findForAdmin((int) $appeal['user_id']) ?? throw new DomainException('Esta cuenta ya no existe.');
        if (!Moderation::canActOnUser($actor, $target)) {
            throw new DomainException('No tienes permiso para actuar sobre esta cuenta.');
        }
        if (!$accept && mb_strlen(trim((string) $note)) < 5) {
            throw new DomainException('Escribe el motivo del rechazo (al menos 5 caracteres). La persona lo verá.');
        }
        if (!Appeal::resolve($appealId, $accept ? 'accepted' : 'rejected', (int) $actor['id'], $note)) {
            throw new DomainException('Esta apelación ya se resolvió.');
        }

        if ($accept) {
            if ($appeal['type'] === 'suspension') {
                User::unsuspend((int) $target['id']);
            } elseif ($appeal['warning_id'] !== null) {
                Warning::revoke((int) $appeal['warning_id'], (int) $actor['id']);
            }
        }
        Notification::notifySystem((int) $target['id'], $accept ? 'appeal_accepted' : 'appeal_rejected', $appealId);
        AccountMail::appealDecision((string) $target['email'], (string) $target['display_name'], (string) $appeal['type'], $accept, $note);
        AuditLog::record((int) $actor['id'], $accept ? 'appeal.accept' : 'appeal.reject', 'user', (int) $target['id'], array_filter([
            'username' => $target['username'], 'appeal' => $appealId, 'note' => $note,
        ]));

        if (!$accept) {
            return t('Apelación rechazada. Le avisamos a @{username} con el motivo.', ['username' => $target['username']]);
        }
        return $appeal['type'] === 'suspension'
            ? t('Apelación aceptada: levantamos la suspensión de @{username}.', ['username' => $target['username']])
            : t('Apelación aceptada: retiramos la advertencia de @{username}.', ['username' => $target['username']]);
    }

    private static function cleanMessage(string $message): string
    {
        $message = trim(Guard::cleanText($message));
        $length = mb_strlen($message);
        if ($length < self::MESSAGE_MIN || $length > self::MESSAGE_MAX) {
            throw ActionError::field('message', t('Explica tu apelación en {min} a {max} caracteres.', ['min' => self::MESSAGE_MIN, 'max' => self::MESSAGE_MAX]));
        }
        return $message;
    }

    /** Una apelación pendiente por sanción; tras un rechazo hay que esperar unos días para volver a apelar. */
    private static function guardRepeat(int $userId, string $type, ?int $warningId, string $field): void
    {
        $last = Appeal::latestFor($userId, $type, $warningId);
        if ($last === null) {
            return;
        }
        if ($last['status'] === 'pending') {
            throw new ActionError(
                t('Ya enviaste una apelación el {date}. El equipo la está revisando; te avisaremos por correo.', ['date' => full_date((string) $last['created_at'])]),
                409,
                [$field => t('Ya tienes una apelación en revisión.')]
            );
        }
        $retryAt = $last['status'] === 'rejected' && $last['reviewed_at'] !== null
            ? strtotime((string) $last['reviewed_at']) + self::RETRY_DAYS * 86400
            : 0;
        if ($retryAt > time()) {
            $text = t('Tu apelación anterior se rechazó. Podrás volver a apelar a partir del {date}.', ['date' => full_date(date('Y-m-d H:i:s', $retryAt))]);
            throw new ActionError($text, 429, [$field => $text]);
        }
    }

    private static function hitLimit(int $userId, string $field): void
    {
        if (RateLimit::tooManyAttempts('appeal', (string) $userId)) {
            throw new ActionError('Enviaste varias apelaciones hoy. Inténtalo mañana.', 429, [$field => 'Enviaste varias apelaciones hoy. Inténtalo mañana.']);
        }
        RateLimit::hit('appeal', (string) $userId);
    }
}
