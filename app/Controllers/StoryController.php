<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Conversation;
use Trevix\Models\Song;
use Trevix\Models\Story;
use Trevix\Models\User;
use Trevix\Services\MediaUpload;
use Trevix\Services\MessageService;
use Trevix\Services\StoryService;

/** Visor de historias (stories.php), creación (stories.php?new=1) y api/stories.php. */
final class StoryController extends Controller
{
    public function index(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Las historias se publican desde el formulario de creación.');
        }

        if (Request::query('new') === '1') {
            $this->renderCreate();
            return;
        }

        $viewer = $this->viewer();
        $username = mb_strtolower(Request::query('u'));

        if ($this->isPreview()) {
            $groups = DemoData::stories();
        } else {
            $uid = (int) $viewer['id'];
            Story::purgeExpired(50);
            $tray = Story::tray($uid);
            $trayIds = array_map(static fn (array $g) => (int) $g['user']['id'], $tray);
            $trayNames = array_map(static fn (array $g) => $g['user']['username'], $tray);

            if ($username === '' || in_array($username, $trayNames, true)) {
                $groups = Story::groupsFor($trayIds, $uid);
            } else {
                // Cuenta que no está en la barra (por ejemplo, abierta desde su perfil): solo sus historias.
                $author = preg_match('/^[a-z0-9_.]{3,30}$/', $username) ? User::findByUsername($username) : null;
                $groups = $author !== null ? Story::groupsFor([(int) $author['id']], $uid) : [];
            }
            foreach ($groups as &$group) {
                $group['own'] = (int) $group['user']['id'] === $uid;
                $group['replyBlocked'] = $group['own'] ? null : Conversation::cannotMessage(
                    $uid,
                    $group['user'],
                    Conversation::findDirectId($uid, (int) $group['user']['id'])
                );
            }
            unset($group);
        }

        $startIndex = 0;
        foreach ($groups as $i => $group) {
            if ($group['user']['username'] === $username) {
                $startIndex = $i;
                break;
            }
        }
        if ($username === '' && !$this->isPreview()) {
            // Sin cuenta elegida: la primera con historias sin ver (las propias van primero).
            foreach ($groups as $i => $group) {
                if (!$group['own'] && array_filter($group['items'], static fn (array $item) => !$item['seen'])) {
                    $startIndex = $i;
                    break;
                }
            }
        }

        $this->render('pages/stories', [
            'title'      => 'Historias · TREVIX',
            'activeNav'  => 'home',
            'groups'     => $groups,
            'startIndex' => $startIndex,
            'exitUrl'    => $this->exitUrl(),
            'replyMax'   => (int) Config::get('app.limits.message_body', 2000),
        ], 'layouts/immersive');
    }

    /** api/stories.php: GET action=viewers | POST action = create | view | delete | reply. */
    public function api(): void
    {
        $user = $this->requireUser();
        $uid = (int) $user['id'];

        if (!Request::isPost()) {
            if (Request::query('action') !== 'viewers') {
                Response::json(['ok' => false, 'error' => 'Acción no válida.'], 400);
            }
            $this->viewers($uid);
        }

        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === []) {
            $this->fail('El archivo supera el tamaño que acepta el servidor.', 413, url('stories.php', ['new' => 1]));
        }
        VerifyCsrf::handle();

        match (Request::text('action')) {
            'create' => $this->create($user),
            'view'   => $this->view($uid),
            'delete' => $this->destroy($uid, (string) $user['username']),
            'reply'  => $this->reply($user),
            default  => $this->fail('Acción no válida.', 400, url('feed.php')),
        };
    }

    // -------------------------------------------------------------------------

    private function create(array $user): never
    {
        $storyId = $this->attempt(static fn () => StoryService::create(
            $user,
            Request::text('type') === 'text' ? 'text' : 'media',
            Request::text('text', false),
            Request::text('caption', false),
            Request::text('background'),
            MediaUpload::collect('media'),
            (int) Request::text('song_id'),
            (int) Request::text('song_start')
        ), url('stories.php', ['new' => 1]));

        $url = url('stories.php', ['u' => (string) $user['username']]);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'id' => $storyId, 'url' => $url], 201);
        }
        Session::flash('success', 'Tu historia se publicó. Estará visible durante 24 horas.');
        Response::redirect($url);
    }

    private function view(int $uid): never
    {
        $story = Story::findVisible((int) Request::text('story_id'), $uid);
        if ($story === null) {
            Response::json(['ok' => false, 'error' => 'Esta historia ya no está disponible.'], 404);
        }
        Response::json(['ok' => true, 'new' => Story::markViewed($story, $uid)]);
    }

    private function viewers(int $uid): never
    {
        $story = Story::findOwn((int) Request::query('id'), $uid);
        if ($story === null) {
            Response::json(['ok' => false, 'error' => 'Solo puedes ver quién vio tus propias historias.'], 404);
        }
        $viewers = array_map(static fn (array $v): array => [
            'username'     => $v['username'],
            'display_name' => $v['display_name'],
            'avatar'       => avatar($v, 'sm'),
            'url'          => profile_url($v),
            'viewed'       => time_ago((string) $v['viewed_at']),
        ], Story::viewers((int) $story['id']));
        Response::json(['ok' => true, 'count' => (int) $story['views_count'], 'viewers' => $viewers]);
    }

    private function destroy(int $uid, string $username): never
    {
        $remaining = $this->attempt(static fn () => StoryService::delete($uid, (int) Request::text('story_id')), url('feed.php'));
        $next = $remaining ? url('stories.php', ['u' => $username]) : url('feed.php');
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'remaining' => $remaining, 'url' => $next]);
        }
        Session::flash('success', 'Eliminaste la historia.');
        Response::redirect($next);
    }

    /** Responder a una historia envía un mensaje privado a su autor, con las mismas reglas que el chat. */
    private function reply(array $user): never
    {
        $result = $this->attempt(
            static fn () => MessageService::replyToStory($user, (int) Request::text('story_id'), Request::text('body', false)),
            url('stories.php')
        );
        $story = $result['story'];

        $chat = url('messages.php', ['c' => $result['conversation_id']]);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'conversation' => $chat]);
        }
        Session::flash('success', 'Enviaste tu respuesta a @' . $story['username'] . '.');
        Response::redirect(url('stories.php', ['u' => $story['username']]));
    }

    private function renderCreate(): void
    {
        // «Usar en historia» desde la biblioteca de música llega con ?song=ID.
        $songId = (int) Request::query('song');
        $viewer = $this->viewer();
        $song = $songId > 0 && !$this->isPreview() && $viewer !== null ? Song::findPublished($songId, (int) $viewer['id']) : null;

        $this->render('pages/story-new', [
            'title'       => 'Nueva historia · TREVIX',
            'activeNav'   => 'home',
            'backgrounds' => Story::BACKGROUNDS,
            'exitUrl'     => $this->exitUrl(),
            'song'        => $song !== null ? $song + ['start' => 0] : null,
            'limits'      => [
                'text'         => (int) Config::get('app.limits.story_text', 300),
                'caption'      => (int) Config::get('app.limits.story_caption', 200),
                'videoBytes'   => (int) Config::get('app.uploads.story_video_max_bytes'),
                'videoSeconds' => (int) Config::get('app.uploads.story_video_seconds', 30),
                'imageBytes'   => (int) Config::get('app.uploads.image.max_bytes'),
                'songSeconds'  => (int) Config::get('app.limits.story_song_seconds', 15),
            ],
        ], 'layouts/immersive');
    }

    /** Al cerrar el visor se vuelve a la página anterior de este sitio (si no era otra historia) o al inicio. */
    private function exitUrl(): string
    {
        $referer = (string) ($_SERVER['HTTP_REFERER'] ?? '');
        $host = $referer !== '' ? parse_url($referer, PHP_URL_HOST) : null;
        $ownHost = parse_url(absolute_url(), PHP_URL_HOST);
        if (is_string($host) && is_string($ownHost) && strcasecmp($host, $ownHost) === 0 && !str_contains($referer, 'stories.php')) {
            return $referer;
        }
        return url('feed.php');
    }
}
