<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Request;

/** Registro de auditoría: cada acción de moderación o administración queda anotada con quién, qué y desde dónde. */
final class AuditLog extends Model
{
    public const ACTIONS = [
        'post.hide'         => 'Ocultó una publicación',
        'post.restore'      => 'Restauró una publicación',
        'post.delete'       => 'Eliminó una publicación',
        'post.feature'      => 'Destacó una publicación',
        'post.unfeature'    => 'Quitó una publicación de destacadas',
        'comment.delete'    => 'Eliminó un comentario',
        'message.delete'    => 'Eliminó un mensaje',
        'story.delete'      => 'Eliminó una historia',
        'song.approve'      => 'Aprobó una canción',
        'song.reject'       => 'Rechazó una canción',
        'song.remove'       => 'Retiró una canción de la biblioteca',
        'song.restore'      => 'Restauró una canción',
        'user.suspend'      => 'Suspendió una cuenta',
        'user.unsuspend'    => 'Levantó una suspensión',
        'user.role'         => 'Cambió el rol de una cuenta',
        'user.verify'       => 'Verificó una cuenta',
        'user.unverify'     => 'Quitó la verificación',
        'user.warn'         => 'Advirtió a una cuenta',
        'user.warning_revoke' => 'Retiró una advertencia',
        'verification.approve' => 'Aprobó una solicitud de verificado',
        'verification.reject'  => 'Rechazó una solicitud de verificado',
        'community.suspend' => 'Suspendió una comunidad',
        'community.restore' => 'Reactivó una comunidad',
        'community.delete'  => 'Eliminó una comunidad',
        'report.reviewing'  => 'Tomó un reporte',
        'report.dismiss'    => 'Descartó reportes',
        'report.resolve'    => 'Resolvió reportes',
        'settings.update'   => 'Cambió la configuración',
    ];

    public static function record(int $adminId, string $action, ?string $targetType, ?int $targetId, array $details = []): void
    {
        $ip = @inet_pton(Request::ip());
        self::execute(
            'INSERT INTO admin_audit_log (admin_id, action, target_type, target_id, details, ip_address) VALUES (?, ?, ?, ?, ?, ?)',
            [
                $adminId,
                $action,
                $targetType,
                $targetId,
                $details !== [] ? json_encode($details, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
                $ip !== false ? $ip : null,
            ]
        );
    }

    /**
     * Entradas más recientes, filtradas por grupo de acción ("post", "user"…) o por responsable.
     * @return array{entries: list<array>, hasMore: bool}
     */
    public static function latest(?string $group, ?int $adminId, int $page, int $limit): array
    {
        $where = ['1 = 1'];
        $params = [];
        if ($group !== null) {
            $where[] = 'l.action LIKE ?';
            $params[] = self::likeEscape($group) . '.%';
        }
        if ($adminId !== null) {
            $where[] = 'l.admin_id = ?';
            $params[] = $adminId;
        }
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT l.id, l.admin_id, l.action, l.target_type, l.target_id, l.details, l.ip_address, l.created_at,
                    a.username AS admin_username, a.display_name AS admin_name, a.role AS admin_role
             FROM admin_audit_log l
             LEFT JOIN users a ON a.id = l.admin_id
             WHERE ' . implode(' AND ', $where) . '
             ORDER BY l.id DESC LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        $entries = array_map(static function (array $r): array {
            $r['details'] = $r['details'] !== null ? (json_decode((string) $r['details'], true) ?: []) : [];
            $ip = $r['ip_address'] !== null ? @inet_ntop($r['ip_address']) : false;
            $r['ip'] = $ip !== false ? $ip : '';
            unset($r['ip_address']);
            $r['label'] = self::ACTIONS[$r['action']] ?? $r['action'];
            return $r;
        }, array_slice($rows, 0, $limit));
        return ['entries' => $entries, 'hasMore' => count($rows) > $limit];
    }

    /** Historial de acciones sobre un objetivo concreto (ficha de usuario o de reporte). */
    public static function forTarget(string $type, int $id, int $limit = 10): array
    {
        $rows = self::fetchAll(
            'SELECT l.id, l.action, l.details, l.created_at, a.username AS admin_username
             FROM admin_audit_log l LEFT JOIN users a ON a.id = l.admin_id
             WHERE l.target_type = ? AND l.target_id = ?
             ORDER BY l.id DESC LIMIT ' . max(1, min(50, $limit)),
            [$type, $id]
        );
        return array_map(static function (array $r): array {
            $r['details'] = $r['details'] !== null ? (json_decode((string) $r['details'], true) ?: []) : [];
            $r['label'] = self::ACTIONS[$r['action']] ?? $r['action'];
            return $r;
        }, $rows);
    }

    /** Personas del equipo que aparecen en el registro (para el filtro). */
    public static function actors(): array
    {
        return self::fetchAll(
            'SELECT DISTINCT a.id, a.username FROM admin_audit_log l JOIN users a ON a.id = l.admin_id ORDER BY a.username'
        );
    }
}
