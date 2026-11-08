<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Event;
use Trevix\Models\Post;
use Trevix\Services\EventService;

/** Sección Eventos (próximos y pasados), enlace directo a un evento y respuestas «Asistiré» / «Me interesa». */
final class EventController extends Controller
{
    public const TABS = ['upcoming' => 'Próximos', 'past' => 'Pasados'];

    /** events.php?tab=upcoming|past */
    public function index(): void
    {
        Authenticate::handle();
        $tab = Request::queryIn('tab', array_keys(self::TABS), 'upcoming');
        $endText = $tab === 'upcoming' ? 'No hay más eventos próximos.' : 'No hay más eventos pasados.';

        $list = ['posts' => [], 'nextUrl' => null];
        if (!$this->isPreview()) {
            $paging = $this->paging();
            $result = Post::feed((int) $this->viewer()['id'], Event::feedQuery($tab === 'past') + ['page' => $paging['page'], 'limit' => $paging['limit']]);
            $list = $this->listData($result, 'events.php', ['tab' => $tab === 'upcoming' ? null : $tab]);
        }
        if ($this->isPartial()) {
            $this->renderList($list, $endText);
        }

        $this->render('pages/events', [
            'title'     => 'Eventos · TREVIX',
            'activeNav' => 'events',
            'tab'       => $tab,
            'tabs'      => self::TABS,
            'list'      => $list,
            'endText'   => $endText,
        ]);
    }

    /** event.php?id= : un evento vive en su publicación. */
    public function show(): void
    {
        Authenticate::handle();
        $event = Event::findRaw((int) Request::query('id'));
        if ($event === null || $event['post_id'] === null) {
            Response::abort(404, 'Este evento no existe o ya no está disponible.');
        }
        Response::redirect(url('post.php', ['id' => (int) $event['post_id']]));
    }

    /** POST api/events.php {event_id, choice: going|interested|none} */
    public function respond(): void
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $eventId = (int) Request::text('event_id');
        $choice = Request::text('choice');
        $result = $this->attempt(static fn () => EventService::respond((int) $user['id'], $eventId, $choice), url('events.php'));
        if (Request::wantsJson()) {
            Response::json(['ok' => true] + $result);
        }
        $this->redirectBack(url('event.php', ['id' => $eventId]));
    }
}
