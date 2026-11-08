<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;

/**
 * Eventos: se crean junto con su publicación (posts.event_id), así aparecen en el inicio con las mismas reglas
 * de visibilidad. «Asistiré» y «Me interesa» son excluyentes: una respuesta por persona.
 */
final class Event extends Model
{
    public const RESPONSES = ['going' => 'Asistiré', 'interested' => 'Me interesa'];

    /** @param array{title:string, description:?string, place:string, starts_at:string, ends_at:?string, cover_path:?string} $data */
    public static function create(int $userId, array $data): int
    {
        self::execute(
            'INSERT INTO events (user_id, title, description, place, starts_at, ends_at, cover_path) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$userId, $data['title'], $data['description'], $data['place'], $data['starts_at'], $data['ends_at'], $data['cover_path']]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function findRaw(int $id): ?array
    {
        return self::fetchOne(
            'SELECT e.*, (SELECT p.id FROM posts p WHERE p.event_id = e.id ORDER BY p.id LIMIT 1) AS post_id FROM events e WHERE e.id = ? LIMIT 1',
            [$id]
        );
    }

    /**
     * Tarjetas de evento con la respuesta de quien mira.
     * @return array<int, array>
     */
    public static function cardsFor(array $ids, int $viewerId): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids))));
        if ($ids === []) {
            return [];
        }
        $marks = implode(',', array_fill(0, count($ids), '?'));
        $rows = self::fetchAll(
            "SELECT e.id, e.user_id, e.title, e.description, e.place, e.starts_at, e.ends_at, e.cover_path, e.going_count, e.interested_count,
                    (SELECT r.status FROM event_responses r WHERE r.event_id = e.id AND r.user_id = ?) AS viewer_response
             FROM events e WHERE e.id IN ($marks)",
            array_merge([$viewerId], $ids)
        );
        $out = [];
        foreach ($rows as $r) {
            $out[(int) $r['id']] = self::card($r);
        }
        return $out;
    }

    private static function card(array $r): array
    {
        $ends = $r['ends_at'] ?? null;
        return [
            'id'               => (int) $r['id'],
            'user_id'          => (int) $r['user_id'],
            'title'            => $r['title'],
            'description'      => (string) ($r['description'] ?? ''),
            'place'            => $r['place'],
            'starts_at'        => $r['starts_at'],
            'ends_at'          => $ends,
            'cover_path'       => $r['cover_path'],
            'going_count'      => (int) $r['going_count'],
            'interested_count' => (int) $r['interested_count'],
            'viewer_response'  => $r['viewer_response'] ?? null,
            'is_past'          => strtotime((string) ($ends ?? $r['starts_at'])) < time(),
        ];
    }

    /**
     * Guarda («going» / «interested») o retira (null) la respuesta y actualiza los contadores.
     * Devuelve la respuesta anterior.
     */
    public static function respond(int $eventId, int $userId, ?string $status): ?string
    {
        return Database::transaction(static function () use ($eventId, $userId, $status): ?string {
            $before = self::fetchValue('SELECT status FROM event_responses WHERE event_id = ? AND user_id = ? FOR UPDATE', [$eventId, $userId]);
            $before = $before === false ? null : (string) $before;
            if ($before === $status) {
                return $before;
            }
            if ($before !== null) {
                self::execute('DELETE FROM event_responses WHERE event_id = ? AND user_id = ?', [$eventId, $userId]);
                self::execute("UPDATE events SET {$before}_count = {$before}_count - ({$before}_count > 0) WHERE id = ?", [$eventId]);
            }
            if ($status !== null) {
                self::execute('INSERT INTO event_responses (event_id, user_id, status) VALUES (?, ?, ?)', [$eventId, $userId, $status]);
                self::execute("UPDATE events SET {$status}_count = {$status}_count + 1 WHERE id = ?", [$eventId]);
            }
            return $before;
        });
    }

    /** Contadores y respuesta actuales (tras responder). */
    public static function counts(int $eventId, int $userId): array
    {
        $card = self::cardsFor([$eventId], $userId)[$eventId] ?? null;
        return [
            'going_count'      => (int) ($card['going_count'] ?? 0),
            'interested_count' => (int) ($card['interested_count'] ?? 0),
            'viewer_response'  => $card['viewer_response'] ?? null,
        ];
    }

    /**
     * Consulta de Post::feed para la sección Eventos: próximos (el más cercano primero) o pasados (el más reciente primero).
     * La visibilidad la aplica Post::feed como en cualquier otro feed.
     */
    public static function feedQuery(bool $past): array
    {
        return [
            'join'    => 'JOIN events ev ON ev.id = p.event_id',
            'where'   => $past ? 'COALESCE(ev.ends_at, ev.starts_at) < NOW()' : 'COALESCE(ev.ends_at, ev.starts_at) >= NOW()',
            'order'   => 'custom',
            'orderBy' => $past ? 'ev.starts_at DESC, p.id DESC' : 'ev.starts_at ASC, p.id ASC',
        ];
    }

    /** @return list<string> portadas de los eventos de una cuenta (para borrarlas del disco al eliminarla). */
    public static function coverPathsByUser(int $userId): array
    {
        return array_map('strval', array_column(
            self::fetchAll('SELECT cover_path FROM events WHERE user_id = ? AND cover_path IS NOT NULL', [$userId]),
            'cover_path'
        ));
    }

    /** Descuenta las respuestas de una cuenta que se va a eliminar en los eventos de otras personas. */
    public static function releaseCountersForUser(int $userId): void
    {
        self::execute(
            "UPDATE events e JOIN event_responses r ON r.event_id = e.id AND r.user_id = ?
             SET e.going_count = e.going_count - (r.status = 'going' AND e.going_count > 0),
                 e.interested_count = e.interested_count - (r.status = 'interested' AND e.interested_count > 0)",
            [$userId]
        );
    }

    public static function delete(int $eventId): ?string
    {
        $cover = self::fetchValue('SELECT cover_path FROM events WHERE id = ?', [$eventId]);
        self::execute('DELETE FROM events WHERE id = ?', [$eventId]);
        return $cover === false || $cover === null ? null : (string) $cover;
    }
}
