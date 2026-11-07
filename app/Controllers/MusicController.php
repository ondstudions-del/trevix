<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Song;
use Trevix\Models\User;
use Trevix\Services\MediaUpload;
use Trevix\Services\MusicService;

/** Biblioteca de música (music.php), panel del artista (artist.php) y api/music.php. */
final class MusicController extends Controller
{
    /** Pestañas del panel del artista: 'all' y 'used' además de los estados de Song::STATUSES. */
    public const ARTIST_TABS = [
        'all'       => 'Todas',
        'published' => 'Publicadas',
        'pending'   => 'En revisión',
        'rejected'  => 'Rechazadas',
        'withdrawn' => 'Retiradas',
        'removed'   => 'Retiradas por moderación',
        'cancelled' => 'Canceladas',
        'used'      => 'Utilizadas',
    ];

    /** music.php?q=&genre=&sort=&page=  ·  music.php?id= (ficha de la canción). */
    public function index(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Las canciones se envían desde el panel de artista.');
        }
        $id = (int) Request::query('id');
        if ($id > 0) {
            $this->show($id);
            return;
        }

        $term = mb_substr(trim((string) Request::query('q', '')), 0, 80);
        $genre = Request::query('genre', '');
        $genre = isset(Song::GENRES[$genre]) ? $genre : null;
        $sort = Request::queryIn('sort', array_keys(Song::SORTS), 'recent');
        $page = max(1, (int) Request::query('page', '1'));
        $viewer = $this->viewer();
        $result = Song::library(
            $this->isPreview() ? 0 : (int) $viewer['id'],
            ['term' => $term, 'genre' => $genre, 'sort' => $sort],
            $page,
            (int) Config::get('app.limits.songs_page', 24)
        );

        $this->render('pages/music', [
            'title'     => 'Música · TREVIX',
            'activeNav' => 'music',
            'term'      => $term,
            'genre'     => $genre,
            'sort'      => $sort,
            'songs'     => $result['songs'],
            'nextUrl'   => $result['hasMore']
                ? url('music.php', ['q' => $term, 'genre' => $genre, 'sort' => $sort === 'recent' ? null : $sort, 'page' => $page + 1])
                : null,
            'isArtist'  => User::isMusicArtist($viewer),
            'aside'     => $this->asideData(),
        ]);
    }

    /** artist.php?status=&page= — canciones propias, su estado y sus usos, y el formulario de envío. */
    public function artist(): void
    {
        $user = $this->requireUser();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Las canciones se envían a api/music.php.');
        }
        $uid = (int) $user['id'];
        $status = Request::queryIn('status', array_keys(self::ARTIST_TABS), 'all');
        $page = max(1, (int) Request::query('page', '1'));
        $counts = Song::countsForArtist($uid);
        $result = Song::forArtist($uid, $status === 'all' ? null : $status, $page, (int) Config::get('app.limits.songs_page', 24));

        $this->render('pages/artist', [
            'title'     => 'Artista · TREVIX',
            'activeNav' => 'artist',
            'isArtist'  => User::isMusicArtist($user),
            'status'    => $status,
            'counts'    => $counts,
            'songs'     => $result['songs'],
            'nextUrl'   => $result['hasMore'] ? url('artist.php', ['status' => $status === 'all' ? null : $status, 'page' => $page + 1]) : null,
            'errors'    => Session::pull('_errors', []),
            'old'       => Session::pull('_old', []),
        ]);
    }

    /** api/music.php: GET action=search · POST action = submit | cancel | withdraw | republish | delete. */
    public function api(): void
    {
        $user = $this->requireUser();
        $uid = (int) $user['id'];

        if (!Request::isPost()) {
            if (Request::query('action') !== 'search') {
                Response::json(['ok' => false, 'error' => 'Acción no válida.'], 400);
            }
            $this->search($uid);
        }

        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === []) {
            $this->fail('El archivo supera el tamaño que acepta el servidor.', 413, url('artist.php'));
        }
        VerifyCsrf::handle();

        $action = Request::text('action');
        if ($action === 'submit') {
            $this->submit($user);
        }
        if (!in_array($action, ['cancel', 'withdraw', 'republish', 'delete'], true)) {
            $this->fail('Acción no válida.', 400, url('artist.php'));
        }
        $message = $this->attempt(
            static fn () => MusicService::manage($uid, (int) Request::text('song_id'), $action),
            url('artist.php')
        );
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'message' => $message]);
        }
        Session::flash('success', $message);
        $this->redirectBack(url('artist.php'));
    }

    // -------------------------------------------------------------------------

    private function show(int $id): void
    {
        $viewer = $this->viewer();
        $uid = $this->isPreview() ? 0 : (int) $viewer['id'];
        $song = Song::findPublished($id, $uid);
        if ($song === null) {
            Response::abort(404, 'Esta canción no está disponible.');
        }

        $list = ['posts' => [], 'nextUrl' => null];
        if ($uid > 0) {
            $list = $this->listData(Song::posts($id, $uid, $this->paging()), 'music.php', ['id' => $id]);
        }
        if ($this->isPartial()) {
            $this->renderList($list, 'Ya viste todas las publicaciones con esta canción.');
        }

        $more = Song::library($uid, ['artist_id' => $song['artist']['id'], 'sort' => 'popular'], 1, 7)['songs'];
        $more = array_slice(array_values(array_filter($more, static fn (array $s): bool => $s['id'] !== $id)), 0, 6);

        $this->render('pages/song', [
            'title'     => $song['title'] . ' · ' . $song['artist']['display_name'] . ' · TREVIX',
            'activeNav' => 'music',
            'song'      => $song,
            'list'      => $list,
            'more'      => $more,
            'aside'     => $this->asideData(),
        ]);
    }

    private function search(int $uid): never
    {
        $result = Song::library(
            $uid,
            [
                'term' => mb_substr(trim((string) Request::query('q', '')), 0, 80),
                'sort' => Request::queryIn('sort', array_keys(Song::SORTS), 'popular'),
            ],
            max(1, (int) Request::query('page', '1')),
            20
        );
        Response::json([
            'ok'      => true,
            'songs'   => array_map('song_client', $result['songs']),
            'hasMore' => $result['hasMore'],
        ]);
    }

    private function submit(array $user): never
    {
        $input = [
            'title'     => Request::text('title'),
            'featuring' => Request::text('featuring'),
            'genre'     => Request::text('genre'),
            'explicit'  => Request::text('explicit') === '1',
            'rights'    => Request::text('rights') === '1',
        ];
        try {
            $songId = MusicService::submit($user, $input, MediaUpload::collect('audio'));
        } catch (ActionError $e) {
            if ($e->retryAfter !== null && !headers_sent()) {
                header('Retry-After: ' . $e->retryAfter);
            }
            if (Request::wantsJson()) {
                Response::json(['ok' => false, 'error' => $e->getMessage(), 'fields' => $e->fields], $e->status);
            }
            if ($e->fields === []) {
                $this->fail($e->getMessage(), $e->status, url('artist.php'));
            }
            $this->backWithErrors(url('artist.php') . '#subir', $e->fields, $input);
        }

        $redirect = url('artist.php', ['status' => 'pending']) . '#cancion-' . $songId;
        Session::flash('success', 'Enviamos tu canción a revisión. Te avisaremos cuando el equipo la apruebe.');
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'id' => $songId, 'redirect' => $redirect], 201);
        }
        Response::redirect($redirect);
    }
}
