<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Solicitudes de acceso anticipado a la app de Android (nombre + correo).
 * El administrador añade el correo a la lista de verificadores de Play y, al aceptar, se envía el correo con el enlace.
 */
final class AndroidEarlyAccess extends Model
{
    public const STATUSES = [
        'pending'  => 'Pendiente',
        'accepted' => 'Aceptada',
        'rejected' => 'Rechazada',
    ];

    private const COLUMNS = 'ea.id, ea.full_name, ea.email, ea.status, ea.reviewed_by, ea.reviewed_at,
                    ea.resolution_note, ea.created_at, rv.username AS reviewer_username';

    public static function find(int $id): ?array
    {
        return self::fetchOne(
            'SELECT ' . self::COLUMNS . ' FROM android_early_access ea
             LEFT JOIN users rv ON rv.id = ea.reviewed_by
             WHERE ea.id = ? LIMIT 1',
            [$id]
        );
    }

    public static function findByEmail(string $email): ?array
    {
        return self::fetchOne(
            'SELECT id, full_name, email, status, created_at FROM android_early_access WHERE email = ? LIMIT 1',
            [$email]
        );
    }

    public static function create(string $fullName, string $email, ?string $ipBinary): int
    {
        self::execute(
            'INSERT INTO android_early_access (full_name, email, ip) VALUES (?, ?, ?)',
            [$fullName, $email, $ipBinary]
        );
        return (int) self::db()->lastInsertId();
    }

    /** Reactiva una solicitud rechazada (mismo correo) como pendiente. */
    public static function reopen(int $id, string $fullName, ?string $ipBinary): void
    {
        self::execute(
            'UPDATE android_early_access
             SET full_name = ?, status = \'pending\', reviewed_by = NULL, reviewed_at = NULL,
                 resolution_note = NULL, ip = ?, created_at = CURRENT_TIMESTAMP
             WHERE id = ?',
            [$fullName, $ipBinary, $id]
        );
    }

    public static function decide(int $id, string $status, int $adminId, ?string $note): void
    {
        self::execute(
            'UPDATE android_early_access
             SET status = ?, reviewed_by = ?, reviewed_at = NOW(), resolution_note = ?
             WHERE id = ? AND status = \'pending\'',
            [$status, $adminId, $note, $id]
        );
    }

    public static function pendingCount(): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM android_early_access WHERE status = 'pending'");
    }

    /** @return array<string, int> */
    public static function counts(): array
    {
        $counts = array_fill_keys(array_keys(self::STATUSES), 0);
        foreach (self::fetchAll('SELECT status, COUNT(*) AS n FROM android_early_access GROUP BY status') as $row) {
            $counts[$row['status']] = (int) $row['n'];
        }
        return $counts;
    }

    /**
     * @return array{requests: list<array>, hasMore: bool}
     */
    public static function adminList(string $status, int $page, int $limit): array
    {
        $status = isset(self::STATUSES[$status]) ? $status : 'pending';
        $limit = max(1, min(60, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ' FROM android_early_access ea
             LEFT JOIN users rv ON rv.id = ea.reviewed_by
             WHERE ea.status = ?
             ORDER BY ea.id ' . ($status === 'pending' ? 'ASC' : 'DESC') . '
             LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            [$status]
        );
        $hasMore = count($rows) > $limit;
        if ($hasMore) {
            array_pop($rows);
        }
        return ['requests' => $rows, 'hasMore' => $hasMore];
    }
}
