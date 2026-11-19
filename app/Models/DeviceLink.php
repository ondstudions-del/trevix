<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * VINCRIPTAR: el dispositivo nuevo (guest) genera un VINCODE; la cuenta autenticada
 * escanea o introduce el código, confirma, y el servidor emite un api_token de un uso.
 */
final class DeviceLink extends Model
{
    public const TTL_SECONDS = 90;

    /** Alfabeto Crockford (sin I, L, O, U) para código legible y anillo VINCODE. */
    public const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    public static function purgeExpired(): void
    {
        self::execute(
            "UPDATE device_link_challenges SET status = 'expired'
             WHERE status IN ('pending', 'claimed') AND expires_at <= NOW()"
        );
    }

    /**
     * Dispositivo nuevo: crea el reto sin dueño.
     *
     * @return array{id:int, code:string, expires_at:string, payload:string, seed:int, ttl:int}
     */
    public static function startGuest(string $deviceName, ?string $deviceType, ?string $ip): array
    {
        self::purgeExpired();
        $code = self::uniqueCode();
        self::execute(
            "INSERT INTO device_link_challenges
                (code, host_user_id, status, guest_device_name, guest_device_type, guest_ip, expires_at)
             VALUES (?, NULL, 'pending', ?, ?, ?, NOW() + INTERVAL ? SECOND)",
            [
                $code,
                mb_substr(trim($deviceName) !== '' ? trim($deviceName) : 'Dispositivo TREVIX', 0, 120),
                ApiToken::cleanDeviceType($deviceType),
                $ip,
                self::TTL_SECONDS,
            ]
        );
        $id = (int) self::db()->lastInsertId();
        $expires = (string) self::fetchValue('SELECT expires_at FROM device_link_challenges WHERE id = ?', [$id]);

        return [
            'id'         => $id,
            'code'       => $code,
            'expires_at' => $expires,
            'payload'    => self::payloadFor($code),
            'seed'       => self::seedFor($code),
            'ttl'        => self::TTL_SECONDS,
        ];
    }

    public static function payloadFor(string $code): string
    {
        return 'trevix://vincriptar/' . strtoupper($code);
    }

    public static function seedFor(string $code): int
    {
        $h = hash('crc32b', strtoupper($code), false);

        return (int) hexdec($h);
    }

    public static function findByCode(string $code): ?array
    {
        self::purgeExpired();
        $code = self::normalizeCode($code);
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

    /**
     * Cuenta autenticada escanea o introduce el código: reclama el reto.
     *
     * @return array|null fila claimed o null si falló
     */
    public static function scan(string $code, int $hostUserId): ?array
    {
        self::purgeExpired();
        $code = self::normalizeCode($code);
        $row = self::findByCode($code);
        if ($row === null || $row['status'] !== 'pending') {
            return null;
        }
        $ok = self::execute(
            "UPDATE device_link_challenges
             SET status = 'claimed', host_user_id = ?, claimed_at = NOW()
             WHERE id = ? AND status = 'pending' AND host_user_id IS NULL AND expires_at > NOW()",
            [$hostUserId, $row['id']]
        ) === 1;

        return $ok ? self::findForHost((int) $row['id'], $hostUserId) : null;
    }

    public static function approve(int $id, int $tokenId, string $tokenPlain): bool
    {
        return self::execute(
            "UPDATE device_link_challenges
             SET status = 'approved', token_id = ?, token_plain = ?, approved_at = NOW()
             WHERE id = ? AND status = 'claimed' AND expires_at > NOW()",
            [$tokenId, $tokenPlain, $id]
        ) === 1;
    }

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

    /** El solicitante cancela su propio reto pendiente (sin host aún). */
    public static function cancelByGuest(int $id, string $code): void
    {
        $code = self::normalizeCode($code);
        self::execute(
            "UPDATE device_link_challenges SET status = 'cancelled'
             WHERE id = ? AND code = ? AND status = 'pending' AND host_user_id IS NULL",
            [$id, $code]
        );
    }

    public static function normalizeCode(string $code): string
    {
        $code = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $code) ?? '');
        // Alias Crockford: O→0, I/L→1, U→V
        $code = strtr($code, ['O' => '0', 'I' => '1', 'L' => '1', 'U' => 'V']);

        return $code;
    }

    private static function uniqueCode(): string
    {
        $alphabet = self::ALPHABET;
        $len = strlen($alphabet);
        for ($attempt = 0; $attempt < 16; $attempt++) {
            $code = '';
            for ($i = 0; $i < 8; $i++) {
                $code .= $alphabet[random_int(0, $len - 1)];
            }
            if (self::fetchValue('SELECT 1 FROM device_link_challenges WHERE code = ? LIMIT 1', [$code]) === false) {
                return $code;
            }
        }

        return strtoupper(substr(bin2hex(random_bytes(5)), 0, 8));
    }

    private static function normalize(array $row): array
    {
        $row['id'] = (int) $row['id'];
        $row['host_user_id'] = $row['host_user_id'] !== null ? (int) $row['host_user_id'] : null;
        $row['token_id'] = $row['token_id'] !== null ? (int) $row['token_id'] : null;

        return $row;
    }
}
