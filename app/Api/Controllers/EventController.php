<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\Event;
use Trevix\Models\Post;
use Trevix\Services\EventService;

/** Sección Eventos y respuestas «Asistiré» / «Me interesa». Los eventos se crean con POST /posts (event[...]). */
final class EventController extends ApiController
{
    /** GET /events?tab=upcoming|past&page= — publicaciones con evento visibles para quien mira. */
    public function index(): never
    {
        $past = Request::queryIn('tab', ['upcoming', 'past'], 'upcoming') === 'past';
        $result = Post::feed($this->uid(), Event::feedQuery($past) + ['page' => $this->pageNumber(), 'limit' => $this->limit('feed_page', 15)]);
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /** GET /events/{id} — la publicación del evento. */
    public function show(string $id): never
    {
        $event = Event::findRaw((int) $id);
        $post = $event !== null && $event['post_id'] !== null ? Post::findVisible((int) $event['post_id'], $this->uid()) : null;
        if ($post === null) {
            $this->notFound('Este evento no existe o ya no está disponible.');
        }
        Reply::ok(Present::post($post));
    }

    /** POST /events/{id}/respond {choice: going|interested|none} */
    public function respond(string $id): never
    {
        Reply::ok(EventService::respond($this->uid(), (int) $id, Input::str('choice')));
    }
}
