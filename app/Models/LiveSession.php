<?php
declare(strict_types=1);

namespace Trevix\Models;

final class LiveSession extends Model
{
    public const KINDS = ['audio', 'video', 'live'];

    public const LIVE_MODES = ['camera', 'voice_chat'];

    public const MAX_VOICE_SPEAKERS = 8;

    /** Segundos sonando antes de marcar «perdida» (timbrar ~1 minuto). */
    public const CALL_RING_TIMEOUT_SEC = 60;

    private const SESSION_COLS = 'id, room_name, kind, host_user_id, peer_user_id, status, title, description, hashtags, category, cover_url, live_mode,
        likes_count, viewers_peak, gifts_total_cents, unique_viewers, join_count, created_at, started_at, ended_at';

    public static function find(int $id): ?array
    {
        return self::fetchOne(
            'SELECT ' . self::SESSION_COLS . ' FROM live_sessions WHERE id = ?',
            [$id]
        );
    }

    /**
     * @param array{description?:?string, hashtags?:?string, category?:?string, cover_url?:?string, live_mode?:string} $meta
     */
    public static function insert(
        string $roomName,
        string $kind,
        int $hostId,
        ?int $peerId,
        string $status,
        ?string $title,
        array $meta = [],
    ): int {
        $liveMode = (string) ($meta['live_mode'] ?? 'camera');
        if (!in_array($liveMode, self::LIVE_MODES, true)) {
            $liveMode = 'camera';
        }
        self::execute(
            'INSERT INTO live_sessions (room_name, kind, host_user_id, peer_user_id, status, title, description, hashtags, category, cover_url, live_mode)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $roomName,
                $kind,
                $hostId,
                $peerId,
                $status,
                $title,
                $meta['description'] ?? null,
                $meta['hashtags'] ?? null,
                $meta['category'] ?? null,
                $meta['cover_url'] ?? null,
                $liveMode,
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function updateStatus(int $id, string $status, ?string $startedAt, ?string $endedAt): void
    {
        self::execute(
            'UPDATE live_sessions SET status = ?, started_at = COALESCE(?, started_at), ended_at = COALESCE(?, ended_at) WHERE id = ?',
            [$status, $startedAt, $endedAt, $id]
        );
    }

    public static function activeRingingForPeer(int $peerId): ?array
    {
        return self::fetchOne(
            'SELECT id FROM live_sessions WHERE peer_user_id = ? AND status = ? AND kind IN (?, ?) ORDER BY id DESC LIMIT 1',
            [$peerId, 'ringing', 'audio', 'video']
        );
    }

    public static function ringingForPeer(int $peerId): ?array
    {
        $maxAge = self::CALL_RING_TIMEOUT_SEC + 30;
        return self::fetchOne(
            'SELECT ' . self::SESSION_COLS . '
             FROM live_sessions WHERE peer_user_id = ? AND status = ? AND kind IN (?, ?)
               AND TIMESTAMPDIFF(SECOND, created_at, NOW()) < ?
             ORDER BY id DESC LIMIT 1',
            [$peerId, 'ringing', 'audio', 'video', $maxAge]
        );
    }

    public static function expireStaleRinging(): void
    {
        $sec = self::CALL_RING_TIMEOUT_SEC;
        self::execute(
            "UPDATE live_sessions SET status = ?, ended_at = NOW()
             WHERE status = ? AND kind IN (?, ?)
               AND TIMESTAMPDIFF(SECOND, created_at, NOW()) >= ?",
            ['missed', 'ringing', 'audio', 'video', $sec]
        );
    }

    /** Live activo del host (uno como máximo en la práctica). */
    public static function activeLiveForUser(int $userId): ?array
    {
        return self::fetchOne(
            'SELECT ' . self::SESSION_COLS . '
             FROM live_sessions WHERE host_user_id = ? AND kind = ? AND status = ?
             ORDER BY id DESC LIMIT 1',
            [$userId, 'live', 'active']
        );
    }

    /** Cierra lives activos del host (antes de iniciar otro). */
    public static function endActiveLivesForHost(int $hostId): void
    {
        self::execute(
            'UPDATE live_sessions SET status = ?, ended_at = NOW()
             WHERE host_user_id = ? AND kind = ? AND status = ?',
            ['ended', $hostId, 'live', 'active']
        );
    }

    /**
     * Lives activos: primero seguidos del viewer, luego el resto.
     * @return list<array>
     */
    public static function activeLives(int $viewerId, int $limit = 30): array
    {
        $limit = max(1, min(50, $limit));
        return self::fetchAll(
            'SELECT s.id, s.room_name, s.kind, s.host_user_id, s.peer_user_id, s.status, s.title,
                    s.description, s.hashtags, s.category, s.cover_url, s.live_mode,
                    s.likes_count, s.viewers_peak, s.gifts_total_cents, s.unique_viewers, s.join_count,
                    s.created_at, s.started_at, s.ended_at,
                    u.username, u.display_name, u.avatar_path, u.is_verified,
                    EXISTS (
                        SELECT 1 FROM follows f
                        WHERE f.follower_id = ? AND f.following_id = s.host_user_id
                    ) AS is_following
             FROM live_sessions s
             JOIN users u ON u.id = s.host_user_id AND u.status = \'active\'
             WHERE s.kind = \'live\' AND s.status = \'active\'
             ORDER BY is_following DESC, s.started_at DESC, s.id DESC
             LIMIT ' . $limit,
            [$viewerId]
        );
    }

    public static function bumpLikes(int $sessionId, int $by = 1): int
    {
        self::execute(
            'UPDATE live_sessions SET likes_count = likes_count + ? WHERE id = ? AND kind = ? AND status = ?',
            [max(1, $by), $sessionId, 'live', 'active']
        );
        return (int) self::fetchValue('SELECT likes_count FROM live_sessions WHERE id = ?', [$sessionId]);
    }

    public static function bumpViewersPeak(int $sessionId, int $current): void
    {
        self::execute(
            'UPDATE live_sessions SET viewers_peak = GREATEST(viewers_peak, ?) WHERE id = ?',
            [max(0, $current), $sessionId]
        );
    }

    public static function bumpJoinCount(int $sessionId, int $by = 1): void
    {
        self::execute(
            'UPDATE live_sessions SET join_count = join_count + ? WHERE id = ?',
            [max(1, $by), $sessionId]
        );
    }

    public static function bumpUniqueViewers(int $sessionId, int $by = 1): void
    {
        self::execute(
            'UPDATE live_sessions SET unique_viewers = unique_viewers + ? WHERE id = ?',
            [max(1, $by), $sessionId]
        );
    }

    public static function setGiftsTotal(int $sessionId, int $cents): void
    {
        self::execute(
            'UPDATE live_sessions SET gifts_total_cents = ? WHERE id = ?',
            [max(0, $cents), $sessionId]
        );
    }

    public static function addMessage(int $sessionId, int $userId, string $body, ?int $replyToId = null): int
    {
        if ($replyToId !== null) {
            $ok = (bool) self::fetchValue(
                'SELECT 1 FROM live_session_messages WHERE id = ? AND session_id = ? LIMIT 1',
                [$replyToId, $sessionId]
            );
            if (!$ok) {
                $replyToId = null;
            }
        }
        self::execute(
            'INSERT INTO live_session_messages (session_id, user_id, body, reply_to_id) VALUES (?, ?, ?, ?)',
            [$sessionId, $userId, $body, $replyToId]
        );
        return (int) self::db()->lastInsertId();
    }

    /** @return list<array> */
    public static function messages(int $sessionId, int $afterId = 0, int $limit = 50): array
    {
        $limit = max(1, min(100, $limit));
        return self::fetchAll(
            'SELECT m.id, m.session_id, m.user_id, m.body, m.reply_to_id, m.created_at,
                    u.username, u.display_name, u.avatar_path, u.is_verified
             FROM live_session_messages m
             JOIN users u ON u.id = m.user_id
             WHERE m.session_id = ?' . ($afterId > 0 ? ' AND m.id > ?' : '') . '
             ORDER BY m.id ASC
             LIMIT ' . $limit,
            $afterId > 0 ? [$sessionId, $afterId] : [$sessionId]
        );
    }

    /** Últimos N mensajes (para quien entra tarde). */
    public static function recentMessages(int $sessionId, int $limit = 40): array
    {
        $limit = max(1, min(100, $limit));
        $rows = self::fetchAll(
            'SELECT m.id, m.session_id, m.user_id, m.body, m.reply_to_id, m.created_at,
                    u.username, u.display_name, u.avatar_path, u.is_verified
             FROM live_session_messages m
             JOIN users u ON u.id = m.user_id
             WHERE m.session_id = ?
             ORDER BY m.id DESC
             LIMIT ' . $limit,
            [$sessionId]
        );
        return array_reverse($rows);
    }

    // -------------------------------------------------------------------------
    // Speakers (voice chat)
    // -------------------------------------------------------------------------

    /** @return list<array{user_id:int, status:string, username:string, display_name:string, avatar_path:?string, is_verified:int}> */
    public static function listSpeakers(int $sessionId): array
    {
        return self::fetchAll(
            "SELECT sp.user_id, sp.status, u.username, u.display_name, u.avatar_path, u.is_verified
             FROM live_session_speakers sp
             JOIN users u ON u.id = sp.user_id
             WHERE sp.session_id = ? AND sp.status <> 'removed'
             ORDER BY sp.status = 'active' DESC, sp.user_id ASC",
            [$sessionId]
        );
    }

    public static function speakerStatus(int $sessionId, int $userId): ?string
    {
        $status = self::fetchValue(
            'SELECT status FROM live_session_speakers WHERE session_id = ? AND user_id = ? LIMIT 1',
            [$sessionId, $userId]
        );
        return is_string($status) ? $status : null;
    }

    public static function countActiveSpeakers(int $sessionId): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM live_session_speakers WHERE session_id = ? AND status = 'active'",
            [$sessionId]
        );
    }

    public static function inviteSpeaker(int $sessionId, int $userId): void
    {
        self::execute(
            "INSERT INTO live_session_speakers (session_id, user_id, status) VALUES (?, ?, 'invited')
             ON DUPLICATE KEY UPDATE status = IF(status = 'removed', 'invited', status)",
            [$sessionId, $userId]
        );
    }

    public static function setSpeakerActive(int $sessionId, int $userId): void
    {
        self::execute(
            "UPDATE live_session_speakers SET status = 'active' WHERE session_id = ? AND user_id = ? AND status IN ('invited', 'active')",
            [$sessionId, $userId]
        );
    }

    public static function removeSpeaker(int $sessionId, int $userId): void
    {
        self::execute(
            "UPDATE live_session_speakers SET status = 'removed' WHERE session_id = ? AND user_id = ?",
            [$sessionId, $userId]
        );
    }
}