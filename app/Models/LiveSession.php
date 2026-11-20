<?php
declare(strict_types=1);

namespace Trevix\Models;

final class LiveSession extends Model
{
    public const KINDS = ['audio', 'video', 'live'];

    public static function find(int $id): ?array
    {
        return self::fetchOne(
            'SELECT id, room_name, kind, host_user_id, peer_user_id, status, title, created_at, started_at, ended_at
             FROM live_sessions WHERE id = ?',
            [$id]
        );
    }

    public static function insert(
        string $roomName,
        string $kind,
        int $hostId,
        ?int $peerId,
        string $status,
        ?string $title,
    ): int {
        self::execute(
            'INSERT INTO live_sessions (room_name, kind, host_user_id, peer_user_id, status, title) VALUES (?, ?, ?, ?, ?, ?)',
            [$roomName, $kind, $hostId, $peerId, $status, $title]
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
        return self::fetchOne(
            'SELECT id, room_name, kind, host_user_id, peer_user_id, status, title, created_at, started_at, ended_at
             FROM live_sessions WHERE peer_user_id = ? AND status = ? AND kind IN (?, ?)
               AND created_at > DATE_SUB(UTC_TIMESTAMP(), INTERVAL 2 MINUTE)
             ORDER BY id DESC LIMIT 1',
            [$peerId, 'ringing', 'audio', 'video']
        );
    }

    public static function expireStaleRinging(): void
    {
        self::execute(
            'UPDATE live_sessions SET status = ?, ended_at = UTC_TIMESTAMP()
             WHERE status = ? AND kind IN (?, ?) AND created_at <= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 2 MINUTE)',
            ['missed', 'ringing', 'audio', 'video']
        );
    }
}