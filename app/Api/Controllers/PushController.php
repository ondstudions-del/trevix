<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\Message;
use Trevix\Models\Notification;
use Trevix\Models\Push;

/**
 * Avisos del teléfono sin Firebase: la app de Android consulta aquí cada pocos segundos (en segundo plano) y muestra
 * lo nuevo como notificaciones del sistema. Cada elemento llega listo para mostrar (título, texto, foto y pantalla).
 */
final class PushController extends ApiController
{
    private const DATE = '/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/';

    /**
     * GET /me/push?n=&m=&f=&r= — n: último aviso, m: último mensaje, f: última solicitud, r: fecha de la última
     * reacción revisada. Sin cursores válidos solo devuelve los iniciales (no avisa de nada antiguo).
     */
    public function poll(): never
    {
        $uid = $this->uid();
        \Trevix\Models\Conversation::markDelivered($uid);
        $since = (string) Request::query('r');
        if (preg_match(self::DATE, $since) !== 1) {
            Reply::ok([], ['cursor' => Push::cursors($uid), 'uid' => $uid]);
        }
        $cursor = [
            'n' => max(0, (int) Request::query('n')),
            'm' => max(0, (int) Request::query('m')),
            'f' => max(0, (int) Request::query('f')),
            'r' => Push::until(),
        ];
        $items = [];

        foreach (Notification::unreadSince($uid, $cursor['n'], 20) as $n) {
            $cursor['n'] = max($cursor['n'], (int) $n['id']);
            $actor = $n['actor'] !== null ? Present::user($n['actor']) : null;
            $items[] = [
                'kind'       => 'activity',
                'key'        => 'n' . $n['id'],
                'id'         => (int) $n['id'],
                'type'       => $n['type'],
                'title'      => $actor['display_name'] ?? 'TREVIX',
                'text'       => self::sentence((string) $n['text']) . ($n['excerpt'] !== null ? ' «' . $n['excerpt'] . '»' : ''),
                'avatar_url' => $actor['avatar_url'] ?? null,
                'link'       => $n['link'],
                'at'         => Present::date($n['created_at']),
            ];
        }

        foreach (Push::followRequests($uid, $cursor['f'], 10) as $r) {
            $cursor['f'] = max($cursor['f'], (int) $r['id']);
            $user = Present::user(['id' => $r['user_id']] + $r);
            $items[] = [
                'kind'       => 'request',
                'key'        => 'f' . $r['id'],
                'id'         => (int) $r['id'],
                'title'      => $user['display_name'],
                'text'       => 'Solicitó seguirte.',
                'avatar_url' => $user['avatar_url'],
                'link'       => 'notifications.php?tab=requests',
                'at'         => null,
            ];
        }

        foreach (Push::messages($uid, $cursor['m'], 30) as $m) {
            $cursor['m'] = max($cursor['m'], (int) $m['id']);
            $user = Present::user(['id' => $m['user_id']] + $m);
            $group = $m['conversation_type'] === 'group';
            $items[] = [
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

        foreach (Push::reactions($uid, $since, $cursor['r'], 20) as $r) {
            $user = Present::user(['id' => $r['user_id']] + $r);
            $items[] = [
                'kind'            => 'reaction',
                'key'             => 'r' . $r['message_id'] . '-' . $r['user_id'],
                'id'              => (int) $r['message_id'],
                'conversation_id' => (int) $r['conversation_id'],
                'title'           => trim((string) ($r['nickname'] ?? '')) !== '' ? (string) $r['nickname'] : $user['display_name'],
                'text'            => 'Reaccionó ' . $r['emoji'] . ' a tu mensaje: «' . Message::summary($r) . '»',
                'emoji'           => $r['emoji'],
                'avatar_url'      => $user['avatar_url'],
                'link'            => 'messages.php?c=' . (int) $r['conversation_id'],
                'e2ee'            => self::sealed($r, $uid),
                'at'              => Present::date($r['created_at']),
            ];
        }

        Reply::ok($items, ['cursor' => $cursor, 'uid' => $uid]);
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
            ($m['context'] ?? null) === 'story_reaction' => 'Reaccionó a tu historia: ' . $m['body'],
            ($m['context'] ?? null) === 'note_reply'     => 'Respondió a tu nota: ' . $summary,
            $m['story_id'] !== null                      => 'Respondió a tu historia: ' . $summary,
            default                                      => $summary,
        };
    }

    private static function sentence(string $text): string
    {
        return mb_strtoupper(mb_substr($text, 0, 1)) . mb_substr($text, 1);
    }
}
