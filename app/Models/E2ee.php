<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Cifrado de extremo a extremo. El servidor solo guarda:
 * - la clave pública X25519 de cada cuenta (user_keys) y la copia de la privada cifrada con el PIN;
 * - la clave de cada época de cada chat, cifrada para cada participante (conversation_keys).
 * Nunca ve las claves privadas ni el contenido de los mensajes. Una época vale mientras sus claves cubran
 * exactamente a los participantes actuales que tienen clave, con su clave vigente; si no, la app de quien escribe
 * crea una época nueva (POST /conversations/{id}/keys).
 */
final class E2ee extends Model
{
    public static function keyOf(int $userId): ?array
    {
        return self::fetchOne('SELECT * FROM user_keys WHERE user_id = ? LIMIT 1', [$userId]);
    }

    /**
     * Guarda la clave pública (y opcionalmente la copia con el PIN). Si cambia la clave, key_id sube.
     * Devuelve [fila, cambió la clave].
     *
     * @param array{blob:string, salt:string, auth_hash:string}|null $backup
     */
    public static function saveKey(int $userId, string $publicKey, ?array $backup): array
    {
        $current = self::keyOf($userId);
        if ($current === null) {
            self::execute(
                'INSERT INTO user_keys (user_id, key_id, public_key, backup_blob, backup_salt, backup_auth) VALUES (?, 1, ?, ?, ?, ?)',
                [$userId, $publicKey, $backup['blob'] ?? null, $backup['salt'] ?? null, $backup['auth_hash'] ?? null]
            );
            return [self::keyOf($userId), false];
        }
        $changed = !hash_equals((string) $current['public_key'], $publicKey);
        self::execute(
            'UPDATE user_keys SET public_key = ?, key_id = key_id + ?, backup_blob = ?, backup_salt = ?, backup_auth = ? WHERE user_id = ?',
            [
                $publicKey, $changed ? 1 : 0,
                $backup !== null ? $backup['blob'] : ($changed ? null : $current['backup_blob']),
                $backup !== null ? $backup['salt'] : ($changed ? null : $current['backup_salt']),
                $backup !== null ? $backup['auth_hash'] : ($changed ? null : $current['backup_auth']),
                $userId,
            ]
        );
        return [self::keyOf($userId), $changed];
    }

    /** @param array{blob:string, salt:string, auth_hash:string} $backup */
    public static function saveBackup(int $userId, array $backup): void
    {
        self::execute(
            'UPDATE user_keys SET backup_blob = ?, backup_salt = ?, backup_auth = ? WHERE user_id = ?',
            [$backup['blob'], $backup['salt'], $backup['auth_hash'], $userId]
        );
    }

    /** Época vigente de la clave del chat (0 = aún no está cifrado). */
    public static function epochOf(int $conversationId): int
    {
        return (int) self::fetchValue('SELECT key_epoch FROM conversations WHERE id = ?', [$conversationId]);
    }

    /** Participantes actuales con su clave (public_key null si aún no configuraron el cifrado). */
    public static function members(int $conversationId): array
    {
        return array_map(static fn (array $r): array => [
            'user_id'    => (int) $r['user_id'],
            'key_id'     => $r['key_id'] !== null ? (int) $r['key_id'] : null,
            'public_key' => $r['public_key'],
        ], self::fetchAll(
            'SELECT cp.user_id, k.key_id, k.public_key FROM conversation_participants cp
             LEFT JOIN user_keys k ON k.user_id = cp.user_id
             WHERE cp.conversation_id = ? AND cp.left_at IS NULL ORDER BY cp.user_id',
            [$conversationId]
        ));
    }

    /** La época ya no sirve: falta alguien con clave, alguien cambió de clave o la tiene quien ya no participa. */
    public static function stale(int $conversationId, int $epoch): bool
    {
        if ($epoch < 1) {
            return true;
        }
        $missing = (int) self::fetchValue(
            'SELECT COUNT(*) FROM conversation_participants cp
             JOIN user_keys k ON k.user_id = cp.user_id
             LEFT JOIN conversation_keys ck ON ck.conversation_id = cp.conversation_id AND ck.epoch = ? AND ck.user_id = cp.user_id
                  AND ck.user_key_id = k.key_id
             WHERE cp.conversation_id = ? AND cp.left_at IS NULL AND ck.user_id IS NULL',
            [$epoch, $conversationId]
        );
        if ($missing > 0) {
            return true;
        }
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM conversation_keys ck
             LEFT JOIN conversation_participants cp ON cp.conversation_id = ck.conversation_id AND cp.user_id = ck.user_id AND cp.left_at IS NULL
             WHERE ck.conversation_id = ? AND ck.epoch = ? AND cp.user_id IS NULL',
            [$conversationId, $epoch]
        ) > 0;
    }

    /** Claves del chat cifradas para esta persona, de todas las épocas (para leer los mensajes anteriores). */
    public static function wrapsFor(int $conversationId, int $userId): array
    {
        return array_map(static fn (array $r): array => [
            'epoch'          => (int) $r['epoch'],
            'key_id'         => (int) $r['user_key_id'],
            'wrapped'        => (string) $r['wrapped'],
            'wrapped_by'     => $r['wrapped_by'] !== null ? (int) $r['wrapped_by'] : null,
            'wrapper_public' => (string) $r['wrapper_public'],
        ], self::fetchAll(
            'SELECT epoch, user_key_id, wrapped, wrapped_by, wrapper_public FROM conversation_keys
             WHERE conversation_id = ? AND user_id = ? ORDER BY epoch DESC LIMIT 500',
            [$conversationId, $userId]
        ));
    }

    /**
     * Crea la época $epoch (debe ser la siguiente a la vigente). Devuelve false si otra persona se adelantó.
     * Debe llamarse dentro de una transacción.
     *
     * @param list<array{user_id:int, key_id:int, wrapped:string}> $keys
     */
    public static function createEpoch(int $conversationId, int $epoch, int $byUserId, string $wrapperPublic, array $keys): bool
    {
        $moved = self::execute(
            'UPDATE conversations SET key_epoch = ?, e2ee = 1 WHERE id = ? AND key_epoch = ?',
            [$epoch, $conversationId, $epoch - 1]
        );
        if ($moved !== 1) {
            return false;
        }
        foreach ($keys as $key) {
            self::execute(
                'INSERT INTO conversation_keys (conversation_id, epoch, user_id, user_key_id, wrapped, wrapped_by, wrapper_public)
                 VALUES (?, ?, ?, ?, ?, ?, ?)',
                [$conversationId, $epoch, $key['user_id'], $key['key_id'], $key['wrapped'], $byUserId, $wrapperPublic]
            );
        }
        return true;
    }

    /** Conversaciones cifradas en las que participa (para avisar del cambio de código de seguridad). */
    public static function encryptedConversationsOf(int $userId): array
    {
        return array_map('intval', array_column(self::fetchAll(
            'SELECT c.id FROM conversations c JOIN conversation_participants cp ON cp.conversation_id = c.id
             WHERE cp.user_id = ? AND cp.left_at IS NULL AND c.e2ee = 1',
            [$userId]
        ), 'id'));
    }
}
