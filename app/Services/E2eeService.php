<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Database;
use Trevix\Models\Conversation;
use Trevix\Models\E2ee;
use Trevix\Models\RateLimit;

/**
 * Claves del cifrado de extremo a extremo (las usa la app; la web no cifra).
 *
 * - La app genera un par X25519 por cuenta y sube la clave pública. La privada se respalda cifrada con una clave
 *   derivada del PIN de 6 dígitos (PBKDF2 + HKDF en el teléfono); del PIN sale también una prueba («auth») que el
 *   servidor guarda con password_hash para entregar la copia solo a quien sabe el PIN, con intentos limitados.
 * - Cada chat tiene una clave por época, que la app de quien escribe cifra para cada participante.
 */
final class E2eeService
{
    /** Clave pública X25519 (32 bytes) en base64. */
    private static function publicKey(string $value, string $field): string
    {
        $value = trim($value);
        $raw = base64_decode($value, true);
        if ($raw === false || strlen($raw) !== 32 || strlen($value) > 64) {
            throw ActionError::field($field, 'La clave pública no es válida.');
        }
        return $value;
    }

    /** base64 de entre $min y $max bytes. */
    private static function b64(string $value, string $field, int $min, int $max): string
    {
        $value = trim($value);
        $raw = base64_decode($value, true);
        if ($raw === false || strlen($raw) < $min || strlen($raw) > $max) {
            throw ActionError::field($field, 'Los datos del cifrado no son válidos.');
        }
        return $value;
    }

    /** @param array{blob?:mixed, salt?:mixed, auth?:mixed} $raw */
    private static function backup(array $raw): array
    {
        return [
            'blob'      => self::b64((string) ($raw['blob'] ?? ''), 'backup', 44, 300),
            'salt'      => self::b64((string) ($raw['salt'] ?? ''), 'backup', 16, 32),
            'auth_hash' => password_hash(self::b64((string) ($raw['auth'] ?? ''), 'backup', 32, 32), PASSWORD_DEFAULT),
        ];
    }

    private static function limit(int $uid): void
    {
        $key = 'user:' . $uid;
        Guard::rateLimit('e2ee_keys', $key, 'Cambiaste el cifrado demasiadas veces. Espera un rato.');
        RateLimit::hit('e2ee_keys', $key);
    }

    /** Estado del cifrado de la cuenta (la sal del PIN sirve para recuperar la clave en otro teléfono). */
    public static function status(int $uid): array
    {
        $key = E2ee::keyOf($uid);
        return [
            'configured' => $key !== null,
            'key_id'     => $key !== null ? (int) $key['key_id'] : null,
            'public_key' => $key['public_key'] ?? null,
            'has_backup' => $key !== null && $key['backup_blob'] !== null,
            'salt'       => $key['backup_salt'] ?? null,
        ];
    }

    /**
     * Registra la clave de la cuenta (primera vez o clave nueva tras perder el PIN). Con clave nueva, los chats
     * cifrados avisan del cambio de código de seguridad y reparten una clave nueva al escribir.
     *
     * @param array{blob?:mixed, salt?:mixed, auth?:mixed}|null $backup
     */
    public static function register(int $uid, string $publicKey, ?array $backup): array
    {
        $publicKey = self::publicKey($publicKey, 'public_key');
        $backup = $backup !== null ? self::backup($backup) : null;
        self::limit($uid);
        Database::transaction(static function () use ($uid, $publicKey, $backup): void {
            [, $changed] = E2ee::saveKey($uid, $publicKey, $backup);
            if ($changed) {
                foreach (E2ee::encryptedConversationsOf($uid) as $conversationId) {
                    Conversation::notice($conversationId, $uid, 'key:' . $uid);
                }
            }
        });
        return self::status($uid);
    }

    /** Cambia el PIN (nueva copia cifrada de la misma clave). */
    public static function saveBackup(int $uid, array $backup): array
    {
        if (E2ee::keyOf($uid) === null) {
            throw new ActionError('Primero configura el cifrado en la app.', 409);
        }
        $backup = self::backup($backup);
        self::limit($uid);
        E2ee::saveBackup($uid, $backup);
        return self::status($uid);
    }

    /** Devuelve la copia cifrada de la clave privada si la prueba del PIN es correcta (intentos limitados). */
    public static function recover(int $uid, string $auth): array
    {
        $key = E2ee::keyOf($uid);
        if ($key === null || $key['backup_auth'] === null) {
            throw new ActionError('Esta cuenta no tiene una copia de la clave con PIN.', 404);
        }
        $rateKey = 'user:' . $uid;
        Guard::rateLimit('e2ee_pin', $rateKey, 'Demasiados intentos con el PIN. Espera 15 minutos para volver a probar.');
        $auth = trim($auth);
        $raw = base64_decode($auth, true);
        if ($raw === false || strlen($raw) !== 32 || !password_verify($auth, (string) $key['backup_auth'])) {
            RateLimit::hit('e2ee_pin', $rateKey);
            throw ActionError::field('pin', 'El PIN no es correcto.', 403);
        }
        RateLimit::clear('e2ee_pin', $rateKey);
        return [
            'key_id'     => (int) $key['key_id'],
            'public_key' => (string) $key['public_key'],
            'blob'       => (string) $key['backup_blob'],
            'salt'       => (string) $key['backup_salt'],
        ];
    }

    /** Claves del chat para quien mira: época vigente, participantes con su clave y las claves cifradas para él. */
    public static function conversationKeys(int $uid, array $conversation): array
    {
        $conversationId = (int) $conversation['id'];
        $epoch = E2ee::epochOf($conversationId);
        return [
            'conversation_id' => $conversationId,
            'e2ee'            => (bool) $conversation['e2ee'] || $epoch > 0,
            'epoch'           => $epoch,
            'stale'           => E2ee::stale($conversationId, $epoch),
            'members'         => E2ee::members($conversationId),
            'wraps'           => E2ee::wrapsFor($conversationId, $uid),
        ];
    }

    /**
     * Crea una época nueva con la clave del chat cifrada para cada participante con clave (incluida quien la crea).
     * 409 si otra persona se adelantó o si la lista no coincide con los participantes actuales.
     *
     * @param list<mixed> $keys [{user_id, key_id, wrapped}]
     */
    public static function rotate(int $uid, array $conversation, int $epoch, array $keys): array
    {
        $conversationId = (int) $conversation['id'];
        $mine = E2ee::keyOf($uid);
        if ($mine === null) {
            throw new ActionError('Configura el cifrado en la app antes de escribir en este chat.', 409);
        }
        if ($conversation['type'] === 'direct' && (!$conversation['available'] || $conversation['blocked'])) {
            throw new ActionError('No puedes escribir en esta conversación.', 403);
        }
        $expected = [];
        foreach (E2ee::members($conversationId) as $member) {
            if ($member['public_key'] !== null) {
                $expected[$member['user_id']] = $member['key_id'];
            }
        }
        $clean = [];
        foreach ($keys as $key) {
            if (!is_array($key)) {
                continue;
            }
            $userId = (int) ($key['user_id'] ?? 0);
            $clean[$userId] = [
                'user_id' => $userId,
                'key_id'  => (int) ($key['key_id'] ?? 0),
                'wrapped' => self::b64((string) ($key['wrapped'] ?? ''), 'keys', 60, 180),
            ];
        }
        $matches = count($clean) === count($expected);
        foreach ($expected as $userId => $keyId) {
            if (!isset($clean[$userId]) || $clean[$userId]['key_id'] !== $keyId) {
                $matches = false;
            }
        }
        $current = E2ee::epochOf($conversationId);
        if (!$matches || $epoch !== $current + 1) {
            throw ActionError::field('epoch', 'Las claves del chat cambiaron. Vuelve a intentarlo.', 409);
        }
        self::limit($uid);
        $wasEncrypted = (bool) $conversation['e2ee'];
        $created = Database::transaction(static function () use ($conversationId, $epoch, $uid, $mine, $clean, $wasEncrypted): bool {
            if (!E2ee::createEpoch($conversationId, $epoch, $uid, (string) $mine['public_key'], array_values($clean))) {
                return false;
            }
            if (!$wasEncrypted) {
                Conversation::notice($conversationId, $uid, 'e2ee:on');
            }
            return true;
        });
        if (!$created) {
            throw ActionError::field('epoch', 'Otra persona actualizó las claves del chat. Vuelve a intentarlo.', 409);
        }
        return self::conversationKeys($uid, ['id' => $conversationId, 'e2ee' => true]);
    }
}
