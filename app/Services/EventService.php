<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Core\ActionError;
use Trevix\Models\Event;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;

/** «Asistiré» y «Me interesa» en eventos (compartido por la web y la API). */
final class EventService
{
    /**
     * Guarda la respuesta ('going' | 'interested') o la retira ('none').
     * Solo responde quien puede ver la publicación del evento; los eventos pasados ya no admiten respuestas.
     *
     * @return array{going_count:int, interested_count:int, viewer_response:?string}
     */
    public static function respond(int $uid, int $eventId, string $choice): array
    {
        if ($choice !== 'none' && !isset(Event::RESPONSES[$choice])) {
            throw new ActionError('Elige «Asistiré» o «Me interesa».');
        }
        $rateKey = 'user:' . $uid;
        Guard::rateLimit('interaction', $rateKey, 'Vas demasiado rápido. Espera un momento.');

        $event = $eventId > 0 ? Event::findRaw($eventId) : null;
        $post = $event !== null && $event['post_id'] !== null ? Post::findVisible((int) $event['post_id'], $uid) : null;
        if ($post === null) {
            throw new ActionError('Este evento ya no está disponible.', 404);
        }
        if (strtotime((string) ($event['ends_at'] ?? $event['starts_at'])) < time()) {
            throw new ActionError('Este evento ya terminó.');
        }

        RateLimit::hit('interaction', $rateKey);
        $status = $choice === 'none' ? null : $choice;
        $before = Event::respond($eventId, $uid, $status);

        $ownerId = (int) $event['user_id'];
        $postId = (int) $event['post_id'];
        if ($status === 'going' && $before !== 'going') {
            Notification::notify($ownerId, $uid, 'event_going', $postId);
        } elseif ($before === 'going' && $status !== 'going') {
            Notification::remove($ownerId, $uid, 'event_going', $postId);
        }
        return Event::counts($eventId, $uid);
    }
}
