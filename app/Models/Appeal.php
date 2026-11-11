<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Apelaciones de una suspensión (o baneo) o de una advertencia. Cada sanción admite una apelación pendiente a la vez;
 * el equipo la acepta (se levanta la sanción) o la rechaza con un motivo que ve la persona.
 */
final class Appeal extends Model
{
    public const TYPES = ['suspension' => 'Suspensión', 'warning' => 'Advertencia'];

    public const STATUSES = ['pending' => 'Pendiente', 'accepted' => 'Aceptada', 'rejected' => 'Rechazada'];

    private const COLUMNS = 'ap.id, ap.user_id, ap.type, ap.warning_id, ap.sanction_reason, ap.message, ap.status,
                    ap.reviewed_at, ap.resolution_note, ap.created_at, rv.username AS reviewer_username,
                    uw.reason AS warning_reason, uw.revoked_at AS warning_revoked_at';

    private const JOINS = 'LEFT JOIN users rv ON rv.id = ap.reviewed_by
             LEFT JOIN user_warnings uw ON uw.id = ap.warning_id';

    public static function create(int $userId, string $type, ?int $warningId, ?string $sanctionReason, string $message): int
    {
        self::execute(
            'INSERT INTO appeals (user_id, type, warning_id, sanction_reason, message) VALUES (?, ?, ?, ?, ?)',
            [$userId, $type, $warningId, $sanctionReason !== null ? mb_substr($sanctionReason, 0, 255) : null, $message]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT ' . self::COLUMNS . ' FROM appeals ap ' . self::JOINS . ' WHERE ap.id = ? LIMIT 1', [$id]);
    }

    /** La apelación más reciente de una cuenta para una sanción (una suspensión o una advertencia concreta). */
    public static function latestFor(int $userId, string $type, ?int $warningId): ?array
    {
        return self::fetchOne(
            'SELECT id, status, reviewed_at, created_at FROM appeals WHERE user_id = ? AND type = ? AND warning_id <=> ?
             ORDER BY id DESC LIMIT 1',
            [$userId, $type, $warningId]
        );
    }

    /** Apelaciones de una cuenta, la más reciente primero. */
    public static function forUser(int $userId, int $limit = 30): array
    {
        return self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM appeals ap ' . self::JOINS . '
             WHERE ap.user_id = ? ORDER BY ap.id DESC LIMIT ' . max(1, min(100, $limit)),
            [$userId]
        );
    }

    /** Cuántas apelaciones hizo una cuenta por estado. */
    public static function countsFor(int $userId): array
    {
        $counts = array_fill_keys(array_keys(self::STATUSES), 0);
        foreach (self::fetchAll('SELECT status, COUNT(*) AS n FROM appeals WHERE user_id = ? GROUP BY status', [$userId]) as $row) {
            $counts[$row['status']] = (int) $row['n'];
        }
        return $counts;
    }

    public static function pendingCount(): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM appeals WHERE status = 'pending'");
    }

    /** Totales por estado para las pestañas del panel. */
    public static function counts(): array
    {
        $counts = array_fill_keys(array_keys(self::STATUSES), 0);
        foreach (self::fetchAll('SELECT status, COUNT(*) AS n FROM appeals GROUP BY status') as $row) {
            $counts[$row['status']] = (int) $row['n'];
        }
        return $counts;
    }

    /**
     * Apelaciones de un estado para el panel, con la cuenta que apela y su estado actual.
     * Las pendientes, de la más antigua a la más reciente (se atienden por orden de llegada).
     * @return array{appeals: list<array>, hasMore: bool}
     */
    public static function adminList(string $status, int $page, int $limit): array
    {
        $status = isset(self::STATUSES[$status]) ? $status : 'pending';
        $limit = max(1, min(60, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ', u.username, u.display_name, u.avatar_path, u.role, u.status AS user_status,
                    u.suspended_until, u.suspension_reason
             FROM appeals ap
             JOIN users u ON u.id = ap.user_id
             ' . self::JOINS . '
             WHERE ap.status = ?
             ORDER BY ap.id ' . ($status === 'pending' ? 'ASC' : 'DESC') . '
             LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            [$status]
        );
        return ['appeals' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Cierra una apelación pendiente. false si ya la había resuelto otra persona. */
    public static function resolve(int $id, string $status, int $reviewerId, ?string $note): bool
    {
        return self::execute(
            "UPDATE appeals SET status = ?, reviewed_by = ?, reviewed_at = NOW(), resolution_note = ? WHERE id = ? AND status = 'pending'",
            [$status, $reviewerId, $note, $id]
        ) > 0;
    }
}
