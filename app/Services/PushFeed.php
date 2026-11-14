<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Api\Present;
use Trevix\Models\Conversation;
use Trevix\Models\Message;
use Trevix\Models\Notification;
use Trevix\Models\Push;

/**
 * Lo nuevo para los avisos del teléfono desde unos cursores, listo para mostrar (título, texto, foto y pantalla).
 * Lo usan GET me/push (Android lo consulta al despertar) y el envío por Firebase a iPhone, para que ambos digan
 * exactamente lo mismo. Cursores: n último aviso, m último mensaje, f última solicitud de seguimiento y r fecha de la
 * última reacción revisada.
 */
final class PushFeed
{
    private const DATE = '/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/';

    public static function validDate(string $value): bool
    {
        return preg_match(self::DATE, $value) === 1;
    }

    /**
     * @param array{n:int, m:int, f:int, r:string} $cursor  r = fecha desde la que se buscan reacciones
     * @return array{items: list<array>, cursor: array{n:int, m:int, f:int, r:string}}
     */
    public static function collect(int $uid, array $cursor): array
    {
        $since = (string) $cursor['r'];
        $next = [
            'n' => max(0, (int) $cursor['n']),
            'm' => max(0, (int) $cursor['m']),
            'f' => max(0, (int) $cursor['f']),
            'r' => Push::until(),
        ];
        $items = [];

        foreach (Notification::unreadSince($uid, $next['n'], 20) as $n) {
            $next['n'] = max($next['n'], (int) $n['id']);
            $actor = $n['actor'] !== null ? Present::user($n['actor']) : null;
            $items[] = [
                'kind'       => 'activity',
                'key'        => 'n' . $n['id'],
                'id'         => (int) $n['id'],
                'type'       => $n['type'],
                'title'      => $actor['display_name'] ?? 'TREVIX',
                'text'       => self::sentence(t((string) $n['text'])) . ($n['excerpt'] !== null ? ' «' . $n['excerpt'] . '»' : ''),
                'avatar_url' => $actor['avatar_url'] ?? null,
                'link'       => $n['link'],
                'at'         => Present::date($n['created_at']),
            ];
        }

        foreach (Push::followRequests($uid, $next['f'], 10) as $r) {
            $next['f'] = max($next['f'], (int) $r['id']);
            $user = Present::user(['id' => $r['user_id']] + $r);
            $items[] = [
                'kind'       => 'request',
                'key'        => 'f' . $r['id'],
                'id'         => (int) $r['id'],
                'title'      => $user['display_name'],
                'text'       => t('Solicitó seguirte.'),
                'avatar_url' => $user['avatar_url'],
                'link'       => 'notifications.php?tab=requests',
                'at'         => null,
            ];
        }

        // «Entregado» (doble check) solo cuando llegan mensajes nuevos: evita escribir en cada consulta.
        $messages = Push::messages($uid, $next['m'], 30);
        if ($messages !== []) {
            Conversation::markDelivered($uid);
        }
        foreach ($messages as $m) {
            $next['m'] = max($next['m'], (int) $m['id']);
            $items[] = self::messageItem($m);
        }

        foreach (Push::reactions($uid, $since, $next['r'], 20) as $r) {
            if ($r['private_at'] !== null) {
                $items[] = self::privateItem('r' . $r['message_id'] . '-' . $r['user_id'], (string) $r['created_at']);
                continue;
            }
            $user = Present::user(['id' => $r['user_id']] + $r);
            $items[] = [
                'kind'            => 'reaction',
                'key'             => 'r' . $r['message_id'] . '-' . $r['user_id'],
                'id'              => (int) $r['message_id'],
                'conversation_id' => (int) $r['conversation_id'],
                'title'           => trim((string) ($r['nickname'] ?? '')) !== '' ? (string) $r['nickname'] : $user['display_name'],
                'text'            => t('Reaccionó {emoji} a tu mensaje: «{summary}»', ['emoji' => $r['emoji'], 'summary' => Message::summary($r)]),
                'emoji'           => $r['emoji'],
                'avatar_url'      => $user['avatar_url'],
                'link'            => 'messages.php?c=' . (int) $r['conversation_id'],
                'e2ee'            => self::sealed($r, $uid),
                'at'              => Present::date($r['created_at']),
            ];
        }

        return ['items' => $items, 'cursor' => $next];
    }

    /**
     * Mensajes desde $fromId (incluido) listos para mostrar, sin tocar cursores ni el «entregado». Van dentro del aviso
     * de Firebase a Android para mostrarlos sin esperar a GET me/push (que después no los repite: misma clave).
     *
     * @return list<array>
     */
    public static function messagesFrom(int $uid, int $fromId, int $limit = 4): array
    {
        return array_map([self::class, 'messageItem'], Push::messages($uid, max(0, $fromId - 1), $limit));
    }

    /**
     * Aviso discreto de un chat privado: no dice quién escribió ni qué, no lleva foto ni «Responder» y abre la bandeja
     * (el chat se abre con el PIN). En iPhone todos se juntan en uno (apns-collapse-id «private»).
     */
    private static function privateItem(string $key, string $at): array
    {
        return [
            'kind'       => 'private',
            'key'        => $key,
            'title'      => 'TREVIX',
            'text'       => t('Tienes un mensaje nuevo.'),
            'avatar_url' => null,
            'link'       => 'messages.php',
            'at'         => Present::date($at),
        ];
    }

    private static function messageItem(array $m): array
    {
        if ($m['private_at'] !== null) {
            return self::privateItem('m' . $m['id'], (string) $m['created_at']);
        }
        $user = Present::user(['id' => $m['user_id']] + $m);
        $group = $m['conversation_type'] === 'group';
        return [
            'kind'            => 'message',
            'key'             => 'm' . $m['id'],
            'id'              => (int) $m['id'],
            'conversation_id' => (int) $m['conversation_id'],
            'title'           => $group
                ? (string) $m['group_title']
                : (trim((string) ($m['nickname'] ?? '')) !== '' ? (string) $m['nickname'] : $user['display_name']),
            'text'            => ($group ? $user['display_name'] . ': ' : '') . self::messageText($m),
            'prefix'          => $group ? $user['display_name'] . ': ' : '',
            'avatar_url'      => $group ? (Present::file($m['group_avatar']) ?? $user['avatar_url']) : $user['avatar_url'],
            'link'            => 'messages.php?c=' . (int) $m['conversation_id'],
            'encrypted'       => $m['e2ee_epoch'] !== null,
            'e2ee'            => self::sealed($m, (int) $m['sender_id']),
            'at'              => Present::date($m['created_at']),
        ];
    }

    /**
     * Texto cifrado de un mensaje normal para que el teléfono lo descifre con la clave del chat (el servidor no puede
     * leerlo). Sin él quedan los mensajes de visualización única, las respuestas a historias y notas y los borrados.
     */
    private static function sealed(array $m, int $senderId): ?array
    {
        if (($m['e2ee_epoch'] ?? null) === null || !empty($m['view_once']) || $m['deleted_at'] !== null
            || ($m['context'] ?? null) !== null || ($m['story_id'] ?? null) !== null) {
            return null;
        }
        return ['epoch' => (int) $m['e2ee_epoch'], 'ciphertext' => (string) $m['body'], 'sender_id' => $senderId];
    }

    private static function messageText(array $m): string
    {
        $summary = Message::summary($m);
        return match (true) {
            ($m['context'] ?? null) === 'story_reaction' => t('Reaccionó a tu historia: {text}', ['text' => $m['body']]),
            ($m['context'] ?? null) === 'note_reply'     => t('Respondió a tu nota: {text}', ['text' => $summary]),
            $m['story_id'] !== null                      => t('Respondió a tu historia: {text}', ['text' => $summary]),
            default                                      => $summary,
        };
    }

    private static function sentence(string $text): string
    {
        return mb_strtoupper(mb_substr($text, 0, 1)) . mb_substr($text, 1);
    }
}
