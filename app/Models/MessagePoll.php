<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Encuestas en mensajes de chat: pregunta + opciones en messages.poll (JSON) y votos en message_poll_votes.
 */
final class MessagePoll extends Model
{
    /** @return array{q:string, opts:list<string>}|null */
    public static function decode(?string $json): ?array
    {
        if ($json === null || $json === '') {
            return null;
        }
        $data = json_decode($json, true);
        if (!is_array($data)) {
            return null;
        }
        $q = trim((string) ($data['q'] ?? ''));
        $opts = array_values(array_filter(array_map(
            static fn ($o): string => mb_substr(trim((string) $o), 0, 40),
            (array) ($data['opts'] ?? [])
        ), static fn (string $o): bool => $o !== ''));
        if ($q === '' || count($opts) < 2) {
            return null;
        }
        return ['q' => mb_substr($q, 0, 120), 'opts' => array_slice($opts, 0, 6)];
    }

    /** @param list<string> $options */
    public static function encode(string $question, array $options): string
    {
        $opts = array_values(array_filter(array_map(
            static fn ($o): string => mb_substr(trim((string) $o), 0, 40),
            $options
        ), static fn (string $o): bool => $o !== ''));
        return json_encode(['q' => mb_substr(trim($question), 0, 120), 'opts' => array_slice($opts, 0, 6)], JSON_UNESCAPED_UNICODE) ?: '{}';
    }

    /**
     * Presentación para la API: question, options[{index,text,votes,percent}], total, viewer_vote.
     *
     * @param list<array> $messages filas con id y poll (JSON string o null)
     * @return array<int, array>
     */
    public static function forMessages(array $messages, int $viewerId): array
    {
        $ids = [];
        $decoded = [];
        foreach ($messages as $m) {
            $id = (int) ($m['id'] ?? 0);
            $poll = self::decode(is_string($m['poll'] ?? null) ? $m['poll'] : null);
            if ($id < 1 || $poll === null) {
                continue;
            }
            $ids[] = $id;
            $decoded[$id] = $poll;
        }
        if ($ids === []) {
            return [];
        }
        $counts = [];
        $mine = [];
        $rows = self::fetchAll(
            'SELECT message_id, option_index, user_id FROM message_poll_votes
             WHERE message_id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')',
            $ids
        );
        foreach ($rows as $r) {
            $mid = (int) $r['message_id'];
            $idx = (int) $r['option_index'];
            $counts[$mid][$idx] = ($counts[$mid][$idx] ?? 0) + 1;
            if ((int) $r['user_id'] === $viewerId) {
                $mine[$mid] = $idx;
            }
        }
        $out = [];
        foreach ($decoded as $mid => $poll) {
            $total = 0;
            $opts = [];
            foreach ($poll['opts'] as $i => $text) {
                $votes = (int) ($counts[$mid][$i] ?? 0);
                $total += $votes;
                $opts[] = ['index' => $i, 'text' => $text, 'votes' => $votes, 'percent' => 0];
            }
            foreach ($opts as &$o) {
                $o['percent'] = $total > 0 ? (int) round(($o['votes'] / $total) * 100) : 0;
            }
            unset($o);
            $out[$mid] = [
                'question'    => $poll['q'],
                'options'     => $opts,
                'total'       => $total,
                'viewer_vote' => $mine[$mid] ?? null,
            ];
        }
        return $out;
    }

    public static function vote(int $messageId, int $userId, int $optionIndex): void
    {
        self::execute(
            'INSERT INTO message_poll_votes (message_id, user_id, option_index) VALUES (?, ?, ?)
             ON DUPLICATE KEY UPDATE option_index = VALUES(option_index)',
            [$messageId, $userId, $optionIndex]
        );
    }
}
