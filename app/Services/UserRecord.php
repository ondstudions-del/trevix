<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Models\Appeal;
use Trevix\Models\AuditLog;
use Trevix\Models\Report;
use Trevix\Models\Warning;

/**
 * Historial de moderación de una cuenta: faltas, reportes recibidos y hechos, y apelaciones.
 * Lo usan la ficha del panel y IX (para entender el contexto de quien escribe a soporte).
 *
 * Faltas = advertencias vigentes + suspensiones y baneos (menos los levantados por una apelación aceptada)
 *          + contenido retirado por moderación.
 */
final class UserRecord
{
    public static function summary(array $user): array
    {
        $id = (int) $user['id'];
        $warnings = Warning::forUser($id, false, 200);
        $activeWarnings = count(array_filter($warnings, static fn (array $w): bool => !$w['revoked']));
        $sanctions = AuditLog::sanctionCounts($id, (string) $user['username']);
        $appeals = Appeal::countsFor($id);
        $overturned = self::acceptedSuspensionAppeals($id);
        $accountSanctions = max(0, $sanctions['suspensions'] + $sanctions['bans'] - $overturned);

        return [
            'strikes'          => $activeWarnings + $accountSanctions + $sanctions['removed_content'],
            'warnings_active'  => $activeWarnings,
            'warnings_revoked' => count($warnings) - $activeWarnings,
            'suspensions'      => $sanctions['suspensions'],
            'bans'             => $sanctions['bans'],
            'overturned'       => $overturned,
            'removed_content'  => $sanctions['removed_content'],
            'reports_received' => Report::countsAgainstUser($id),
            'reports_made'     => Report::countsByReporter($id),
            'appeals'          => $appeals,
        ];
    }

    /** Resumen en texto para el contexto de IX (sin datos de quien reportó ni notas internas). */
    public static function forAssistant(array $user): string
    {
        $s = self::summary($user);
        $status = match ($user['status'] ?? 'active') {
            'suspended' => empty($user['suspended_until']) ? 'baneada (suspensión sin fecha de fin)' : 'suspendida hasta ' . $user['suspended_until'],
            default     => 'activa',
        };
        $lines = [
            'Estado de la cuenta: ' . $status . '.',
            'Faltas registradas: ' . $s['strikes'] . ' (advertencias vigentes: ' . $s['warnings_active']
                . ', suspensiones: ' . $s['suspensions'] . ', baneos: ' . $s['bans']
                . ', levantadas por apelación: ' . $s['overturned'] . ', contenido retirado: ' . $s['removed_content'] . ').',
            'Reportes recibidos: ' . $s['reports_received']['total'] . ' (abiertos: ' . $s['reports_received']['open']
                . ', con medida: ' . $s['reports_received']['resolved'] . ', descartados: ' . $s['reports_received']['dismissed'] . ').',
            'Reportes que hizo: ' . $s['reports_made']['total'] . ' (descartados: ' . $s['reports_made']['dismissed'] . ').',
            'Apelaciones: pendientes ' . $s['appeals']['pending'] . ', aceptadas ' . $s['appeals']['accepted'] . ', rechazadas ' . $s['appeals']['rejected'] . '.',
        ];
        $recent = array_slice(array_filter(Warning::forUser((int) $user['id'], false, 5), static fn (array $w): bool => !$w['revoked']), 0, 3);
        foreach ($recent as $w) {
            $lines[] = 'Advertencia del ' . substr((string) $w['created_at'], 0, 10) . ': ' . mb_strimwidth((string) $w['reason'], 0, 160, '…');
        }
        if (!empty($user['suspension_reason']) && ($user['status'] ?? '') === 'suspended') {
            $lines[] = 'Motivo de la suspensión actual: ' . mb_strimwidth((string) $user['suspension_reason'], 0, 160, '…');
        }
        return implode("\n", $lines);
    }

    private static function acceptedSuspensionAppeals(int $userId): int
    {
        return count(array_filter(
            Appeal::forUser($userId, 100),
            static fn (array $a): bool => $a['type'] === 'suspension' && $a['status'] === 'accepted'
        ));
    }
}
