<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Grupos de mensajes (conversations.type = 'group'): participantes con rol (owner, admin, member), enlace de
 * invitación (invite_code), solicitudes para los privados y búsqueda de los públicos. Quien sale queda con left_at
 * (al volver a entrar solo ve los mensajes nuevos).
 */
final class Group extends Model
{
    public static function find(int $id): ?array
    {
        return self::fetchOne("SELECT * FROM conversations WHERE id = ? AND type = 'group' LIMIT 1", [$id]);
    }

    public static function findByInvite(string $code): ?array
    {
        return self::fetchOne("SELECT * FROM conversations WHERE invite_code = ? AND type = 'group' LIMIT 1", [$code]);
    }

    public static function newInviteCode(): string
    {
        $alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
        $code = '';
        for ($i = 0; $i < 16; $i++) {
            $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }
        return $code;
    }

    /** Crea el grupo con su dueño. Debe llamarse dentro de una transacción. */
    public static function create(int $ownerId, string $title, ?string $description, string $visibility, ?string $avatarPath): int
    {
        self::execute(
            "INSERT INTO conversations (type, title, description, avatar_path, visibility, invite_code, created_by, last_message_at)
             VALUES ('group', ?, ?, ?, ?, ?, ?, NOW())",
            [$title, $description, $avatarPath, $visibility, self::newInviteCode(), $ownerId]
        );
        $id = (int) self::db()->lastInsertId();
        self::addMember($id, $ownerId, 'owner');
        return $id;
    }

    /** Rol activo de la persona en el grupo, o null si no participa. */
    public static function role(int $groupId, int $userId): ?string
    {
        $role = self::fetchValue(
            'SELECT role FROM conversation_participants WHERE conversation_id = ? AND user_id = ? AND left_at IS NULL',
            [$groupId, $userId]
        );
        return $role !== false ? (string) $role : null;
    }

    public static function isManager(?string $role): bool
    {
        return $role === 'owner' || $role === 'admin';
    }

    public static function memberCount(int $groupId): int
    {
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = ? AND left_at IS NULL',
            [$groupId]
        );
    }

    /**
     * Añade (o vuelve a añadir) a una persona. Empieza con todo leído: solo verá los mensajes desde ahora.
     * Debe llamarse dentro de una transacción.
     */
    public static function addMember(int $groupId, int $userId, string $role = 'member'): void
    {
        self::execute(
            'INSERT INTO conversation_participants (conversation_id, user_id, role, last_read_message_id, joined_at)
             VALUES (?, ?, ?, (SELECT last_message_id FROM conversations WHERE id = ?), NOW())
             ON DUPLICATE KEY UPDATE role = VALUES(role), left_at = NULL, joined_at = NOW(), is_muted = 0,
                 last_read_message_id = VALUES(last_read_message_id), nickname = NULL, wallpaper = NULL',
            [$groupId, $userId, $role, $groupId]
        );
        self::execute('DELETE FROM conversation_requests WHERE conversation_id = ? AND user_id = ?', [$groupId, $userId]);
    }

    public static function removeMember(int $groupId, int $userId): void
    {
        self::execute(
            "UPDATE conversation_participants SET left_at = NOW(), role = 'member' WHERE conversation_id = ? AND user_id = ? AND left_at IS NULL",
            [$groupId, $userId]
        );
    }

    public static function setRole(int $groupId, int $userId, string $role): void
    {
        self::execute(
            'UPDATE conversation_participants SET role = ? WHERE conversation_id = ? AND user_id = ? AND left_at IS NULL',
            [$role, $groupId, $userId]
        );
    }

    /**
     * Cuando el dueño sale (o elimina su cuenta), el grupo pasa al administrador más antiguo o, si no hay, a quien
     * lleva más tiempo. Devuelve el id del nuevo dueño o null si el grupo quedó vacío.
     */
    public static function promoteSuccessor(int $groupId): ?int
    {
        $next = self::fetchValue(
            "SELECT user_id FROM conversation_participants WHERE conversation_id = ? AND left_at IS NULL
             ORDER BY role = 'admin' DESC, joined_at ASC LIMIT 1",
            [$groupId]
        );
        if ($next === false) {
            return null;
        }
        self::setRole($groupId, (int) $next, 'owner');
        return (int) $next;
    }

    /** Ids de los participantes activos. */
    public static function memberIds(int $groupId): array
    {
        return array_map('intval', array_column(self::fetchAll(
            'SELECT user_id FROM conversation_participants WHERE conversation_id = ? AND left_at IS NULL',
            [$groupId]
        ), 'user_id'));
    }

    /** Participantes (dueño y administradores primero) con su rol y si ya configuraron el cifrado. */
    public static function members(int $groupId, int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $offset = ($page - 1) * $limit;
        $rows = self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, u.status, cp.role, cp.joined_at,
                    (k.user_id IS NOT NULL) AS has_key
             FROM conversation_participants cp
             JOIN users u ON u.id = cp.user_id
             LEFT JOIN user_keys k ON k.user_id = u.id
             WHERE cp.conversation_id = ? AND cp.left_at IS NULL
             ORDER BY FIELD(cp.role, 'owner', 'admin', 'member'), u.display_name ASC
             LIMIT $limit OFFSET $offset",
            [$groupId]
        );
        $hasMore = count($rows) === $limit && self::memberCount($groupId) > $offset + $limit;
        return ['users' => $rows, 'hasMore' => $hasMore];
    }

    /** Solicitudes pendientes para entrar a un grupo privado. */
    public static function requests(int $groupId): array
    {
        return self::fetchAll(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, r.created_at
             FROM conversation_requests r JOIN users u ON u.id = r.user_id AND u.status = 'active'
             WHERE r.conversation_id = ? ORDER BY r.created_at ASC LIMIT 200",
            [$groupId]
        );
    }

    public static function requestCount(int $groupId): int
    {
        return (int) self::fetchValue('SELECT COUNT(*) FROM conversation_requests WHERE conversation_id = ?', [$groupId]);
    }

    public static function hasRequest(int $groupId, int $userId): bool
    {
        return (bool) self::fetchValue('SELECT 1 FROM conversation_requests WHERE conversation_id = ? AND user_id = ?', [$groupId, $userId]);
    }

    public static function addRequest(int $groupId, int $userId): void
    {
        self::execute('INSERT IGNORE INTO conversation_requests (conversation_id, user_id) VALUES (?, ?)', [$groupId, $userId]);
    }

    public static function deleteRequest(int $groupId, int $userId): bool
    {
        return self::execute('DELETE FROM conversation_requests WHERE conversation_id = ? AND user_id = ?', [$groupId, $userId]) === 1;
    }

    /** Cambia los datos indicados (columnas permitidas). */
    public static function update(int $groupId, array $fields): void
    {
        $allowed = ['title', 'description', 'avatar_path', 'cover_path', 'visibility', 'invite_code'];
        $sets = [];
        $params = [];
        foreach ($fields as $column => $value) {
            if (!in_array($column, $allowed, true)) {
                throw new \InvalidArgumentException('Campo del grupo desconocido: ' . $column);
            }
            $sets[] = "$column = ?";
            $params[] = $value;
        }
        if ($sets === []) {
            return;
        }
        $params[] = $groupId;
        self::execute('UPDATE conversations SET ' . implode(', ', $sets) . " WHERE id = ? AND type = 'group'", $params);
    }

    /** Grupos públicos por nombre o descripción (para unirse con su enlace desde la búsqueda). */
    public static function searchPublic(string $term, int $viewerId, int $limit): array
    {
        $like = '%' . self::likeEscape(mb_strtolower($term)) . '%';
        return self::fetchAll(
            "SELECT c.id, c.title, c.description, c.avatar_path, c.cover_path, c.invite_code,
                    (SELECT COUNT(*) FROM conversation_participants gm WHERE gm.conversation_id = c.id AND gm.left_at IS NULL) AS members_count,
                    EXISTS (SELECT 1 FROM conversation_participants me WHERE me.conversation_id = c.id AND me.user_id = ? AND me.left_at IS NULL) AS is_member
             FROM conversations c
             WHERE c.type = 'group' AND c.visibility = 'public' AND (c.title LIKE ? OR c.description LIKE ?)
             ORDER BY members_count DESC, c.id DESC LIMIT " . max(1, min(50, $limit)),
            [$viewerId, $like, $like]
        );
    }

    /** Borra un grupo vacío con sus archivos. */
    public static function deleteIfEmpty(int $groupId): bool
    {
        if (self::memberCount($groupId) > 0) {
            return false;
        }
        $group = self::find($groupId);
        if ($group === null) {
            return false;
        }
        $files = array_column(self::fetchAll(
            'SELECT media_path FROM messages WHERE conversation_id = ? AND media_path IS NOT NULL',
            [$groupId]
        ), 'media_path');
        self::execute('DELETE FROM conversations WHERE id = ?', [$groupId]);
        foreach ($files as $path) {
            \Trevix\Services\MediaUpload::delete($path);
        }
        \Trevix\Services\ImageUpload::delete($group['avatar_path']);
        \Trevix\Services\ImageUpload::delete($group['cover_path']);
        return true;
    }
}
