<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Retos de vinculación por QR / código: un dispositivo autenticado genera el código;
 * el otro lo reclama y el anfitrión aprueba para emitir un api_token.
 */
final class DeviceLink extends Model
{
    public const TTL_SECONDS = 180;

    public static function purgeExpired(): void
    {
        self::execute(
            "UPDATE device_link_challenges SET status = 'expired'
             WHERE status IN ('pending', 'claimed') AND expires_at <= NOW()"
        );
    }

    /** @return array{id:int, code:string, expires_at:string, payload:string} */
    public static function start(int $hostUserId): array
    {
        self::purgeExpired();
        self::execute(
            "UPDATE device_link_challenges SET status = 'cancelled'
             WHERE host_user_id = ? AND status IN ('pending', 'claimed')",
            [$hostUserId]
        );
        $code = self::uniqueCode();
        self::execute(
            "INSERT INTO device_link_challenges (code, host_user_id, status, expires_at)
             VALUES (?, ?, 'pending', NOW() + INTERVAL ? SECOND)",
            [$code, $hostUserId, self::TTL_SECONDS]
        );
        $id = (int) self::db()->lastInsertId();
        $expires = (string) self::fetchValue('SELECT expires_at FROM device_link_challenges WHERE id = ?', [$id]);
        return [
            'id'         => $id,
            'code'       => $code,
            'expires_at' => $expires,
            'payload'    => 'trevix://link/' . $code,
        ];
    }

    public static function findByCode(string $code): ?array
    {
        self::purgeExpired();
        $code = strtoupper(preg_replace('/[^A-Z0-9]/', '', $code) ?? '');
        if (strlen($code) < 6) {
            return null;
        }
        $row = self::fetchOne('SELECT * FROM device_link_challenges WHERE code = ? LIMIT 1', [$code]);
        return $row !== null ? self::normalize($row) : null;
    }

    public static function findForHost(int $id, int $hostUserId): ?array
    {
        self::purgeExpired();
        $row = self::fetchOne(
            'SELECT * FROM device_link_challenges WHERE id = ? AND host_user_id = ? LIMIT 1',
            [$id, $hostUserId]
        );
        return $row !== null ? self::normalize($row) : null;
    }

    public static function claim(int $id, string $deviceName, ?string $deviceType, ?string $ip): bool
    {
        return self::execute(
            "UPDATE device_link_challenges
             SET status = 'claimed', guest_device_name = ?, guest_device_type = ?, guest_ip = ?, claimed_at = NOW()
             WHERE id = ? AND status = 'pending' AND expires_at > NOW()",
            [mb_substr(trim($deviceName), 0, 120), ApiToken::cleanDeviceType($deviceType), $ip, $id]
        ) === 1;
    }

    /** Guarda el token emitido y marca approved. */
    public static function approve(int $id, int $tokenId, string $tokenPlain): bool
    {
        return self::execute(
            "UPDATE device_link_challenges
             SET status = 'approved', token_id = ?, token_plain = ?, approved_at = NOW()
             WHERE id = ? AND status = 'claimed' AND expires_at > NOW()",
            [$tokenId, $tokenPlain, $id]
        ) === 1;
    }

    /** El guest recoge el token una sola vez. */
    public static function takeToken(int $id): ?string
    {
        $row = self::fetchOne(
            "SELECT token_plain FROM device_link_challenges WHERE id = ? AND status = 'approved' LIMIT 1",
            [$id]
        );
        if ($row === null || ($row['token_plain'] ?? null) === null) {
            return null;
        }
        self::execute('UPDATE device_link_challenges SET token_plain = NULL WHERE id = ?', [$id]);
        return (string) $row['token_plain'];
    }

    public static function cancel(int $id, int $hostUserId): void
    {
        self::execute(
            "UPDATE device_link_challenges SET status = 'cancelled'
             WHERE id = ? AND host_user_id = ? AND status IN ('pending', 'claimed')",
            [$id, $hostUserId]
        );
    }

    private static function uniqueCode(): string
    {
        $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        for ($attempt = 0; $attempt < 12; $attempt++) {
            $code = '';
            for ($i = 0; $i < 8; $i++) {
                $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
            if (self::fetchValue('SELECT 1 FROM device_link_challenges WHERE code = ? LIMIT 1', [$code]) === false) {
                return $code;
            }
        }
        return strtoupper(bin2hex(random_bytes(4)));
    }

    private static function normalize(array $row): array
    {
        $row['id'] = (int) $row['id'];
        $row['host_user_id'] = (int) $row['host_user_id'];
        $row['token_id'] = $row['token_id'] !== null ? (int) $row['token_id'] : null;
        return $row;
    }
}
