<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;
use Trevix\Services\ImageUpload;

/**
 * Comunidades y sus miembros. Las públicas aceptan a cualquiera al instante; en las privadas se pide
 * acceso y lo aprueban el administrador o los moderadores. members_count cuenta solo miembros activos
 * y posts_count las publicaciones dentro de la comunidad: ambos cambian solo cuando la fila cambió.
 */
final class Community extends Model
{
    public const CATEGORIES = [
        'Arte', 'Ciencia', 'Deportes', 'Diseño', 'Educación', 'Entretenimiento', 'Estilo de vida',
        'Fotografía', 'Gaming', 'Música', 'Negocios', 'Tecnología', 'Viajes', 'Otra',
    ];
    public const VISIBILITIES = ['public' => 'Pública', 'private' => 'Privada'];
    public const ROLES = ['owner' => 'Administrador', 'moderator' => 'Moderador', 'member' => 'Miembro'];

    private const COLUMNS = 'c.id, c.owner_id, c.slug, c.name, c.description, c.category, c.avatar_path, c.cover_path,
        c.visibility, c.status, c.members_count, c.posts_count, c.created_at';

    private const NOT_BLOCKED = 'NOT EXISTS (SELECT 1 FROM blocks b
        WHERE (b.blocker_id = ? AND b.blocked_id = c.owner_id) OR (b.blocker_id = c.owner_id AND b.blocked_id = ?))';

    // -------------------------------------------------------------------------
    // Lectura
    // -------------------------------------------------------------------------

    /** Comunidad activa por slug, con los datos de su administrador y la membresía de quien mira. */
    public static function findBySlug(string $slug, int $viewerId): ?array
    {
        if (!preg_match('/^[a-z0-9-]{3,60}$/', $slug)) {
            return null;
        }
        $row = self::fetchOne(
            'SELECT ' . self::COLUMNS . ', o.username AS owner_username, o.display_name AS owner_name,
                    m.role AS viewer_role, m.status AS viewer_status
             FROM communities c
             JOIN users o ON o.id = c.owner_id
             LEFT JOIN community_members m ON m.community_id = c.id AND m.user_id = ?
             WHERE c.slug = ? AND c.status = \'active\' LIMIT 1',
            [$viewerId, $slug]
        );
        return $row !== null ? self::present($row) : null;
    }

    /** Comunidad activa por id con la membresía de quien mira. */
    public static function find(int $id, int $viewerId): ?array
    {
        $row = self::fetchOne(
            'SELECT ' . self::COLUMNS . ', m.role AS viewer_role, m.status AS viewer_status
             FROM communities c
             LEFT JOIN community_members m ON m.community_id = c.id AND m.user_id = ?
             WHERE c.id = ? AND c.status = \'active\' LIMIT 1',
            [$viewerId, $id]
        );
        return $row !== null ? self::present($row) : null;
    }

    /** @return array{role:string,status:string}|null */
    public static function membership(int $communityId, int $userId): ?array
    {
        return self::fetchOne(
            'SELECT role, status FROM community_members WHERE community_id = ? AND user_id = ? LIMIT 1',
            [$communityId, $userId]
        );
    }

    /**
     * Buscar y descubrir comunidades (públicas y privadas; el contenido de las privadas sigue cerrado).
     *
     * @return array{communities: list<array>, hasMore: bool}
     */
    public static function discover(int $viewerId, string $term, ?string $category, int $page, int $limit): array
    {
        $where = "c.status = 'active' AND " . self::NOT_BLOCKED;
        $params = [$viewerId, $viewerId, $viewerId];
        if ($category !== null) {
            $where .= ' AND c.category = ?';
            $params[] = $category;
        }
        $term = trim($term);
        if ($term !== '') {
            $boolean = self::booleanSearch($term);
            if ($boolean !== '') {
                $where .= ' AND MATCH (c.name, c.description) AGAINST (? IN BOOLEAN MODE)';
                $params[] = $boolean;
            } else {
                $like = '%' . self::likeEscape($term) . '%';
                $where .= ' AND (c.name LIKE ? OR c.description LIKE ?)';
                array_push($params, $like, $like);
            }
        }
        return self::page(
            'SELECT ' . self::COLUMNS . ', m.role AS viewer_role, m.status AS viewer_status
             FROM communities c
             LEFT JOIN community_members m ON m.community_id = c.id AND m.user_id = ?
             WHERE ' . $where . '
             ORDER BY c.members_count DESC, c.id DESC',
            $params,
            $page,
            $limit
        );
    }

    /** Comunidades del usuario (miembro o con solicitud pendiente): primero las que administra o modera. */
    public static function mine(int $userId, int $page, int $limit): array
    {
        return self::page(
            'SELECT ' . self::COLUMNS . ', m.role AS viewer_role, m.status AS viewer_status
             FROM communities c
             JOIN community_members m ON m.community_id = c.id AND m.user_id = ?
             WHERE c.status = \'active\' AND m.status IN (\'active\', \'pending\')
             ORDER BY FIELD(m.role, \'owner\', \'moderator\', \'member\'), m.status = \'pending\', c.name',
            [$userId],
            $page,
            $limit
        );
    }

    /** Comunidades públicas populares a las que el usuario aún no pertenece (panel lateral). */
    public static function suggestions(int $viewerId, int $limit = 3): array
    {
        $rows = self::fetchAll(
            'SELECT ' . self::COLUMNS . ', NULL AS viewer_role, NULL AS viewer_status
             FROM communities c
             WHERE c.status = \'active\' AND c.visibility = \'public\'
               AND NOT EXISTS (SELECT 1 FROM community_members m WHERE m.community_id = c.id AND m.user_id = ?)
               AND ' . self::NOT_BLOCKED . '
             ORDER BY c.members_count DESC, c.id DESC
             LIMIT ' . max(1, min(10, $limit)),
            [$viewerId, $viewerId, $viewerId]
        );
        return array_map([self::class, 'present'], $rows);
    }

    /**
     * Miembros de la comunidad con un estado (active | pending | banned). Los activos se ordenan por rol.
     *
     * @return array{users: list<array>, hasMore: bool}
     */
    public static function members(int $communityId, string $status, int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, u.is_private, m.role, m.status, m.joined_at
             FROM community_members m
             JOIN users u ON u.id = m.user_id
             WHERE m.community_id = ? AND m.status = ? AND u.status = \'active\'
             ORDER BY FIELD(m.role, \'owner\', \'moderator\', \'member\'), m.joined_at, u.id
             LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            [$communityId, $status]
        );
        return ['users' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    public static function pendingCount(int $communityId): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM community_members m JOIN users u ON u.id = m.user_id
             WHERE m.community_id = ? AND m.status = 'pending' AND u.status = 'active'",
            [$communityId]
        );
    }

    /** Administrador y moderadores activos (reciben los avisos de solicitudes). */
    public static function managerIds(int $communityId): array
    {
        return array_map('intval', array_column(self::fetchAll(
            "SELECT user_id FROM community_members WHERE community_id = ? AND status = 'active' AND role IN ('owner', 'moderator')",
            [$communityId]
        ), 'user_id'));
    }

    public static function ownedCount(int $userId): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM communities WHERE owner_id = ? AND status <> 'deleted'", [$userId]);
    }

    // -------------------------------------------------------------------------
    // Escritura
    // -------------------------------------------------------------------------

    /** Crea la comunidad con su administrador como primer miembro. */
    public static function create(int $ownerId, string $name, ?string $description, string $category, string $visibility): array
    {
        return Database::transaction(static function () use ($ownerId, $name, $description, $category, $visibility): array {
            $slug = self::uniqueSlug($name);
            self::execute(
                'INSERT INTO communities (owner_id, slug, name, description, category, visibility, members_count)
                 VALUES (?, ?, ?, ?, ?, ?, 1)',
                [$ownerId, $slug, $name, $description, $category, $visibility]
            );
            $id = (int) self::db()->lastInsertId();
            self::execute(
                "INSERT INTO community_members (community_id, user_id, role, status) VALUES (?, ?, 'owner', 'active')",
                [$id, $ownerId]
            );
            return ['id' => $id, 'slug' => $slug];
        });
    }

    public static function update(int $id, string $name, ?string $description, string $category): void
    {
        self::execute(
            'UPDATE communities SET name = ?, description = ?, category = ? WHERE id = ?',
            [$name, $description, $category, $id]
        );
    }

    /**
     * Cambia la visibilidad. Al pasar a pública se aceptan todas las solicitudes pendientes.
     *
     * @return list<int> ids de las personas aceptadas
     */
    public static function setVisibility(int $id, string $visibility): array
    {
        return Database::transaction(static function () use ($id, $visibility): array {
            self::execute('UPDATE communities SET visibility = ? WHERE id = ?', [$visibility, $id]);
            if ($visibility !== 'public') {
                return [];
            }
            $pending = array_map('intval', array_column(
                self::fetchAll("SELECT user_id FROM community_members WHERE community_id = ? AND status = 'pending' FOR UPDATE", [$id]),
                'user_id'
            ));
            if ($pending !== []) {
                $accepted = self::execute(
                    "UPDATE community_members SET status = 'active', joined_at = NOW() WHERE community_id = ? AND status = 'pending'",
                    [$id]
                );
                self::execute('UPDATE communities SET members_count = members_count + ? WHERE id = ?', [$accepted, $id]);
            }
            return $pending;
        });
    }

    /** Guarda la nueva ruta de imagen ('avatar' | 'cover') y borra la anterior del disco. */
    public static function setImage(array $community, string $kind, ?string $path): void
    {
        $column = $kind === 'avatar' ? 'avatar_path' : 'cover_path';
        self::execute("UPDATE communities SET $column = ? WHERE id = ?", [$path, (int) $community['id']]);
        if (!empty($community[$column]) && $community[$column] !== $path) {
            ImageUpload::delete($community[$column]);
        }
    }

    /**
     * Unirse (pública) o pedir acceso (privada). Devuelve el estado resultante, o null si ya tenía
     * una membresía (activa, pendiente o con veto).
     */
    public static function join(int $communityId, int $userId, bool $private): ?string
    {
        return Database::transaction(static function () use ($communityId, $userId, $private): ?string {
            $status = $private ? 'pending' : 'active';
            $inserted = self::execute(
                "INSERT IGNORE INTO community_members (community_id, user_id, role, status) VALUES (?, ?, 'member', ?)",
                [$communityId, $userId, $status]
            );
            if ($inserted === 0) {
                return null;
            }
            if ($status === 'active') {
                self::execute('UPDATE communities SET members_count = members_count + 1 WHERE id = ?', [$communityId]);
            }
            return $status;
        });
    }

    /**
     * Salir de la comunidad o cancelar la solicitud. El administrador no puede salir (debe transferirla)
     * y un veto no se borra así. Devuelve el estado que tenía, o null si no había nada que quitar.
     */
    public static function leave(int $communityId, int $userId): ?string
    {
        return Database::transaction(static function () use ($communityId, $userId): ?string {
            $row = self::fetchOne(
                'SELECT role, status FROM community_members WHERE community_id = ? AND user_id = ? FOR UPDATE',
                [$communityId, $userId]
            );
            if ($row === null || $row['role'] === 'owner' || $row['status'] === 'banned') {
                return null;
            }
            self::execute('DELETE FROM community_members WHERE community_id = ? AND user_id = ?', [$communityId, $userId]);
            if ($row['status'] === 'active') {
                self::execute('UPDATE communities SET members_count = members_count - (members_count > 0) WHERE id = ?', [$communityId]);
            }
            return $row['status'];
        });
    }

    public static function approve(int $communityId, int $userId): bool
    {
        return Database::transaction(static function () use ($communityId, $userId): bool {
            $changed = self::execute(
                "UPDATE community_members SET status = 'active', joined_at = NOW() WHERE community_id = ? AND user_id = ? AND status = 'pending'",
                [$communityId, $userId]
            );
            if ($changed > 0) {
                self::execute('UPDATE communities SET members_count = members_count + 1 WHERE id = ?', [$communityId]);
            }
            return $changed > 0;
        });
    }

    public static function reject(int $communityId, int $userId): bool
    {
        return self::execute(
            "DELETE FROM community_members WHERE community_id = ? AND user_id = ? AND status = 'pending'",
            [$communityId, $userId]
        ) > 0;
    }

    /** Veta a un miembro (o a quien pidió acceso): pierde el rol y no puede volver a unirse. */
    public static function ban(int $communityId, int $userId): bool
    {
        return Database::transaction(static function () use ($communityId, $userId): bool {
            $row = self::fetchOne(
                'SELECT role, status FROM community_members WHERE community_id = ? AND user_id = ? FOR UPDATE',
                [$communityId, $userId]
            );
            if ($row === null || $row['role'] === 'owner' || $row['status'] === 'banned') {
                return false;
            }
            self::execute(
                "UPDATE community_members SET status = 'banned', role = 'member' WHERE community_id = ? AND user_id = ?",
                [$communityId, $userId]
            );
            if ($row['status'] === 'active') {
                self::execute('UPDATE communities SET members_count = members_count - (members_count > 0) WHERE id = ?', [$communityId]);
            }
            return true;
        });
    }

    /** Levanta el veto: la persona queda fuera y puede volver a unirse o pedir acceso. */
    public static function unban(int $communityId, int $userId): bool
    {
        return self::execute(
            "DELETE FROM community_members WHERE community_id = ? AND user_id = ? AND status = 'banned'",
            [$communityId, $userId]
        ) > 0;
    }

    /** Nombra o retira moderadores (solo miembros activos que no sean el administrador). */
    public static function setRole(int $communityId, int $userId, string $role): bool
    {
        if (!in_array($role, ['member', 'moderator'], true)) {
            return false;
        }
        return self::execute(
            "UPDATE community_members SET role = ? WHERE community_id = ? AND user_id = ? AND status = 'active' AND role <> 'owner'",
            [$role, $communityId, $userId]
        ) > 0;
    }

    /** Transfiere la administración a un miembro activo; el administrador anterior queda como moderador. */
    public static function transfer(int $communityId, int $fromId, int $toId): bool
    {
        return Database::transaction(static function () use ($communityId, $fromId, $toId): bool {
            $promoted = self::execute(
                "UPDATE community_members SET role = 'owner' WHERE community_id = ? AND user_id = ? AND status = 'active' AND role <> 'owner'",
                [$communityId, $toId]
            );
            if ($promoted === 0) {
                return false;
            }
            self::execute("UPDATE community_members SET role = 'moderator' WHERE community_id = ? AND user_id = ?", [$communityId, $fromId]);
            self::execute('UPDATE communities SET owner_id = ? WHERE id = ?', [$toId, $communityId]);
            return true;
        });
    }

    /**
     * Saca una publicación de la comunidad sin borrarla: vuelve al perfil de su autor. Si la comunidad
     * era privada queda como "Solo yo" para no exponer contenido que solo veían los miembros.
     */
    public static function removePost(array $community, int $postId): bool
    {
        return Database::transaction(static function () use ($community, $postId): bool {
            $changed = self::execute(
                "UPDATE posts SET community_id = NULL, visibility = IF(?, 'private', visibility) WHERE id = ? AND community_id = ?",
                [$community['visibility'] === 'private' ? 1 : 0, $postId, (int) $community['id']]
            );
            if ($changed > 0) {
                self::execute('UPDATE communities SET posts_count = posts_count - (posts_count > 0) WHERE id = ?', [(int) $community['id']]);
            }
            return $changed > 0;
        });
    }

    /** Elimina la comunidad: sus publicaciones (con adjuntos), miembros, avisos e imágenes. */
    public static function delete(array $community): void
    {
        $id = (int) $community['id'];
        $posts = self::fetchAll('SELECT id, user_id, community_id, shared_post_id, status FROM posts WHERE community_id = ?', [$id]);
        foreach ($posts as $post) {
            Post::delete($post);
        }
        self::execute('DELETE FROM communities WHERE id = ?', [$id]);
        ImageUpload::delete($community['avatar_path'] ?? null);
        ImageUpload::delete($community['cover_path'] ?? null);
    }

    // -------------------------------------------------------------------------
    // Panel de administración
    // -------------------------------------------------------------------------

    public const STATUS_LABELS = ['active' => 'Activa', 'suspended' => 'Suspendida'];

    /**
     * Comunidades no eliminadas para el panel, filtradas por texto y estado.
     * @return array{communities: list<array>, hasMore: bool}
     */
    public static function adminList(string $term, ?string $status, int $page, int $limit): array
    {
        $where = ["c.status <> 'deleted'"];
        $params = [];
        $term = trim($term);
        if ($term !== '') {
            $like = '%' . self::likeEscape(mb_strtolower($term)) . '%';
            $where[] = '(c.name LIKE ? OR c.slug LIKE ?)';
            array_push($params, $like, $like);
        }
        if ($status !== null) {
            $where[] = 'c.status = ?';
            $params[] = $status;
        }
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT c.id, c.owner_id, c.slug, c.name, c.category, c.avatar_path, c.cover_path, c.visibility, c.status,
                    c.members_count, c.posts_count, c.created_at, o.username AS owner_username, o.display_name AS owner_name,
                    (SELECT COUNT(*) FROM reports r WHERE r.target_type = \'community\' AND r.target_id = c.id AND r.status IN (\'open\', \'reviewing\')) AS open_reports
             FROM communities c JOIN users o ON o.id = c.owner_id
             WHERE ' . implode(' AND ', $where) . '
             ORDER BY c.id DESC LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return ['communities' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Comunidad activa o suspendida, sin datos de quien mira (moderación). */
    public static function findAny(int $id): ?array
    {
        return self::fetchOne(
            "SELECT id, owner_id, slug, name, avatar_path, cover_path, visibility, status, members_count, posts_count
             FROM communities WHERE id = ? AND status <> 'deleted' LIMIT 1",
            [$id]
        );
    }

    /** Suspende (active → suspended) o reactiva (suspended → active) una comunidad. */
    public static function setModerationStatus(int $id, string $status): bool
    {
        $from = $status === 'suspended' ? 'active' : 'suspended';
        return self::execute('UPDATE communities SET status = ? WHERE id = ? AND status = ?', [$status, $id, $from]) > 0;
    }

    /** Antes de borrar una cuenta: descuenta su membresía activa y sus publicaciones en comunidades. */
    public static function releaseCountersForUser(int $userId): void
    {
        self::execute(
            "UPDATE communities c JOIN community_members m ON m.community_id = c.id AND m.user_id = ? AND m.status = 'active'
             SET c.members_count = GREATEST(CAST(c.members_count AS SIGNED) - 1, 0)",
            [$userId]
        );
        self::execute(
            'UPDATE communities c JOIN (
                SELECT community_id AS id, COUNT(*) AS n FROM posts WHERE user_id = ? AND community_id IS NOT NULL AND status = \'published\' GROUP BY community_id
             ) x ON x.id = c.id
             SET c.posts_count = GREATEST(CAST(c.posts_count AS SIGNED) - x.n, 0)',
            [$userId]
        );
    }

    // -------------------------------------------------------------------------

    /** Slug único a partir del nombre: minúsculas, sin acentos, guiones; con sufijo -2, -3… si ya existe. */
    private static function uniqueSlug(string $name): string
    {
        $map = [
            'á' => 'a', 'à' => 'a', 'ä' => 'a', 'â' => 'a', 'ã' => 'a', 'é' => 'e', 'è' => 'e', 'ë' => 'e', 'ê' => 'e',
            'í' => 'i', 'ì' => 'i', 'ï' => 'i', 'î' => 'i', 'ó' => 'o', 'ò' => 'o', 'ö' => 'o', 'ô' => 'o', 'õ' => 'o',
            'ú' => 'u', 'ù' => 'u', 'ü' => 'u', 'û' => 'u', 'ñ' => 'n', 'ç' => 'c', '&' => ' y ',
        ];
        $base = strtr(mb_strtolower($name), $map);
        $base = trim((string) preg_replace('/[^a-z0-9]+/', '-', $base), '-');
        $base = rtrim(substr($base, 0, 50), '-');
        if (strlen($base) < 3) {
            $base = trim('comunidad-' . $base, '-');
        }

        $taken = array_column(self::fetchAll(
            'SELECT slug FROM communities WHERE slug = ? OR slug LIKE ?',
            [$base, self::likeEscape($base) . '-%']
        ), 'slug');
        $slug = $base;
        for ($n = 2; in_array($slug, $taken, true); $n++) {
            $slug = $base . '-' . $n;
        }
        return $slug;
    }

    /** @return array{communities: list<array>, hasMore: bool} */
    private static function page(string $sql, array $params, int $page, int $limit): array
    {
        $limit = max(1, min(60, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll($sql . ' LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit), $params);
        return [
            'communities' => array_map([self::class, 'present'], array_slice($rows, 0, $limit)),
            'hasMore'     => count($rows) > $limit,
        ];
    }

    private static function present(array $r): array
    {
        $community = [
            'id'            => (int) $r['id'],
            'owner_id'      => (int) $r['owner_id'],
            'slug'          => $r['slug'],
            'name'          => $r['name'],
            'description'   => (string) ($r['description'] ?? ''),
            'category'      => (string) ($r['category'] ?? ''),
            'avatar_path'   => $r['avatar_path'],
            'cover_path'    => $r['cover_path'],
            'visibility'    => $r['visibility'],
            'members_count' => (int) $r['members_count'],
            'posts_count'   => (int) $r['posts_count'],
            'created_at'    => $r['created_at'],
            'membership'    => !empty($r['viewer_status']) ? ['role' => $r['viewer_role'], 'status' => $r['viewer_status']] : null,
        ];
        if (isset($r['owner_username'])) {
            $community['owner'] = ['username' => $r['owner_username'], 'display_name' => $r['owner_name']];
        }
        return $community;
    }
}
