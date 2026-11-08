<?php
declare(strict_types=1);

namespace Trevix\Models;

final class User extends Model
{
    private const PUBLIC_COLUMNS = 'id, username, email, display_name, bio, avatar_path, cover_path, birth_date,
        country, website, is_private, is_verified, account_type, creator_category, show_activity, message_privacy,
        notify_follows, notify_likes, notify_comments, notify_mentions, role, status, email_verified_at,
        last_seen_at, followers_count, following_count, posts_count, created_at';

    public const ACCOUNT_TYPES = ['personal' => 'Cuenta normal', 'creator' => 'Creador de contenido'];

    /** Categorías de creador. Solo 'music_artist' activa la sección Artista para publicar música. */
    public const CREATOR_CATEGORIES = [
        'music_artist' => 'Artista musical',
        'influencer'   => 'Influencer',
        'blogger'      => 'Blogger',
        'other'        => 'Otro',
    ];

    /** La cuenta puede publicar música (creador con categoría Artista musical). */
    public static function isMusicArtist(?array $user): bool
    {
        return ($user['account_type'] ?? '') === 'creator' && ($user['creator_category'] ?? '') === 'music_artist';
    }

    /** Etiqueta pública del tipo de cuenta, o null si es una cuenta normal. */
    public static function creatorLabel(?array $user): ?string
    {
        if (($user['account_type'] ?? '') !== 'creator') {
            return null;
        }
        return self::CREATOR_CATEGORIES[$user['creator_category'] ?? ''] ?? 'Creador de contenido';
    }

    /** Preferencia de aviso que controla cada tipo de notificación. */
    public const NOTIFY_COLUMNS = [
        'follow'          => 'notify_follows',
        'follow_accepted' => 'notify_follows',
        'like'            => 'notify_likes',
        'share'           => 'notify_likes',
        'comment'         => 'notify_comments',
        'reply'           => 'notify_comments',
        'mention'         => 'notify_mentions',
        'story_mention'   => 'notify_mentions',
        'event_going'     => 'notify_likes',
        'featured'        => 'notify_likes',
        'community_request'  => 'notify_follows',
        'community_accepted' => 'notify_follows',
    ];

    public const MESSAGE_PRIVACY = ['everyone', 'following', 'nobody'];

    public static function findActiveById(int $id): ?array
    {
        return self::fetchOne(
            'SELECT ' . self::PUBLIC_COLUMNS . " FROM users WHERE id = ? AND status = 'active' LIMIT 1",
            [$id]
        );
    }

    /**
     * Usuario activo junto con su hash, para validar la huella de la sesión,
     * y los avisos de la navegación: solicitudes pendientes, notificaciones y chats sin leer.
     */
    public static function findForSession(int $id): ?array
    {
        $user = self::fetchOne(
            'SELECT ' . self::PUBLIC_COLUMNS . ", password_hash,
                (SELECT COUNT(*) FROM follow_requests fr WHERE fr.target_id = users.id AND fr.status = 'pending') AS pending_requests
             FROM users WHERE id = ? AND status = 'active' LIMIT 1",
            [$id]
        );
        if ($user === null) {
            return null;
        }
        $user['unread_notifications'] = Notification::unreadCount($id);
        $user['unread_messages'] = Conversation::unreadCount($id);
        return $user;
    }

    public static function updateActivityPrivacy(int $id, int $showActivity, string $messagePrivacy): void
    {
        self::execute('UPDATE users SET show_activity = ?, message_privacy = ? WHERE id = ?', [$showActivity, $messagePrivacy, $id]);
    }

    /** @param array<string,int> $prefs columna notify_* => 0|1 */
    public static function updateNotificationPrefs(int $id, array $prefs): void
    {
        $allowed = array_unique(array_values(self::NOTIFY_COLUMNS));
        $sets = [];
        $params = [];
        foreach ($prefs as $column => $value) {
            if (in_array($column, $allowed, true)) {
                $sets[] = $column . ' = ?';
                $params[] = $value ? 1 : 0;
            }
        }
        if ($sets === []) {
            return;
        }
        $params[] = $id;
        self::execute('UPDATE users SET ' . implode(', ', $sets) . ' WHERE id = ?', $params);
    }

    /** La persona tiene actividad reciente y permite mostrarla. */
    public static function isOnline(array $user): bool
    {
        if (empty($user['show_activity']) || empty($user['last_seen_at'])) {
            return false;
        }
        $seen = strtotime((string) $user['last_seen_at']);
        return $seen !== false && time() - $seen <= (int) \Trevix\Core\Config::get('app.presence_window', 240);
    }

    /** Datos mínimos de una cuenta no eliminada para acciones de seguimiento y bloqueo. */
    public static function findForRelation(int $id): ?array
    {
        return self::fetchOne(
            "SELECT id, username, display_name, is_private, status, followers_count FROM users WHERE id = ? AND status <> 'deleted' LIMIT 1",
            [$id]
        );
    }

    public static function followersCount(int $id): int
    {
        return (int) self::fetchValue('SELECT followers_count FROM users WHERE id = ?', [$id]);
    }

    public static function setPrivate(int $id, bool $private): void
    {
        self::execute('UPDATE users SET is_private = ? WHERE id = ?', [$private ? 1 : 0, $id]);
    }

    /**
     * Búsqueda de personas (usuario, nombre, biografía, ciudad pública e intereses), ordenada por coincidencia y
     * cercanía con quien busca. Ver People::search.
     *
     * @return array{users: list<array>, hasMore: bool}
     */
    public static function search(int $viewerId, string $term, int $page, int $limit): array
    {
        return People::search($viewerId, $term, $page, $limit);
    }

    public static function passwordHash(int $id): ?string
    {
        $hash = self::fetchValue('SELECT password_hash FROM users WHERE id = ? LIMIT 1', [$id]);
        return is_string($hash) ? $hash : null;
    }

    /** Cuenta a la que se puede enviar un enlace de recuperación. */
    public static function findForPasswordReset(string $email): ?array
    {
        return self::fetchOne(
            "SELECT id, email, display_name FROM users WHERE email = ? AND status <> 'deleted' LIMIT 1",
            [mb_strtolower($email)]
        );
    }

    public static function findBasicById(int $id): ?array
    {
        return self::fetchOne(
            "SELECT id, username, email, display_name, email_verified_at, avatar_path, cover_path FROM users WHERE id = ? AND status <> 'deleted' LIMIT 1",
            [$id]
        );
    }

    public static function findByUsername(string $username): ?array
    {
        return self::fetchOne(
            'SELECT ' . self::PUBLIC_COLUMNS . " FROM users WHERE username = ? AND status <> 'deleted' LIMIT 1",
            [mb_strtolower($username)]
        );
    }

    public static function follows(int $followerId, int $followingId): bool
    {
        return (bool) self::fetchValue(
            'SELECT 1 FROM follows WHERE follower_id = ? AND following_id = ? LIMIT 1',
            [$followerId, $followingId]
        );
    }

    /** Hay un bloqueo entre ambos usuarios, en cualquier dirección. */
    public static function blockedBetween(int $a, int $b): bool
    {
        return (bool) self::fetchValue(
            'SELECT 1 FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1',
            [$a, $b, $b, $a]
        );
    }

    /** Datos necesarios para autenticar, buscando por correo o nombre de usuario. */
    public static function findForLogin(string $identifier): ?array
    {
        $identifier = mb_strtolower(trim($identifier));
        $column = str_contains($identifier, '@') ? 'email' : 'username';

        return self::fetchOne(
            'SELECT id, password_hash, role, status, suspended_until, suspension_reason FROM users WHERE ' . $column . " = ? AND status <> 'deleted' LIMIT 1",
            [$identifier]
        );
    }

    public static function usernameExists(string $username, ?int $exceptId = null): bool
    {
        return (bool) self::fetchValue('SELECT 1 FROM users WHERE username = ? AND id <> ? LIMIT 1', [$username, $exceptId ?? 0]);
    }

    public static function emailExists(string $email, ?int $exceptId = null): bool
    {
        return (bool) self::fetchValue('SELECT 1 FROM users WHERE email = ? AND id <> ? LIMIT 1', [$email, $exceptId ?? 0]);
    }

    /** @param array{username:string, email:string, password_hash:string, display_name:string, birth_date:string} $data */
    public static function create(array $data): int
    {
        self::execute(
            'INSERT INTO users (username, email, password_hash, display_name, birth_date, last_seen_at)
             VALUES (?, ?, ?, ?, ?, NOW())',
            [$data['username'], $data['email'], $data['password_hash'], $data['display_name'], $data['birth_date']]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function updatePasswordHash(int $id, string $hash): void
    {
        self::execute('UPDATE users SET password_hash = ? WHERE id = ?', [$hash, $id]);
    }

    /** Reactiva cuentas desactivadas por su dueño o con suspensión vencida. */
    public static function reactivate(int $id): void
    {
        self::execute(
            "UPDATE users SET status = 'active', suspended_until = NULL, suspension_reason = NULL WHERE id = ?",
            [$id]
        );
    }

    public static function touchLastSeen(int $id): void
    {
        self::execute('UPDATE users SET last_seen_at = NOW() WHERE id = ?', [$id]);
    }

    /**
     * @param array{display_name:string, username:string, bio:?string, website:?string, country:?string,
     *              birth_date:?string, is_private:int, avatar_path:?string, cover_path:?string,
     *              account_type:string, creator_category:?string} $data
     */
    public static function updateProfile(int $id, array $data): void
    {
        self::execute(
            'UPDATE users SET display_name = ?, username = ?, bio = ?, website = ?, country = ?, birth_date = ?,
                 is_private = ?, avatar_path = ?, cover_path = ?, account_type = ?, creator_category = ? WHERE id = ?',
            [
                $data['display_name'], $data['username'], $data['bio'], $data['website'], $data['country'],
                $data['birth_date'], $data['is_private'], $data['avatar_path'], $data['cover_path'],
                $data['account_type'], $data['creator_category'], $id,
            ]
        );
    }

    public static function setBirthDate(int $id, string $date): void
    {
        self::execute('UPDATE users SET birth_date = ? WHERE id = ?', [$date, $id]);
    }

    public static function updateUsername(int $id, string $username): void
    {
        self::execute('UPDATE users SET username = ? WHERE id = ?', [$username, $id]);
    }

    /** El nuevo correo queda verificado porque se confirmó desde un enlace enviado a esa dirección. */
    public static function updateEmail(int $id, string $email): void
    {
        self::execute('UPDATE users SET email = ?, email_verified_at = NOW() WHERE id = ?', [$email, $id]);
    }

    public static function markEmailVerified(int $id): void
    {
        self::execute('UPDATE users SET email_verified_at = COALESCE(email_verified_at, NOW()) WHERE id = ?', [$id]);
    }

    public static function deactivate(int $id): void
    {
        self::execute("UPDATE users SET status = 'deactivated' WHERE id = ? AND status = 'active'", [$id]);
    }

    /** Eliminación definitiva: las claves foráneas borran en cascada el contenido del usuario. */
    public static function deletePermanently(int $id): void
    {
        self::execute('DELETE FROM users WHERE id = ?', [$id]);
    }

    // -------------------------------------------------------------------------
    // Panel de administración
    // -------------------------------------------------------------------------

    public const ROLE_LABELS = ['user' => 'Usuario', 'moderator' => 'Moderador', 'admin' => 'Administrador'];
    public const STATUS_LABELS = ['active' => 'Activa', 'suspended' => 'Suspendida', 'deactivated' => 'Desactivada'];

    private const ADMIN_COLUMNS = 'u.id, u.username, u.email, u.display_name, u.avatar_path, u.bio, u.role, u.status,
        u.suspended_until, u.suspension_reason, u.is_verified, u.is_private, u.email_verified_at, u.posts_count,
        u.followers_count, u.following_count, u.last_seen_at, u.created_at';

    /**
     * Cuentas no eliminadas, de la más reciente a la más antigua, filtradas por texto, rol y estado.
     * @return array{users: list<array>, hasMore: bool}
     */
    public static function adminList(string $term, ?string $role, ?string $status, int $page, int $limit): array
    {
        $where = ["u.status <> 'deleted'"];
        $params = [];
        $term = mb_strtolower(trim(ltrim(trim($term), '@')));
        if ($term !== '') {
            $like = '%' . self::likeEscape($term) . '%';
            $where[] = '(u.username LIKE ? OR u.display_name LIKE ? OR u.email LIKE ?)';
            array_push($params, $like, $like, $like);
        }
        if ($role !== null) {
            $where[] = 'u.role = ?';
            $params[] = $role;
        }
        if ($status !== null) {
            $where[] = 'u.status = ?';
            $params[] = $status;
        }
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT ' . self::ADMIN_COLUMNS . ",
                    (SELECT COUNT(*) FROM reports r WHERE r.target_type = 'user' AND r.target_id = u.id AND r.status IN ('open', 'reviewing')) AS open_reports
             FROM users u WHERE " . implode(' AND ', $where) . '
             ORDER BY u.id DESC LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return ['users' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    public static function findForAdmin(int $id): ?array
    {
        return self::fetchOne('SELECT ' . self::ADMIN_COLUMNS . " FROM users u WHERE u.id = ? AND u.status <> 'deleted' LIMIT 1", [$id]);
    }

    /** $until null = suspensión sin fecha de fin. Las sesiones abiertas dejan de valer al instante. */
    public static function suspend(int $id, ?string $until, string $reason): bool
    {
        return self::execute(
            "UPDATE users SET status = 'suspended', suspended_until = ?, suspension_reason = ?
             WHERE id = ? AND status IN ('active', 'deactivated', 'suspended')",
            [$until, $reason, $id]
        ) > 0;
    }

    public static function unsuspend(int $id): bool
    {
        return self::execute(
            "UPDATE users SET status = 'active', suspended_until = NULL, suspension_reason = NULL WHERE id = ? AND status = 'suspended'",
            [$id]
        ) > 0;
    }

    public static function setRole(int $id, string $role): bool
    {
        return self::execute("UPDATE users SET role = ? WHERE id = ? AND status <> 'deleted'", [$role, $id]) > 0;
    }

    public static function setVerified(int $id, bool $verified): bool
    {
        return self::execute('UPDATE users SET is_verified = ? WHERE id = ?', [$verified ? 1 : 0, $id]) > 0;
    }

    public static function activeAdminCount(): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM users WHERE role = 'admin' AND status = 'active'");
    }
}
