<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Teléfonos que reciben avisos por Firebase Cloud Messaging. Cada token pertenece a un solo teléfono y a la sesión de
 * la API con la que se registró (token_id): al cerrar esa sesión, revocarla o cambiar la contraseña, el teléfono deja
 * de recibir avisos solo (ON DELETE CASCADE). Si otra cuenta inicia sesión en el mismo teléfono, el token pasa a ella.
 * En iPhone se guardan los cursores de GET me/push para no repetir un aviso ya entregado.
 */
final class PushDevice extends Model
{
    public const PLATFORMS = ['android', 'ios'];

    /**
     * Registra o renueva el token del teléfono para esta sesión (la app lo hace cada vez que abre). Los cursores
     * vuelven a lo más reciente: lo anterior ya lo vio con la app abierta. Devuelve el id del registro.
     */
    public static function register(int $userId, int $tokenId, string $platform, string $fcmToken, ?string $appVersion, string $locale, array $cursor): int
    {
        self::execute(
            'INSERT INTO push_devices (user_id, token_id, platform, fcm_token, app_version, locale, cursor_json, last_error, failures)
             VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 0)
             ON DUPLICATE KEY UPDATE
                 user_id = VALUES(user_id), token_id = VALUES(token_id), platform = VALUES(platform),
                 app_version = VALUES(app_version), locale = VALUES(locale), cursor_json = VALUES(cursor_json), updated_at = NOW()',
            [$userId, $tokenId, $platform, $fcmToken, $appVersion, $locale, json_encode($cursor)]
        );
        // Un teléfono que cambió de token deja el anterior de esta misma sesión.
        self::execute('DELETE FROM push_devices WHERE token_id = ? AND fcm_token <> ?', [$tokenId, $fcmToken]);
        return (int) self::fetchValue('SELECT id FROM push_devices WHERE fcm_token = ?', [$fcmToken]);
    }

    public static function find(int $id): ?array
    {
        return self::fetchOne('SELECT * FROM push_devices WHERE id = ?', [$id]);
    }

    public static function remove(int $userId, string $fcmToken): void
    {
        self::execute('DELETE FROM push_devices WHERE user_id = ? AND fcm_token = ?', [$userId, $fcmToken]);
    }

    /** @param list<int> $userIds */
    public static function forUsers(array $userIds): array
    {
        $userIds = array_values(array_unique(array_filter(array_map('intval', $userIds), static fn (int $id): bool => $id > 0)));
        if ($userIds === []) {
            return [];
        }
        return self::fetchAll(
            "SELECT d.id, d.user_id, d.platform, d.fcm_token, d.cursor_json, COALESCE(d.locale, u.locale) AS locale
             FROM push_devices d JOIN users u ON u.id = d.user_id AND u.status = 'active'
             WHERE d.user_id IN (" . implode(',', array_fill(0, count($userIds), '?')) . ')',
            $userIds
        );
    }

    /** Quienes siguen en la conversación y no la silenciaron, sin quien envió el mensaje. @return list<int> */
    public static function conversationRecipients(int $conversationId, int $senderId): array
    {
        return array_map('intval', array_column(self::fetchAll(
            'SELECT user_id FROM conversation_participants
             WHERE conversation_id = ? AND user_id <> ? AND left_at IS NULL AND is_muted = 0',
            [$conversationId, $senderId]
        ), 'user_id'));
    }

    /** Quienes enviaron estos mensajes. @return list<int> */
    public static function messageSenders(array $messageIds): array
    {
        $messageIds = array_values(array_filter(array_map('intval', $messageIds)));
        if ($messageIds === []) {
            return [];
        }
        return array_map('intval', array_column(self::fetchAll(
            'SELECT DISTINCT sender_id FROM messages WHERE id IN (' . implode(',', array_fill(0, count($messageIds), '?')) . ')',
            $messageIds
        ), 'sender_id'));
    }

    /** Teléfonos de un envío del panel, por tandas (después del id $afterId). $platform null = todos. */
    public static function batch(?string $platform, int $afterId, int $limit, ?int $userId = null): array
    {
        $where = ["u.status = 'active'", 'd.id > ?'];
        $params = [$afterId];
        if ($platform !== null) {
            $where[] = 'd.platform = ?';
            $params[] = $platform;
        }
        if ($userId !== null) {
            $where[] = 'd.user_id = ?';
            $params[] = $userId;
        }
        return self::fetchAll(
            'SELECT d.id, d.user_id, d.platform, d.fcm_token, COALESCE(d.locale, u.locale) AS locale FROM push_devices d JOIN users u ON u.id = d.user_id
             WHERE ' . implode(' AND ', $where) . ' ORDER BY d.id LIMIT ' . max(1, min(1000, $limit)),
            $params
        );
    }

    public static function count(?string $platform = null, ?int $userId = null): int
    {
        $where = ["u.status = 'active'"];
        $params = [];
        if ($platform !== null) {
            $where[] = 'd.platform = ?';
            $params[] = $platform;
        }
        if ($userId !== null) {
            $where[] = 'd.user_id = ?';
            $params[] = $userId;
        }
        return (int) self::fetchValue(
            'SELECT COUNT(*) FROM push_devices d JOIN users u ON u.id = d.user_id WHERE ' . implode(' AND ', $where),
            $params
        );
    }

    /** Resumen para el panel: teléfonos por plataforma y los que fallan. */
    public static function stats(): array
    {
        $row = self::fetchOne(
            "SELECT SUM(d.platform = 'android') AS android, SUM(d.platform = 'ios') AS ios,
                    SUM(d.last_error IS NOT NULL) AS failing, COUNT(DISTINCT d.user_id) AS users
             FROM push_devices d JOIN users u ON u.id = d.user_id AND u.status = 'active'"
        ) ?? [];
        return [
            'android' => (int) ($row['android'] ?? 0),
            'ios'     => (int) ($row['ios'] ?? 0),
            'failing' => (int) ($row['failing'] ?? 0),
            'users'   => (int) ($row['users'] ?? 0),
        ];
    }

    /**
     * Avanza los cursores de un iPhone solo si nadie los cambió desde que se leyeron ($old): si dos envíos coinciden,
     * solo uno manda los avisos y el otro no los repite.
     */
    public static function claimCursor(int $id, ?string $old, array $cursor): bool
    {
        return self::execute(
            'UPDATE push_devices SET cursor_json = ?, last_sent_at = NOW() WHERE id = ? AND cursor_json <=> ?',
            [json_encode($cursor), $id, $old]
        ) === 1;
    }

    /** @param list<int> $ids */
    public static function delete(array $ids): void
    {
        $ids = array_values(array_filter(array_map('intval', $ids)));
        if ($ids !== []) {
            self::execute('DELETE FROM push_devices WHERE id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')', $ids);
        }
    }

    /** Resultado de un envío: los que llegaron limpian su error; los que fallaron lo anotan. */
    public static function markResults(array $okIds, array $errors): void
    {
        $okIds = array_values(array_filter(array_map('intval', $okIds)));
        if ($okIds !== []) {
            self::execute(
                'UPDATE push_devices SET last_error = NULL, failures = 0, last_sent_at = NOW()
                 WHERE last_error IS NOT NULL AND id IN (' . implode(',', array_fill(0, count($okIds), '?')) . ')',
                $okIds
            );
        }
        foreach ($errors as $id => $code) {
            self::execute(
                'UPDATE push_devices SET last_error = ?, failures = LEAST(failures + 1, 1000) WHERE id = ?',
                [mb_substr((string) $code, 0, 40), (int) $id]
            );
        }
    }
}
