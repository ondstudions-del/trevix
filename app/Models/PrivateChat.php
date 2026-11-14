<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Password;

/** PIN de los chats privados de cada persona (solo el hash). */
final class PrivateChat extends Model
{
    public static function pinHash(int $userId): ?string
    {
        $hash = self::fetchValue('SELECT pin_hash FROM private_chat_pins WHERE user_id = ?', [$userId]);
        return $hash !== false && $hash !== null ? (string) $hash : null;
    }

    public static function hasPin(int $userId): bool
    {
        return self::pinHash($userId) !== null;
    }

    public static function verify(int $userId, string $pin): bool
    {
        $hash = self::pinHash($userId);
        return $hash !== null && Password::verify($pin, $hash);
    }

    /** Crea o reemplaza el PIN (el hash nuevo invalida los desbloqueos firmados con el anterior). */
    public static function setPin(int $userId, string $pin): void
    {
        self::execute(
            'INSERT INTO private_chat_pins (user_id, pin_hash) VALUES (?, ?) ON DUPLICATE KEY UPDATE pin_hash = VALUES(pin_hash)',
            [$userId, Password::hash($pin)]
        );
    }

    public static function deletePin(int $userId): void
    {
        self::execute('DELETE FROM private_chat_pins WHERE user_id = ?', [$userId]);
    }
}
