<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Encontrar personas: sugerencias de amigos según cercanía y búsqueda ordenada por relación con quien busca.
 *
 * Cercanía (sugerencias): te sigue, amigos en común (personas que sigues y la siguen), misma ciudad o ciudad natal,
 * interacciones de los últimos 90 días (Me gusta, comentarios y chats, en ambos sentidos) e intereses en común.
 * La ciudad solo cuenta si esa persona la muestra a todos: así una sugerencia nunca revela dónde vive alguien.
 */
final class People extends Model
{
    private const INTERACTION_DAYS = 90;
    private const DISMISS_DAYS = 90;

    /** Puntos por señal. Las sumas se limitan para que una sola señal no tape a las demás. */
    private const SCORE = 'c.follows_you * 40 + LEAST(c.mutuals, 6) * 12 + c.same_city * 30 + c.same_home * 15
        + c.near * 8 + LEAST(c.interactions, 30) + LEAST(c.interests, 3) * 6';

    /**
     * Personas que el usuario aún no sigue, de la más cercana a la menos. Cada una trae el motivo («reason»).
     *
     * @return array{users: list<array>, hasMore: bool}
     */
    public static function suggestions(int $viewerId, int $limit = 10, int $page = 1): array
    {
        $limit = max(1, min(30, $limit));
        $page = max(1, min(10, $page));
        $keys = UserProfile::keysFor($viewerId);
        $since = date('Y-m-d H:i:s', strtotime('-' . self::INTERACTION_DAYS . ' days'));

        // id, follows_you, mutual, same_city, same_home, near, interactions, interests
        $sources = [
            'SELECT f2.following_id, 0, 1, 0, 0, 0, 0, 0 FROM follows f1 JOIN follows f2 ON f2.follower_id = f1.following_id WHERE f1.follower_id = ?',
            'SELECT follower_id, 1, 0, 0, 0, 0, 0, 0 FROM follows WHERE following_id = ?',
            'SELECT l.user_id, 0, 0, 0, 0, 0, 2, 0 FROM likes l JOIN posts p ON p.id = l.post_id WHERE p.user_id = ? AND l.created_at > ?',
            "SELECT c.user_id, 0, 0, 0, 0, 0, 3, 0 FROM comments c JOIN posts p ON p.id = c.post_id WHERE p.user_id = ? AND c.status = 'published' AND c.created_at > ?",
            'SELECT p.user_id, 0, 0, 0, 0, 0, 2, 0 FROM likes l JOIN posts p ON p.id = l.post_id WHERE l.user_id = ? AND l.created_at > ?',
            "SELECT p.user_id, 0, 0, 0, 0, 0, 3, 0 FROM comments c JOIN posts p ON p.id = c.post_id WHERE c.user_id = ? AND c.status = 'published' AND c.created_at > ?",
            "SELECT cp2.user_id, 0, 0, 0, 0, 0, 10, 0 FROM conversation_participants cp1
                JOIN conversations cv ON cv.id = cp1.conversation_id AND cv.type = 'direct' AND cv.last_message_at > ?
                JOIN conversation_participants cp2 ON cp2.conversation_id = cp1.conversation_id AND cp2.user_id <> cp1.user_id
              WHERE cp1.user_id = ?",
            'SELECT b.user_id, 0, 0, 0, 0, 0, 0, 1 FROM user_interests a JOIN user_interests b ON b.interest_key = a.interest_key AND b.user_id <> a.user_id WHERE a.user_id = ?',
            "(SELECT id, 0, 0, 0, 0, 0, 0, 0 FROM users WHERE status = 'active' ORDER BY followers_count DESC, id DESC LIMIT 40)",
            "(SELECT id, 0, 0, 0, 0, 0, 0, 0 FROM users WHERE status = 'active' ORDER BY id DESC LIMIT 40)",
        ];
        $params = [$viewerId, $viewerId, $viewerId, $since, $viewerId, $since, $viewerId, $since, $viewerId, $since, $since, $viewerId, $viewerId];

        $public = "details_audience = 'everyone'";
        if ($keys['city_key'] !== null) {
            $sources[] = "(SELECT user_id, 0, 0, 1, 0, 0, 0, 0 FROM user_profiles WHERE city_key = ? AND $public LIMIT 300)";
            $sources[] = "(SELECT user_id, 0, 0, 0, 0, 1, 0, 0 FROM user_profiles WHERE hometown_key = ? AND $public LIMIT 200)";
            array_push($params, $keys['city_key'], $keys['city_key']);
        }
        if ($keys['hometown_key'] !== null) {
            $sources[] = "(SELECT user_id, 0, 0, 0, 1, 0, 0, 0 FROM user_profiles WHERE hometown_key = ? AND $public LIMIT 300)";
            $sources[] = "(SELECT user_id, 0, 0, 0, 0, 1, 0, 0 FROM user_profiles WHERE city_key = ? AND $public LIMIT 200)";
            array_push($params, $keys['hometown_key'], $keys['hometown_key']);
        }

        $sql = 'SELECT ' . Follow::USER_COLUMNS . ', up.city, up.hometown, up.city_key, up.hometown_key,
                c.follows_you, c.mutuals, c.same_city, c.same_home, c.near, c.interactions, c.interests
            FROM (
                SELECT id, MAX(follows_you) AS follows_you, SUM(mutual) AS mutuals, MAX(same_city) AS same_city,
                       MAX(same_home) AS same_home, MAX(near) AS near, SUM(interactions) AS interactions, SUM(interests) AS interests
                FROM (
                    SELECT 0 AS id, 0 AS follows_you, 0 AS mutual, 0 AS same_city, 0 AS same_home, 0 AS near, 0 AS interactions, 0 AS interests FROM DUAL WHERE 1 = 0
                    UNION ALL ' . implode("\n UNION ALL ", $sources) . '
                ) candidates GROUP BY id
            ) c
            JOIN users u ON u.id = c.id
            LEFT JOIN user_profiles up ON up.user_id = u.id
            WHERE u.id <> ? AND ' . Follow::VISIBLE_USER . '
              AND NOT EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id)
              AND NOT EXISTS (SELECT 1 FROM follow_requests r WHERE r.requester_id = ? AND r.target_id = u.id AND r.status = \'pending\')
              AND NOT EXISTS (SELECT 1 FROM suggestion_dismissals sd WHERE sd.user_id = ? AND sd.target_id = u.id AND sd.created_at > ?)
            ORDER BY (' . self::SCORE . ') DESC, u.followers_count DESC, u.id DESC
            LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit);
        array_push($params, $viewerId, $viewerId, $viewerId, $viewerId, $viewerId, $viewerId,
            date('Y-m-d H:i:s', strtotime('-' . self::DISMISS_DAYS . ' days')));

        $rows = self::fetchAll($sql, $params);
        $hasMore = count($rows) > $limit;
        $rows = array_slice($rows, 0, $limit);

        $recent = strtotime('-14 days');
        foreach ($rows as &$row) {
            $mutuals = (int) $row['mutuals'];
            $together = $mutuals > 0 ? ' · ' . $mutuals . ($mutuals === 1 ? ' amigo en común' : ' amigos en común') : '';
            $row['reason'] = match (true) {
                (bool) $row['follows_you'] => 'Te sigue',
                (bool) $row['same_city']   => 'Vive en ' . $row['city'] . $together,
                $mutuals > 0               => 'Seguido por ' . self::mutualName($viewerId, (int) $row['id']) . ($mutuals > 1 ? ' y ' . ($mutuals - 1) . ' más' : ''),
                (bool) $row['same_home']   => 'También es de ' . $row['hometown'],
                (bool) $row['near']        => $row['hometown_key'] !== null && $row['hometown_key'] === $keys['city_key']
                    ? 'Es de ' . $row['hometown'] : 'Vive en ' . $row['city'],
                (int) $row['interactions'] > 0 => 'Interactúa contigo',
                (int) $row['interests'] > 0    => 'También le gusta ' . self::sharedInterest($viewerId, (int) $row['id']),
                strtotime($row['created_at']) > $recent => 'Nuevo en TREVIX',
                default => 'Popular en TREVIX',
            };
            $row['relation'] = ['following' => false, 'requested' => false, 'follows_you' => (bool) $row['follows_you']];
            unset($row['city'], $row['hometown'], $row['city_key'], $row['hometown_key'], $row['follows_you'], $row['mutuals'],
                $row['same_city'], $row['same_home'], $row['near'], $row['interactions'], $row['interests']);
        }
        unset($row);
        return ['users' => $rows, 'hasMore' => $hasMore];
    }

    /** «No me interesa»: esa persona deja de aparecer en las sugerencias durante 90 días. */
    public static function dismiss(int $viewerId, int $targetId): void
    {
        self::execute(
            'INSERT INTO suggestion_dismissals (user_id, target_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE created_at = NOW()',
            [$viewerId, $targetId]
        );
    }

    /**
     * Búsqueda de personas por usuario, nombre, biografía, ciudad (si es pública) e intereses. Primero el usuario
     * exacto; después, cuanto más cerca de quien busca (lo sigue, le sigue, amigos en común, misma ciudad) y mejor
     * coincida el texto, más arriba. Cada resultado trae el motivo («reason»).
     *
     * @return array{users: list<array>, hasMore: bool}
     */
    public static function search(int $viewerId, string $term, int $page, int $limit): array
    {
        $term = mb_strtolower(trim(ltrim(trim($term), '@')));
        if ($term === '') {
            return ['users' => [], 'hasMore' => false];
        }
        $like = self::likeEscape($term);
        $key = UserProfile::key($term);
        $keyLike = mb_strlen($key) >= 3 ? self::likeEscape($key) . '%' : null;
        $boolean = self::booleanSearch($term);
        $viewerCity = UserProfile::keysFor($viewerId)['city_key'];
        $match = 'MATCH (u.username, u.display_name, u.bio) AGAINST (? IN BOOLEAN MODE)';
        $publicCity = "up.details_audience = 'everyone'";

        $select = 'SELECT ' . Follow::USER_COLUMNS . ', up.city,
                (u.username = ?) AS exact_match,
                (u.username LIKE ? OR u.display_name LIKE ?) AS prefix_match,
                ' . ($boolean !== '' ? $match : '0') . ' AS relevance,
                EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.following_id = u.id) AS i_follow,
                EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = u.id AND f.following_id = ?) AS follows_me,
                COALESCE(' . $publicCity . ' AND up.city_key = ?, 0) AS same_city,
                ' . ($keyLike !== null ? "COALESCE($publicCity AND up.city_key LIKE ?, 0)" : '0') . ' AS city_match,
                ' . ($keyLike !== null ? '(SELECT ui.label FROM user_interests ui WHERE ui.user_id = u.id AND ui.interest_key LIKE ? LIMIT 1)' : 'NULL') . ' AS interest_label';
        $params = [$term, $like . '%', $like . '%'];
        if ($boolean !== '') {
            $params[] = $boolean;
        }
        array_push($params, $viewerId, $viewerId, $viewerCity ?? '');
        if ($keyLike !== null) {
            array_push($params, $keyLike, $keyLike);
        }

        $where = ['u.username LIKE ?', 'u.display_name LIKE ?'];
        array_push($params, $viewerId, $viewerId);
        $whereParams = ['%' . $like . '%', '%' . $like . '%'];
        if ($boolean !== '') {
            $where[] = $match;
            $whereParams[] = $boolean;
        }
        if ($keyLike !== null) {
            $where[] = "($publicCity AND up.city_key LIKE ?)";
            $where[] = 'EXISTS (SELECT 1 FROM user_interests ui WHERE ui.user_id = u.id AND ui.interest_key LIKE ?)';
            array_push($whereParams, $keyLike, $keyLike);
        }

        $limit = max(1, min(50, $limit));
        $page = max(1, $page);
        $sql = $select . '
            FROM users u
            LEFT JOIN user_profiles up ON up.user_id = u.id
            WHERE ' . Follow::VISIBLE_USER . ' AND (' . implode(' OR ', $where) . ')
            ORDER BY exact_match DESC,
                (prefix_match * 100 + LEAST(relevance, 10) * 8 + i_follow * 30 + follows_me * 20 + same_city * 15
                 + city_match * 10 + (interest_label IS NOT NULL) * 8 + u.is_verified * 6) DESC,
                u.followers_count DESC, u.id DESC
            LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit);
        $rows = self::fetchAll($sql, array_merge($params, $whereParams));
        $hasMore = count($rows) > $limit;
        $rows = array_slice($rows, 0, $limit);

        $mutuals = self::mutualCounts($viewerId, array_map(static fn (array $r): int => (int) $r['id'], $rows));
        foreach ($rows as &$row) {
            $count = $mutuals[(int) $row['id']] ?? 0;
            $row['reason'] = match (true) {
                (bool) $row['i_follow']   => 'Lo sigues',
                (bool) $row['follows_me'] => 'Te sigue',
                $count > 0                => $count . ($count === 1 ? ' amigo en común' : ' amigos en común'),
                (bool) $row['city_match'] || (bool) $row['same_city'] => 'Vive en ' . $row['city'],
                $row['interest_label'] !== null => 'Le interesa ' . $row['interest_label'],
                default => null,
            };
            unset($row['city'], $row['exact_match'], $row['prefix_match'], $row['relevance'], $row['i_follow'], $row['follows_me'],
                $row['same_city'], $row['city_match'], $row['interest_label']);
        }
        unset($row);
        return ['users' => Follow::withRelations($viewerId, $rows), 'hasMore' => $hasMore];
    }

    /** @return array<int, int> id => personas que sigue quien mira y que siguen a esa cuenta */
    private static function mutualCounts(int $viewerId, array $ids): array
    {
        if ($ids === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT b.following_id AS id, COUNT(*) AS n FROM follows a JOIN follows b ON b.follower_id = a.following_id
             WHERE a.follower_id = ? AND b.following_id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')
             GROUP BY b.following_id',
            array_merge([$viewerId], $ids)
        );
        return array_column(array_map(static fn (array $r): array => ['id' => (int) $r['id'], 'n' => (int) $r['n']], $rows), 'n', 'id');
    }

    /** Nombre de una persona que el usuario sigue y que a su vez sigue a $userId (la más popular). */
    private static function mutualName(int $viewerId, int $userId): string
    {
        $name = self::fetchValue(
            "SELECT mu.display_name FROM follows a
             JOIN follows b ON b.follower_id = a.following_id AND b.following_id = ?
             JOIN users mu ON mu.id = a.following_id AND mu.status = 'active'
             WHERE a.follower_id = ? ORDER BY mu.followers_count DESC LIMIT 1",
            [$userId, $viewerId]
        );
        return is_string($name) ? $name : 'personas que sigues';
    }

    private static function sharedInterest(int $viewerId, int $userId): string
    {
        $label = self::fetchValue(
            'SELECT b.label FROM user_interests a JOIN user_interests b ON b.interest_key = a.interest_key AND b.user_id = ?
             WHERE a.user_id = ? ORDER BY a.position LIMIT 1',
            [$userId, $viewerId]
        );
        return is_string($label) ? $label : 'lo mismo que a ti';
    }
}
