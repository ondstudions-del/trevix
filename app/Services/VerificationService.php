<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\AuditLog;
use Trevix\Models\Notification;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Models\VerificationRequest;
use Trevix\Models\Warning;

/**
 * Verificado: requisitos (seguidores, promedio de «Me gusta» en las últimas publicaciones y sin advertencias
 * recientes), solicitud desde la app y decisión de un administrador. Los requisitos se comprueban siempre en el
 * servidor al pedirlo; la app solo los muestra.
 */
final class VerificationService
{
    public static function rules(): array
    {
        $c = (array) Config::get('app.verification', []);
        return [
            'min_followers' => (int) ($c['min_followers'] ?? 1000),
            'min_avg_likes' => (int) ($c['min_avg_likes'] ?? 100),
            'min_posts'     => (int) ($c['min_posts'] ?? 5),
            'recent_posts'  => (int) ($c['recent_posts'] ?? 10),
            'warning_days'  => (int) ($c['warning_days'] ?? 30),
            'reapply_days'  => (int) ($c['reapply_days'] ?? 30),
        ];
    }

    /**
     * Requisitos y si la cuenta los cumple ahora mismo.
     *
     * @return array{eligible: bool, checks: list<array>, stats: array}
     */
    public static function eligibility(array $user): array
    {
        $rules = self::rules();
        $id = (int) $user['id'];
        $followers = (int) $user['followers_count'];
        $likes = VerificationRequest::likeStats($id, $rules['recent_posts']);
        $lastWarning = Warning::latestActiveSince($id, $rules['warning_days']);
        $enoughPosts = $likes['posts'] >= $rules['min_posts'];

        $checks = [
            [
                'key'      => 'followers',
                'label'    => number_format($rules['min_followers'], 0, ',', '.') . ' seguidores o más',
                'ok'       => $followers >= $rules['min_followers'],
                'current'  => $followers,
                'required' => $rules['min_followers'],
                'detail'   => 'Tienes ' . number_format($followers, 0, ',', '.') . ($followers === 1 ? ' seguidor.' : ' seguidores.'),
            ],
            [
                'key'      => 'likes',
                'label'    => 'Promedio de ' . $rules['min_avg_likes'] . ' «Me gusta» en tus últimas publicaciones (mínimo ' . $rules['min_posts'] . ')',
                'ok'       => $enoughPosts && $likes['avg_likes'] >= $rules['min_avg_likes'],
                'current'  => $likes['avg_likes'],
                'required' => $rules['min_avg_likes'],
                'detail'   => $enoughPosts
                    ? 'Promedio de ' . number_format($likes['avg_likes'], 0, ',', '.') . ' en tus últimas ' . $likes['posts'] . ' publicaciones.'
                    : 'Necesitas al menos ' . $rules['min_posts'] . ' publicaciones propias (tienes ' . $likes['posts'] . ').',
            ],
            [
                'key'      => 'warnings',
                'label'    => 'Sin advertencias en los últimos ' . $rules['warning_days'] . ' días',
                'ok'       => $lastWarning === null,
                'current'  => Warning::activeCountSince($id, $rules['warning_days']),
                'required' => 0,
                'detail'   => $lastWarning === null
                    ? 'No tienes advertencias recientes.'
                    : 'Recibiste una advertencia el ' . full_date($lastWarning, false) . '. Podrás pedirlo desde el '
                        . full_date(date('Y-m-d H:i:s', strtotime($lastWarning) + $rules['warning_days'] * 86400), false) . '.',
            ],
        ];
        return [
            'eligible' => !in_array(false, array_column($checks, 'ok'), true),
            'checks'   => $checks,
            'stats'    => ['followers' => $followers, 'avg_likes' => $likes['avg_likes'], 'posts' => $likes['posts']],
        ];
    }

    /** Estado completo para la pantalla de la app: insignia, requisitos, última solicitud y si puede pedirlo. */
    public static function status(array $user): array
    {
        $verified = (bool) $user['is_verified'];
        $eligibility = self::eligibility($user);
        $latest = VerificationRequest::latestFor((int) $user['id']);
        $blocked = self::blockedReason($user, $latest, $eligibility);
        return [
            'verified'    => $verified,
            'eligible'    => $eligibility['eligible'],
            'checks'      => $eligibility['checks'],
            'request'     => $latest !== null ? self::presentRequest($latest) : null,
            'can_apply'   => $blocked === null,
            'blocked_reason' => $blocked,
            'categories'  => array_map(static fn ($k, $v) => ['key' => $k, 'label' => $v], array_keys(VerificationRequest::CATEGORIES), VerificationRequest::CATEGORIES),
        ];
    }

    /** Envía la solicitud. $input: category, full_name, note. */
    public static function apply(array $user, array $input): array
    {
        $id = (int) $user['id'];
        $eligibility = self::eligibility($user);
        $blocked = self::blockedReason($user, VerificationRequest::latestFor($id), $eligibility);
        if ($blocked !== null) {
            throw new ActionError($blocked, 422, ['form' => $blocked]);
        }

        $category = (string) ($input['category'] ?? '');
        $fullName = Guard::singleLine((string) ($input['full_name'] ?? ''), 200) ?? '';
        $note = Guard::cleanText(trim((string) ($input['note'] ?? '')));
        $errors = [];
        if (!isset(VerificationRequest::CATEGORIES[$category])) {
            $errors['category'] = 'Elige la categoría que mejor te describe.';
        }
        if (mb_strlen($fullName) < 2 || mb_strlen($fullName) > 80) {
            $errors['full_name'] = 'Escribe tu nombre real o el de tu marca (2 a 80 caracteres).';
        } elseif (preg_match('/[<>\p{C}]/u', $fullName)) {
            $errors['full_name'] = 'El nombre tiene caracteres no permitidos.';
        }
        if (mb_strlen($note) > 500) {
            $errors['note'] = 'Cuéntanos en 500 caracteres como máximo.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        Guard::rateLimit('verification_request', (string) $id, 'Enviaste demasiadas solicitudes. Inténtalo en {min} min.');
        RateLimit::hit('verification_request', (string) $id);
        $stats = $eligibility['stats'];
        VerificationRequest::create($id, $category, $fullName, $note !== '' ? $note : null, $stats['followers'], $stats['avg_likes'], min(255, $stats['posts']));
        return self::status($user);
    }

    public static function cancel(array $user): array
    {
        if (!VerificationRequest::cancel((int) $user['id'])) {
            throw new ActionError('No tienes una solicitud en revisión.', 404);
        }
        return self::status($user);
    }

    /** Aprueba la solicitud: pone la insignia y avisa a la persona (solo administradores). */
    public static function approve(array $actor, int $requestId, ?string $note): array
    {
        [$request, $target] = self::pendingRequest($actor, $requestId);
        if (!VerificationRequest::decide($requestId, 'approved', (int) $actor['id'], $note)) {
            throw new DomainException('Esta solicitud ya no está en revisión.');
        }
        if (!(bool) $target['is_verified']) {
            User::setVerified((int) $target['id'], true);
        }
        Notification::notifySystem((int) $target['id'], 'verification_approved', $requestId);
        AuditLog::record((int) $actor['id'], 'verification.approve', 'user', (int) $target['id'], array_filter([
            'username' => $target['username'], 'request' => $requestId, 'note' => $note,
        ]));
        return $request;
    }

    /** Rechaza la solicitud con un motivo que verá la persona (solo administradores). */
    public static function reject(array $actor, int $requestId, string $reason): array
    {
        [$request, $target] = self::pendingRequest($actor, $requestId);
        if (mb_strlen(trim($reason)) < 5) {
            throw new DomainException('Escribe el motivo (al menos 5 caracteres).');
        }
        if (!VerificationRequest::decide($requestId, 'rejected', (int) $actor['id'], $reason)) {
            throw new DomainException('Esta solicitud ya no está en revisión.');
        }
        Notification::notifySystem((int) $target['id'], 'verification_rejected', $requestId);
        AuditLog::record((int) $actor['id'], 'verification.reject', 'user', (int) $target['id'], [
            'username' => $target['username'], 'request' => $requestId, 'note' => $reason,
        ]);
        return $request;
    }

    public static function presentRequest(array $r): array
    {
        return [
            'id'             => (int) $r['id'],
            'category'       => $r['category'],
            'category_label' => VerificationRequest::CATEGORIES[$r['category']] ?? $r['category'],
            'full_name'      => $r['full_name'],
            'note'           => $r['note'],
            'status'         => $r['status'],
            'status_label'   => VerificationRequest::STATUSES[$r['status']] ?? $r['status'],
            'decision_note'  => $r['decision_note'],
            'created_at'     => $r['created_at'],
            'reviewed_at'    => $r['reviewed_at'],
        ];
    }

    /** Por qué no puede pedirlo ahora (null si puede). */
    private static function blockedReason(array $user, ?array $latest, array $eligibility): ?string
    {
        if ((bool) $user['is_verified']) {
            return 'Tu cuenta ya está verificada.';
        }
        if ($latest !== null && $latest['status'] === 'pending') {
            return 'Tu solicitud está en revisión. Te avisaremos cuando el equipo la revise.';
        }
        $days = self::rules()['reapply_days'];
        if ($latest !== null && $latest['status'] === 'rejected' && $latest['reviewed_at'] !== null
            && strtotime((string) $latest['reviewed_at']) > time() - $days * 86400) {
            return 'Podrás volver a pedirlo desde el ' . full_date(date('Y-m-d H:i:s', strtotime((string) $latest['reviewed_at']) + $days * 86400), false) . '.';
        }
        if (!$eligibility['eligible']) {
            return 'Aún no cumples todos los requisitos.';
        }
        return null;
    }

    /** @return array{0: array, 1: array} la solicitud pendiente y la cuenta (activa) que la pidió */
    private static function pendingRequest(array $actor, int $requestId): array
    {
        if (!Moderation::isAdmin($actor)) {
            throw new DomainException('Esta acción es exclusiva de los administradores.');
        }
        $request = VerificationRequest::find($requestId);
        if ($request === null) {
            throw new ActionError('Esta solicitud no existe.', 404);
        }
        if ($request['status'] !== 'pending') {
            throw new DomainException('Esta solicitud ya no está en revisión.');
        }
        $target = User::findForAdmin((int) $request['user_id']);
        if ($target === null || $target['status'] !== 'active') {
            throw new DomainException('La cuenta que pidió el verificado ya no está activa.');
        }
        return [$request, $target];
    }
}
