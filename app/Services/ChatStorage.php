<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Database;
use Trevix\Models\Message;
use Trevix\Models\RateLimit;

/**
 * Almacenamiento del chat en el servidor: cuánto ocupan los archivos que enviaste (fotos, notas de voz y archivos
 * cifrados) y «Eliminar almacenamiento del chat», que borra tus archivos enviados de más de 30 o 90 días. Los
 * mensajes se quedan; donde estaba el archivo se muestra «Archivo eliminado». La caché del teléfono la limpia la app.
 */
final class ChatStorage
{
    /** Completa el tamaño de los archivos antiguos que no lo tenían guardado. */
    private static function backfill(string $where, array $params): void
    {
        $pdo = Database::connection();
        $select = $pdo->prepare("SELECT id, media_path FROM messages WHERE media_path IS NOT NULL AND media_size IS NULL AND $where LIMIT 300");
        $select->execute($params);
        $update = $pdo->prepare('UPDATE messages SET media_size = ? WHERE id = ?');
        foreach ($select->fetchAll() as $row) {
            $file = BASE_PATH . '/' . $row['media_path'];
            $update->execute([is_file($file) ? (int) filesize($file) : 0, (int) $row['id']]);
        }
    }

    /** Resumen de tus archivos enviados: total, de más de 30 y 90 días, y por conversación. */
    public static function mine(int $uid): array
    {
        self::backfill('sender_id = ?', [$uid]);
        $pdo = Database::connection();
        $totals = $pdo->prepare(
            "SELECT COUNT(*) AS files, COALESCE(SUM(media_size), 0) AS bytes,
                    COALESCE(SUM(created_at < NOW() - INTERVAL 30 DAY), 0) AS files_30,
                    COALESCE(SUM(IF(created_at < NOW() - INTERVAL 30 DAY, media_size, 0)), 0) AS bytes_30,
                    COALESCE(SUM(created_at < NOW() - INTERVAL 90 DAY), 0) AS files_90,
                    COALESCE(SUM(IF(created_at < NOW() - INTERVAL 90 DAY, media_size, 0)), 0) AS bytes_90
             FROM messages WHERE sender_id = ? AND media_path IS NOT NULL AND deleted_at IS NULL"
        );
        $totals->execute([$uid]);
        $t = $totals->fetch() ?: [];
        $byChat = $pdo->prepare(
            "SELECT m.conversation_id, COUNT(*) AS files, COALESCE(SUM(m.media_size), 0) AS bytes,
                    c.type, c.title, (SELECT u.display_name FROM conversation_participants op JOIN users u ON u.id = op.user_id
                      WHERE op.conversation_id = c.id AND op.user_id <> ? LIMIT 1) AS partner
             FROM messages m JOIN conversations c ON c.id = m.conversation_id
             JOIN conversation_participants cp ON cp.conversation_id = c.id AND cp.user_id = ? AND cp.left_at IS NULL AND cp.private_at IS NULL
             WHERE m.sender_id = ? AND m.media_path IS NOT NULL AND m.deleted_at IS NULL
             GROUP BY m.conversation_id ORDER BY bytes DESC LIMIT 50"
        );
        $byChat->execute([$uid, $uid, $uid]);
        return [
            'files'   => (int) ($t['files'] ?? 0),
            'bytes'   => (int) ($t['bytes'] ?? 0),
            'older'   => [
                ['days' => 30, 'files' => (int) ($t['files_30'] ?? 0), 'bytes' => (int) ($t['bytes_30'] ?? 0)],
                ['days' => 90, 'files' => (int) ($t['files_90'] ?? 0), 'bytes' => (int) ($t['bytes_90'] ?? 0)],
            ],
            'conversations' => array_map(static fn (array $r): array => [
                'conversation_id' => (int) $r['conversation_id'],
                'title'           => $r['type'] === 'group' ? (string) $r['title'] : (string) ($r['partner'] ?? t('Cuenta no disponible')),
                'type'            => (string) $r['type'],
                'files'           => (int) $r['files'],
                'bytes'           => (int) $r['bytes'],
            ], $byChat->fetchAll()),
        ];
    }

    /**
     * Borra tus archivos enviados de más de $days días (en una conversación o en todas). Devuelve cuántos y cuánto.
     *
     * @return array{files:int, bytes:int}
     */
    public static function clean(int $uid, int $days, ?int $conversationId): array
    {
        if (!in_array($days, array_map('intval', (array) Config::get('app.chat.storage_clean_days', [30, 90])), true)) {
            throw ActionError::field('older_than_days', 'Elige 30 o 90 días.');
        }
        $key = 'user:' . $uid;
        Guard::rateLimit('chat_storage', $key, 'Ya limpiaste el almacenamiento varias veces. Espera un rato.');
        RateLimit::hit('chat_storage', $key);
        $sql = 'SELECT id, media_path, COALESCE(media_size, 0) AS media_size FROM messages
                WHERE sender_id = ? AND media_path IS NOT NULL AND deleted_at IS NULL AND created_at < NOW() - INTERVAL ? DAY';
        $params = [$uid, $days];
        if ($conversationId !== null) {
            $sql .= ' AND conversation_id = ?';
            $params[] = $conversationId;
        }
        $select = Database::connection()->prepare($sql . ' LIMIT 2000');
        $select->execute($params);
        $files = 0;
        $bytes = 0;
        foreach ($select->fetchAll() as $row) {
            Message::clearMedia((int) $row['id'], (string) $row['media_path']);
            $files++;
            $bytes += (int) $row['media_size'];
        }
        return ['files' => $files, 'bytes' => $bytes];
    }

    /** Almacenamiento de una conversación (todos los participantes): por tipo y por persona. */
    public static function conversation(int $conversationId): array
    {
        self::backfill('conversation_id = ?', [$conversationId]);
        $pdo = Database::connection();
        $kinds = $pdo->prepare(
            "SELECT CASE WHEN e2ee_epoch IS NOT NULL THEN 'encrypted' WHEN media_mime LIKE 'audio/%' THEN 'voice'
                         WHEN media_mime LIKE 'video/%' THEN 'video' ELSE 'photo' END AS kind,
                    COUNT(*) AS files, COALESCE(SUM(media_size), 0) AS bytes
             FROM messages WHERE conversation_id = ? AND media_path IS NOT NULL AND deleted_at IS NULL GROUP BY kind"
        );
        $kinds->execute([$conversationId]);
        $people = $pdo->prepare(
            "SELECT u.id, u.username, u.display_name, u.avatar_path, u.is_verified, COUNT(*) AS files, COALESCE(SUM(m.media_size), 0) AS bytes
             FROM messages m JOIN users u ON u.id = m.sender_id
             WHERE m.conversation_id = ? AND m.media_path IS NOT NULL AND m.deleted_at IS NULL
             GROUP BY u.id ORDER BY bytes DESC LIMIT 20"
        );
        $people->execute([$conversationId]);
        $labels = ['photo' => 'Fotos', 'video' => 'Videos', 'voice' => 'Notas de voz', 'encrypted' => 'Archivos cifrados'];
        $byKind = array_map(static fn (array $r): array => [
            'kind'  => (string) $r['kind'],
            'label' => t($labels[$r['kind']] ?? 'Archivos'),
            'files' => (int) $r['files'],
            'bytes' => (int) $r['bytes'],
        ], $kinds->fetchAll());
        return [
            'files'   => array_sum(array_column($byKind, 'files')),
            'bytes'   => array_sum(array_column($byKind, 'bytes')),
            'kinds'   => $byKind,
            'people'  => $people->fetchAll(),
        ];
    }
}
