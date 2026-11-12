<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Models\Block;
use Trevix\Models\RateLimit;
use Trevix\Models\Song;
use Trevix\Models\User;
use Trevix\Services\Guard;
use Trevix\Services\MediaUpload;
use Trevix\Services\Moderation;
use Trevix\Services\MusicService;

/** Biblioteca de música, canciones de cada artista, panel del artista y revisión por moderación. */
final class MusicController extends ApiController
{
    private const ADMIN_STATUSES = ['pending', 'published', 'rejected', 'removed', 'withdrawn'];

    /** GET /music?q=&genre=&sort=recent|popular&source=trevix|original&page= */
    public function library(): never
    {
        $genre = Request::query('genre');
        $result = Song::library($this->uid(), [
            'term'   => mb_substr(trim(Request::query('q')), 0, 80),
            'genre'  => isset(Song::GENRES[$genre]) ? $genre : null,
            'sort'   => Request::queryIn('sort', array_keys(Song::SORTS), 'recent'),
            'source' => Request::queryIn('source', ['trevix', 'original'], 'trevix'),
        ], $this->pageNumber(), $this->limit('songs_page', 24));
        Reply::ok(Present::songs($result['songs']), $this->nextPage($result['hasMore']));
    }

    /**
     * GET /music/browse?q=&genre=&sort=&page= — catálogo único: canciones de TREVIX y pistas de Audius y Free To Use
     * intercaladas. Cada elemento trae `song` (ya se puede usar) o `track` (se importa al elegirla).
     */
    public function browse(): never
    {
        $result = MusicService::browse($this->uid(), [
            'term'  => Request::query('q'),
            'genre' => Request::query('genre'),
            'sort'  => Request::query('sort'),
        ], $this->pageNumber());
        Reply::ok(array_map(static fn (array $item): array => [
            'source'       => $item['source'],
            'source_label' => Song::SOURCES[$item['source']],
            'song'         => $item['song'] !== null ? Present::song($item['song']) : null,
            'track'        => $item['track'] !== null ? self::track($item['track']) : null,
        ], $result['items']), $this->nextPage($result['hasMore']) + ['unavailable' => $result['unavailable']]);
    }

    /** GET /music/catalog/{audius|freetouse}?q=&page= — pistas del catálogo externo (sin texto: destacadas). */
    public function catalog(string $source): never
    {
        $result = MusicService::catalog($this->uid(), $source, Request::query('q'), $this->pageNumber());
        Reply::ok(array_map([self::class, 'track'], $result['tracks']), $this->nextPage($result['hasMore']));
    }

    private static function track(array $t): array
    {
        return [
            'source'       => $t['source'],
            'source_label' => $t['source_label'],
            'external_id'  => $t['external_id'],
            'title'        => $t['title'],
            'artist'       => $t['artist'],
            'genre'        => $t['genre'],
            'genre_label'  => $t['genre_label'],
            'duration'     => $t['duration'],
            'preview_url'  => $t['audio_url'],
            'cover_url'    => $t['cover_url'],
            'page_url'     => $t['page_url'],
        ];
    }

    /** POST /music/catalog/{audius|freetouse}/import {external_id} — la guarda como canción y la devuelve lista para usar. */
    public function import(string $source): never
    {
        Reply::ok(Present::song(MusicService::import($this->uid(), $source, Input::str('external_id'))));
    }

    /** GET /music/{id} */
    public function show(string $id): never
    {
        Reply::ok(Present::song($this->published((int) $id)));
    }

    /** GET /music/{id}/posts?before= — publicaciones visibles que usan la canción. */
    public function posts(string $id): never
    {
        $song = $this->published((int) $id);
        $result = Song::posts($song['id'], $this->uid(), $this->paging());
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /** GET /users/{username}/music?page= — canciones publicadas del artista (visibles aunque el perfil sea privado). */
    public function byArtist(string $username): never
    {
        $username = mb_strtolower($username);
        $uid = $this->uid();
        $artist = preg_match('/^[a-z0-9_.]{3,30}$/', $username) ? User::findByUsername($username) : null;
        if ($artist === null || ((int) $artist['id'] !== $uid && ($artist['status'] !== 'active' || Block::exists((int) $artist['id'], $uid)))) {
            $this->notFound(t('No encontramos a @{username}.', ['username' => $username]));
        }
        $result = Song::library($uid, ['artist_id' => (int) $artist['id']], $this->pageNumber(), $this->limit('songs_page', 24));
        Reply::ok(Present::songs($result['songs']), $this->nextPage($result['hasMore']));
    }

    /** GET /me/music?status=all|used|pending|published|rejected|cancelled|withdrawn|removed&page= */
    public function mine(): never
    {
        $user = $this->user();
        $uid = (int) $user['id'];
        $status = Request::queryIn('status', array_merge(['all', 'used'], array_keys(Song::STATUSES)), 'all');
        $result = Song::forArtist($uid, $status === 'all' ? null : $status, $this->pageNumber(), $this->limit('songs_page', 24));
        Reply::ok(array_map([Present::class, 'ownSong'], $result['songs']), $this->nextPage($result['hasMore']) + [
            'counts'          => Song::countsForArtist($uid),
            'is_music_artist' => User::isMusicArtist($user),
        ]);
    }

    /** POST /me/music (multipart) {title, featuring?, genre, explicit?, rights} + «audio» (MP3/M4A) y «cover» opcional. */
    public function submit(): never
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === []) {
            throw new ActionError('El archivo supera el tamaño que acepta el servidor.', 413);
        }
        $user = $this->user();
        $songId = MusicService::submit($user, [
            'title'     => Input::str('title'),
            'featuring' => Input::str('featuring'),
            'genre'     => Input::str('genre'),
            'explicit'  => Input::bool('explicit'),
            'rights'    => Input::bool('rights'),
        ], MediaUpload::collect('audio'));
        $song = Song::findOwn($songId, (int) $user['id']);
        $this->created([
            'message' => 'Enviamos tu canción a revisión. Te avisaremos cuando el equipo la apruebe.',
            'song'    => $song !== null ? Present::ownSong($song) : ['id' => $songId],
        ]);
    }

    /** POST /me/music/{id}/cancel|withdraw|republish · DELETE /me/music/{id} */
    public function manage(string $id, string $action = 'delete'): never
    {
        Reply::ok(['message' => MusicService::manage($this->uid(), (int) $id, $action)]);
    }

    /** GET /admin/music?status=pending|published|rejected|removed|withdrawn&q=&page= */
    public function adminList(): never
    {
        $status = Request::queryIn('status', self::ADMIN_STATUSES, 'pending');
        $result = Song::adminList($status, mb_substr(trim(Request::query('q')), 0, 100), $this->pageNumber(), $this->limit('admin_page', 25));
        Reply::ok(Present::admin($result['songs']), $this->nextPage($result['hasMore']) + ['counts' => Song::adminCounts()]);
    }

    /** POST /admin/music/{id}/approve {note?} · reject {reason} · remove {reason} · restore {note?} */
    public function moderate(string $id, string $action): never
    {
        $staff = $this->user();
        $key = (string) $staff['id'];
        Guard::rateLimit('admin_action', $key, 'Hiciste demasiadas acciones seguidas. Espera {min} min.');
        RateLimit::hit('admin_action', $key);

        $song = (int) $id > 0 ? Song::findRaw((int) $id) : null;
        if ($song === null) {
            $this->notFound('Esta canción ya no existe.');
        }
        $max = (int) Config::get('app.limits.moderation_note', 255);
        $note = Guard::singleLine(Input::str('note', false), $max);
        $reason = (string) Guard::singleLine(Input::str('reason', false), $max);
        $message = match ($action) {
            'approve' => (static function () use ($staff, $song, $note): string {
                Moderation::approveSong($staff, $song, $note);
                return t('«{title}» ya está en la biblioteca.', ['title' => $song['title']]);
            })(),
            'reject'  => (static function () use ($staff, $song, $reason): string {
                Moderation::rejectSong($staff, $song, $reason);
                return t('Rechazaste «{title}».', ['title' => $song['title']]);
            })(),
            'remove'  => (static function () use ($staff, $song, $reason): string {
                Moderation::removeSong($staff, $song, $reason);
                return t('Retiraste «{title}» de la biblioteca.', ['title' => $song['title']]);
            })(),
            default   => (static function () use ($staff, $song, $note): string {
                Moderation::restoreSong($staff, $song, $note);
                return t('«{title}» vuelve a estar en la biblioteca.', ['title' => $song['title']]);
            })(),
        };
        Reply::ok(['message' => $message, 'song' => Present::admin(Song::findRaw((int) $id))]);
    }

    private function published(int $id): array
    {
        $song = $id > 0 ? Song::findPublished($id, $this->uid()) : null;
        return $song ?? $this->notFound('Esta canción no está disponible.');
    }
}
