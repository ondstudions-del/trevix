<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Reportes de contenido y cuentas. Cada persona reporta un objetivo una sola vez (si su reporte ya se
 * cerró, puede volver a abrirlo). El panel los agrupa por objetivo: una decisión cierra todos los
 * reportes abiertos de ese objetivo.
 */
final class Report extends Model
{
    public const TYPES = [
        'post'      => 'Publicación',
        'comment'   => 'Comentario',
        'user'      => 'Cuenta',
        'community' => 'Comunidad',
        'message'   => 'Mensaje',
        'story'     => 'Historia',
    ];

    public const REASONS = [
        'spam'           => 'Spam o publicidad engañosa',
        'harassment'     => 'Acoso o intimidación',
        'hate'           => 'Discurso de odio',
        'violence'       => 'Violencia o amenazas',
        'nudity'         => 'Desnudos o contenido sexual',
        'misinformation' => 'Información falsa',
        'impersonation'  => 'Suplantación de identidad',
        'self_harm'      => 'Autolesiones o suicidio',
        'other'          => 'Otro motivo',
    ];

    /** Estados que muestra cada pestaña del panel. */
    public const STATUS_GROUPS = [
        'open'      => ['open', 'reviewing'],
        'resolved'  => ['resolved'],
        'dismissed' => ['dismissed'],
    ];

    /** @return 'created'|'reopened'|'exists' */
    public static function create(int $reporterId, string $type, int $targetId, string $reason, ?string $details): string
    {
        return Database::transaction(static function () use ($reporterId, $type, $targetId, $reason, $details): string {
            $existing = self::fetchOne(
                'SELECT id, status FROM reports WHERE reporter_id = ? AND target_type = ? AND target_id = ? LIMIT 1 FOR UPDATE',
                [$reporterId, $type, $targetId]
            );
            if ($existing === null) {
                self::execute(
                    'INSERT INTO reports (reporter_id, target_type, target_id, reason, details) VALUES (?, ?, ?, ?, ?)',
                    [$reporterId, $type, $targetId, $reason, $details]
                );
                return 'created';
            }
            if (in_array($existing['status'], ['open', 'reviewing'], true)) {
                return 'exists';
            }
            self::execute(
                "UPDATE reports SET reason = ?, details = ?, status = 'open', reviewed_by = NULL, reviewed_at = NULL,
                        resolution_note = NULL, created_at = NOW()
                 WHERE id = ?",
                [$reason, $details, (int) $existing['id']]
            );
            return 'reopened';
        });
    }

    public static function openCount(): int
    {
        return (int) self::fetchValue("SELECT COUNT(DISTINCT target_type, target_id) FROM reports WHERE status IN ('open', 'reviewing')");
    }

    /** Objetivos con reportes abiertos por tipo (para las pestañas). */
    public static function openCountsByType(): array
    {
        $counts = array_fill_keys(array_keys(self::TYPES), 0);
        foreach (self::fetchAll(
            "SELECT target_type, COUNT(DISTINCT target_id) AS n FROM reports WHERE status IN ('open', 'reviewing') GROUP BY target_type"
        ) as $row) {
            $counts[$row['target_type']] = (int) $row['n'];
        }
        return $counts;
    }

    /**
     * Objetivos reportados agrupados, del reporte más reciente al más antiguo, con su vista previa.
     * @return array{targets: list<array>, hasMore: bool}
     */
    public static function targets(string $group, ?string $type, int $page, int $limit): array
    {
        $statuses = self::STATUS_GROUPS[$group] ?? self::STATUS_GROUPS['open'];
        $where = 'r.status IN (' . implode(', ', array_fill(0, count($statuses), '?')) . ')';
        $params = $statuses;
        if ($type !== null) {
            $where .= ' AND r.target_type = ?';
            $params[] = $type;
        }
        $limit = max(1, min(60, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            "SELECT r.target_type, r.target_id, COUNT(*) AS reports_count, MAX(r.created_at) AS last_reported_at,
                    GROUP_CONCAT(DISTINCT r.reason ORDER BY r.reason) AS reasons, MAX(r.status = 'reviewing') AS reviewing,
                    MAX(r.reviewed_at) AS reviewed_at
             FROM reports r
             WHERE $where
             GROUP BY r.target_type, r.target_id
             ORDER BY last_reported_at DESC, r.target_id DESC
             LIMIT " . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        $targets = array_map(static function (array $r): array {
            return [
                'type'             => $r['target_type'],
                'id'               => (int) $r['target_id'],
                'reports_count'    => (int) $r['reports_count'],
                'last_reported_at' => $r['last_reported_at'],
                'reviewed_at'      => $r['reviewed_at'],
                'reviewing'        => (bool) $r['reviewing'],
                'reasons'          => array_values(array_filter(explode(',', (string) $r['reasons']))),
                'preview'          => self::preview($r['target_type'], (int) $r['target_id']),
            ];
        }, array_slice($rows, 0, $limit));
        return ['targets' => $targets, 'hasMore' => count($rows) > $limit];
    }

    /** Todos los reportes de un objetivo, con quién reportó y quién los revisó. */
    public static function forTarget(string $type, int $targetId): array
    {
        return self::fetchAll(
            'SELECT r.id, r.reason, r.details, r.status, r.created_at, r.reviewed_at, r.resolution_note,
                    u.id AS reporter_id, u.username AS reporter_username, u.display_name AS reporter_name, u.avatar_path AS reporter_avatar,
                    rv.username AS reviewer_username
             FROM reports r
             LEFT JOIN users u ON u.id = r.reporter_id
             LEFT JOIN users rv ON rv.id = r.reviewed_by
             WHERE r.target_type = ? AND r.target_id = ?
             ORDER BY r.created_at DESC, r.id DESC',
            [$type, $targetId]
        );
    }

    /** Reportes abiertos dirigidos a una cuenta o a su contenido (para la ficha del usuario). */
    public static function openAgainstUser(int $userId): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM reports r
             LEFT JOIN posts p ON r.target_type = 'post' AND p.id = r.target_id
             LEFT JOIN comments c ON r.target_type = 'comment' AND c.id = r.target_id
             LEFT JOIN messages m ON r.target_type = 'message' AND m.id = r.target_id
             LEFT JOIN stories s ON r.target_type = 'story' AND s.id = r.target_id
             WHERE r.status IN ('open', 'reviewing')
               AND ((r.target_type = 'user' AND r.target_id = ?) OR p.user_id = ? OR c.user_id = ? OR m.sender_id = ? OR s.user_id = ?)",
            [$userId, $userId, $userId, $userId, $userId]
        );
    }

    /** Marca como "en revisión" los reportes abiertos de un objetivo. */
    public static function markReviewing(string $type, int $targetId, int $reviewerId): int
    {
        return self::execute(
            "UPDATE reports SET status = 'reviewing', reviewed_by = ?, reviewed_at = NOW()
             WHERE target_type = ? AND target_id = ? AND status = 'open'",
            [$reviewerId, $type, $targetId]
        );
    }

    /** Cierra (resueltos o descartados) los reportes pendientes de un objetivo. Devuelve cuántos cerró. */
    public static function close(string $type, int $targetId, string $status, int $reviewerId, ?string $note): int
    {
        return self::execute(
            "UPDATE reports SET status = ?, reviewed_by = ?, reviewed_at = NOW(), resolution_note = ?
             WHERE target_type = ? AND target_id = ? AND status IN ('open', 'reviewing')",
            [$status === 'dismissed' ? 'dismissed' : 'resolved', $reviewerId, $note, $type, $targetId]
        );
    }

    // -------------------------------------------------------------------------
    // Vista previa del objetivo
    // -------------------------------------------------------------------------

    /**
     * Datos del objetivo para el panel, aunque esté oculto o suspendido. null si ya no existe.
     * Claves: title, excerpt, status, author (usuario), url (enlace público o null), media (ruta o null),
     * owner_id (autor o responsable), y los campos propios de cada tipo.
     */
    public static function preview(string $type, int $id): ?array
    {
        return match ($type) {
            'post'      => self::previewPost($id),
            'comment'   => self::previewComment($id),
            'user'      => self::previewUser($id),
            'community' => self::previewCommunity($id),
            'message'   => self::previewMessage($id),
            'story'     => self::previewStory($id),
            default     => null,
        };
    }

    private const AUTHOR = 'u.id AS author_id, u.username AS author_username, u.display_name AS author_name,
        u.avatar_path AS author_avatar, u.role AS author_role, u.status AS author_status';

    private static function author(array $r): array
    {
        return [
            'id'           => (int) $r['author_id'],
            'username'     => $r['author_username'],
            'display_name' => $r['author_name'],
            'avatar_path'  => $r['author_avatar'],
            'role'         => $r['author_role'],
            'status'       => $r['author_status'],
        ];
    }

    private static function previewPost(int $id): ?array
    {
        $r = self::fetchOne(
            'SELECT p.id, p.user_id, p.community_id, p.shared_post_id, p.body, p.status, p.visibility, p.created_at,
                    c.name AS community_name, c.slug AS community_slug, ' . self::AUTHOR . ',
                    (SELECT pm.path FROM post_media pm WHERE pm.post_id = p.id AND pm.type = \'image\' ORDER BY pm.position LIMIT 1) AS image,
                    (SELECT COUNT(*) FROM post_media pm WHERE pm.post_id = p.id) AS media_count
             FROM posts p JOIN users u ON u.id = p.user_id LEFT JOIN communities c ON c.id = p.community_id
             WHERE p.id = ? LIMIT 1',
            [$id]
        );
        if ($r === null) {
            return null;
        }
        return [
            'title'        => 'Publicación de @' . $r['author_username'],
            'excerpt'      => (string) ($r['body'] ?? ''),
            'status'       => $r['status'],
            'author'       => self::author($r),
            'owner_id'     => (int) $r['user_id'],
            'url'          => $r['status'] === 'published' ? url('post.php', ['id' => $id]) : null,
            'media'        => $r['image'],
            'media_count'  => (int) $r['media_count'],
            'community'    => $r['community_name'] !== null ? ['name' => $r['community_name'], 'slug' => $r['community_slug']] : null,
            'created_at'   => $r['created_at'],
            'row'          => [
                'id' => (int) $r['id'], 'user_id' => (int) $r['user_id'], 'community_id' => $r['community_id'],
                'shared_post_id' => $r['shared_post_id'], 'status' => $r['status'],
            ],
        ];
    }

    private static function previewComment(int $id): ?array
    {
        $r = self::fetchOne(
            'SELECT c.id, c.post_id, c.parent_id, c.user_id, c.body, c.gif_url, c.status, c.created_at, ' . self::AUTHOR . '
             FROM comments c JOIN users u ON u.id = c.user_id WHERE c.id = ? LIMIT 1',
            [$id]
        );
        if ($r === null) {
            return null;
        }
        return [
            'title'      => 'Comentario de @' . $r['author_username'],
            'excerpt'    => (string) $r['body'],
            'status'     => $r['status'],
            'author'     => self::author($r),
            'owner_id'   => (int) $r['user_id'],
            'url'        => url('post.php', ['id' => (int) $r['post_id']]) . '#comentario-' . $id,
            'media'      => $r['gif_url'],
            'created_at' => $r['created_at'],
            'row'        => [
                'id' => (int) $r['id'], 'post_id' => (int) $r['post_id'],
                'parent_id' => $r['parent_id'] !== null ? (int) $r['parent_id'] : null, 'user_id' => (int) $r['user_id'],
            ],
        ];
    }

    private static function previewUser(int $id): ?array
    {
        $r = self::fetchOne(
            "SELECT u.id, u.bio, u.created_at, u.suspended_until, u.suspension_reason, u.is_verified, " . self::AUTHOR . "
             FROM users u WHERE u.id = ? AND u.status <> 'deleted' LIMIT 1",
            [$id]
        );
        if ($r === null) {
            return null;
        }
        return [
            'title'      => '@' . $r['author_username'],
            'excerpt'    => (string) ($r['bio'] ?? ''),
            'status'     => $r['author_status'],
            'author'     => self::author($r),
            'owner_id'   => (int) $r['id'],
            'url'        => $r['author_status'] === 'active' ? url('profile.php', ['u' => $r['author_username']]) : null,
            'media'      => null,
            'created_at' => $r['created_at'],
            'suspended_until'   => $r['suspended_until'],
            'suspension_reason' => $r['suspension_reason'],
        ];
    }

    private static function previewCommunity(int $id): ?array
    {
        $r = self::fetchOne(
            "SELECT c.id, c.slug, c.name, c.description, c.avatar_path, c.cover_path, c.visibility, c.status, c.members_count,
                    c.posts_count, c.created_at, " . self::AUTHOR . "
             FROM communities c JOIN users u ON u.id = c.owner_id WHERE c.id = ? AND c.status <> 'deleted' LIMIT 1",
            [$id]
        );
        if ($r === null) {
            return null;
        }
        return [
            'title'      => $r['name'],
            'excerpt'    => (string) ($r['description'] ?? ''),
            'status'     => $r['status'],
            'author'     => self::author($r),
            'owner_id'   => (int) $r['author_id'],
            'url'        => $r['status'] === 'active' ? url('community.php', ['c' => $r['slug']]) : null,
            'media'      => $r['cover_path'],
            'created_at' => $r['created_at'],
            'row'        => [
                'id' => (int) $r['id'], 'slug' => $r['slug'], 'name' => $r['name'], 'owner_id' => (int) $r['author_id'],
                'avatar_path' => $r['avatar_path'], 'cover_path' => $r['cover_path'], 'status' => $r['status'],
                'visibility' => $r['visibility'], 'members_count' => (int) $r['members_count'], 'posts_count' => (int) $r['posts_count'],
            ],
        ];
    }

    /** Las historias caducadas se borran solas: entonces la vista previa es null. */
    private static function previewStory(int $id): ?array
    {
        $r = self::fetchOne(
            'SELECT s.id, s.user_id, s.media_type, s.media_path, s.body, s.expires_at, s.created_at, ' . self::AUTHOR . '
             FROM stories s JOIN users u ON u.id = s.user_id WHERE s.id = ? LIMIT 1',
            [$id]
        );
        if ($r === null) {
            return null;
        }
        $active = strtotime((string) $r['expires_at']) > time();
        return [
            'title'      => 'Historia de @' . $r['author_username'],
            'excerpt'    => (string) ($r['body'] ?? ''),
            'status'     => $active ? 'published' : 'removed',
            'author'     => self::author($r),
            'owner_id'   => (int) $r['user_id'],
            'url'        => $active ? url('stories.php', ['u' => $r['author_username']]) : null,
            'media'      => $r['media_type'] === 'image' ? $r['media_path'] : null,
            'video'      => $r['media_type'] === 'video' ? $r['media_path'] : null,
            'created_at' => $r['created_at'],
            'row'        => ['id' => (int) $r['id'], 'user_id' => (int) $r['user_id'], 'media_path' => $r['media_path']],
        ];
    }

    private static function previewMessage(int $id): ?array
    {
        $r = self::fetchOne(
            'SELECT m.id, m.conversation_id, m.sender_id, m.body, m.e2ee_epoch, m.media_path, m.media_mime, m.gif_url, m.deleted_at,
                    m.created_at, ' . self::AUTHOR . '
             FROM messages m JOIN users u ON u.id = m.sender_id WHERE m.id = ? LIMIT 1',
            [$id]
        );
        if ($r === null) {
            return null;
        }
        $deleted = $r['deleted_at'] !== null;
        $encrypted = $r['e2ee_epoch'] !== null;
        if (\Trevix\Services\MediaUpload::isProtected($r['media_path'])) {
            $r['media_path'] = null;
        }
        $voice = !$deleted && $r['media_path'] !== null && str_starts_with((string) $r['media_mime'], 'audio/');
        return [
            'title'      => 'Mensaje privado de @' . $r['author_username'],
            // TREVIX no puede leer los mensajes cifrados: el texto que cuenta es el que copió quien reporta en los detalles.
            'excerpt'    => $deleted ? '' : ($encrypted ? 'Mensaje cifrado de extremo a extremo (el contenido está en los detalles del reporte).' : (string) ($r['body'] ?? '')),
            'status'     => $deleted ? 'removed' : 'published',
            'author'     => self::author($r),
            'owner_id'   => (int) $r['sender_id'],
            'url'        => null,
            'media'      => $deleted || $voice ? null : ($r['media_path'] ?? $r['gif_url']),
            'audio'      => $voice ? $r['media_path'] : null,
            'created_at' => $r['created_at'],
        ];
    }
}
