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
        $page = max(1, (int) Request::query('page', '1'));
        $viewer = $this->viewer();
        $genre = Request::query('genre', '');
        $genre = isset(Song::GENRES[$genre]) ? $genre : null;
        $sort = Request::queryIn('sort', array_keys(Song::SORTS), 'recent');
        $result = MusicService::browse(
            $this->isPreview() ? 0 : (int) $viewer['id'],
            ['term' => $term, 'genre' => $genre, 'sort' => $sort],
            $page
        );

        $this->render('pages/music', [
            'title'       => t('Música') . ' · TREVIX',
            'activeNav'   => 'music',
            'term'        => $term,
            'genre'       => $genre,
            'sort'        => $sort,
            'items'       => $result['items'],
            'unavailable' => $result['unavailable'],
            'nextUrl'     => $result['hasMore']
                ? url('music.php', ['q' => $term, 'genre' => $genre, 'sort' => $sort === 'recent' ? null : $sort, 'page' => $page + 1])
                : null,
            'isArtist'    => User::isMusicArtist($viewer),
            'aside'       => $this->asideData(),
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
            'title'     => t('Artista') . ' · TREVIX',
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

    /**
     * api/music.php: GET action = search | catalog (source=audius|freetouse)
     * · POST action = submit | cancel | withdraw | republish | delete | import (source + external_id).
     */
    public function api(): void
    {
        $user = $this->requireUser();
        $uid = (int) $user['id'];

        if (!Request::isPost()) {
            match (Request::query('action')) {
                'search'  => $this->search($uid),
                'catalog' => $this->catalog($uid),
                default   => Response::json(['ok' => false, 'error' => 'Acción no válida.'], 400),
            };
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
        if ($action === 'import') {
            $this->import($uid);
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

        $more = [];
        if ($song['artist']['id'] > 0) {
            $more = Song::library($uid, ['artist_id' => $song['artist']['id'], 'sort' => 'popular'], 1, 7)['songs'];
            $more = array_slice(array_values(array_filter($more, static fn (array $s): bool => $s['id'] !== $id)), 0, 6);
        }

        $this->render('pages/song', [
            'title'     => $song['title'] . ' · ' . $song['artist']['display_name'] . ' · TREVIX',
            'activeNav' => 'music',
            'song'      => $song,
            'list'      => $list,
            'more'      => $more,
            'aside'     => $this->asideData(),
        ]);
    }

    /** Selector de canciones: catálogo único (TREVIX, Audius y Free To Use). */
    private function search(int $uid): never
    {
        $result = MusicService::browse(
            $uid,
            [
                'term' => (string) Request::query('q', ''),
                'sort' => Request::queryIn('sort', array_keys(Song::SORTS), 'popular'),
            ],
            max(1, (int) Request::query('page', '1'))
        );
        Response::json([
            'ok'          => true,
            'items'       => array_map(static fn (array $item): array => [
                'source'       => $item['source'],
                'source_label' => Song::SOURCES[$item['source']],
                'song'         => $item['song'] !== null ? song_client($item['song']) : null,
                'track'        => $item['track'] !== null ? self::trackClient($item['track']) : null,
            ], $result['items']),
            'hasMore'     => $result['hasMore'],
            'unavailable' => $result['unavailable'],
        ]);
    }

    private static function trackClient(array $t): array
    {
        return [
            'source'       => $t['source'],
            'source_label' => $t['source_label'],
            'external_id'  => $t['external_id'],
            'title'        => $t['title'],
            'artist'       => $t['artist'],
            'genre_label'  => $t['genre_label'],
            'duration'     => $t['duration'],
            'preview'      => $t['audio_url'],
            'cover'        => $t['cover_url'],
            'page_url'     => $t['page_url'],
        ];
    }

    private function catalog(int $uid): never
    {
        $result = $this->attempt(
            static fn () => MusicService::catalog(
                $uid,
                Request::query('source'),
                (string) Request::query('q', ''),
                max(1, (int) Request::query('page', '1'))
            ),
            url('music.php')
        );
        Response::json([
            'ok'      => true,
            'tracks'  => array_map([self::class, 'trackClient'], $result['tracks']),
            'hasMore' => $result['hasMore'],
        ]);
    }

    /** Toma una pista de un catálogo externo: JSON con la canción lista para el selector, o redirección a su ficha. */
    private function import(int $uid): never
    {
        $song = $this->attempt(
            static fn () => MusicService::import($uid, Request::text('source'), Request::text('external_id')),
            url('music.php')
        );
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'song' => song_client($song)]);
        }
        Response::redirect(url('music.php', ['id' => $song['id']]));
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
                Response::json(['ok' => false, 'error' => $e->getMessage(), 'fields' => array_map('t', $e->fields)], $e->status);
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
