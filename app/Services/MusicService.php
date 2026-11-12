<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Models\RateLimit;
use Trevix\Models\Song;
use Trevix\Models\User;

/**
 * Música de artistas (compartido por la web y la API): enviar canciones a revisión, gestionarlas y
 * elegirlas para publicaciones, historias y mensajes.
 *
 * Ciclo de una canción:
 *   pending → published (el equipo la aprueba) | rejected (no la aprueba) | cancelled (el artista la cancela)
 *   published → withdrawn (el artista la retira) → published (la vuelve a publicar, sin nueva revisión)
 *   published | withdrawn → removed (moderación) → published (moderación la restaura)
 */
final class MusicService
{
    /** Estados en los que el artista puede eliminar la canción definitivamente. */
    public const DELETABLE = ['rejected', 'cancelled', 'withdrawn'];

    /** Por página del catálogo único: canciones de TREVIX y pistas de cada catálogo externo. */
    private const BROWSE_LOCAL = 12;
    private const BROWSE_EXTERNAL = 8;

    /**
     * Envía una canción a revisión. El audio llega en $audioFiles (MediaUpload::collect('audio')) y la
     * portada opcional en $_FILES['cover'].
     *
     * @param array{title?:string, featuring?:string, genre?:string, explicit?:bool, rights?:bool} $input
     */
    public static function submit(array $user, array $input, array $audioFiles): int
    {
        if (!User::isMusicArtist($user)) {
            throw new ActionError('Para publicar música elige «Creador de contenido · Artista musical» en Editar perfil.', 403);
        }
        Guard::verifiedEmail($user);
        $uid = (int) $user['id'];
        $rateKey = 'user:' . $uid;
        Guard::rateLimit('song_submit', $rateKey, 'Llegaste al límite de canciones enviadas por hoy. Inténtalo de nuevo en {min} min.');

        $limits = (array) Config::get('app.limits');
        $title = Guard::singleLine((string) ($input['title'] ?? ''), 1000) ?? '';
        $featuring = Guard::singleLine((string) ($input['featuring'] ?? ''), 1000);
        $genre = trim((string) ($input['genre'] ?? ''));

        $errors = array_filter([
            'title'     => $title === '' ? 'Escribe el título de la canción.'
                : (mb_strlen($title) > (int) $limits['song_title'] ? t('El título no puede superar los {n} caracteres.', ['n' => (int) $limits['song_title']]) : null),
            'featuring' => $featuring !== null && mb_strlen($featuring) > (int) $limits['song_featuring']
                ? t('Los artistas invitados no pueden superar los {n} caracteres.', ['n' => (int) $limits['song_featuring']]) : null,
            'genre'     => !isset(Song::GENRES[$genre]) ? 'Elige el género de la canción.' : null,
            'audio'     => count($audioFiles) !== 1 ? 'Elige el archivo de la canción (MP3 o M4A).' : null,
            'rights'    => empty($input['rights']) ? 'Confirma que tienes los derechos para publicar esta canción.' : null,
        ]);
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }

        RateLimit::hit('song_submit', $rateKey);

        try {
            $audio = AudioUpload::store($audioFiles[0]);
        } catch (RuntimeException $e) {
            throw ActionError::field('audio', $e->getMessage());
        }
        try {
            $cover = ImageUpload::storeProfileImage('cover', 'song_cover');
        } catch (RuntimeException $e) {
            AudioUpload::delete($audio['path']);
            throw ActionError::field('cover', $e->getMessage());
        }

        try {
            return Song::create($uid, [
                'title'     => $title,
                'featuring' => $featuring,
                'genre'     => $genre,
                'explicit'  => !empty($input['explicit']),
                'audio'     => $audio,
                'cover'     => $cover,
            ]);
        } catch (Throwable $e) {
            AudioUpload::delete($audio['path']);
            ImageUpload::delete($cover);
            throw $e;
        }
    }

    /**
     * Acción del artista sobre una canción propia: cancel | withdraw | republish | delete.
     * Devuelve el mensaje de confirmación.
     */
    public static function manage(int $uid, int $songId, string $action): string
    {
        $song = $songId > 0 ? Song::findOwn($songId, $uid) : null;
        if ($song === null) {
            throw new ActionError('No encontramos esa canción entre las tuyas.', 404);
        }

        switch ($action) {
            case 'cancel':
                if (!Song::transition($songId, ['pending'], 'cancelled')) {
                    throw new ActionError('Solo puedes cancelar canciones que siguen en revisión.', 409);
                }
                return t('Cancelaste el envío de «{title}».', ['title' => $song['title']]);
            case 'withdraw':
                if (!Song::transition($songId, ['published'], 'withdrawn')) {
                    throw new ActionError('Solo puedes retirar canciones publicadas.', 409);
                }
                return t('Retiraste «{title}»: ya no aparece en la biblioteca ni suena donde se usó.', ['title' => $song['title']]);
            case 'republish':
                if (!Song::transition($songId, ['withdrawn'], 'published')) {
                    throw new ActionError('Solo puedes volver a publicar canciones que retiraste tú.', 409);
                }
                return t('«{title}» vuelve a estar en la biblioteca.', ['title' => $song['title']]);
            case 'delete':
                if (!in_array($song['status'], self::DELETABLE, true)) {
                    throw new ActionError($song['status'] === 'pending'
                        ? 'Cancela el envío antes de eliminar la canción.'
                        : ($song['status'] === 'published' ? 'Retira la canción antes de eliminarla.' : 'Esta canción no se puede eliminar.'), 409);
                }
                Song::delete($song);
                return t('Eliminaste «{title}».', ['title' => $song['title']]);
        }
        throw new ActionError('Acción no válida.', 400);
    }

    /**
     * Comprueba que la canción elegida para publicar se puede usar y ajusta el inicio del fragmento.
     *
     * @return array{id:int, start:int, duration:int}
     */
    public static function resolveForUse(int $songId, int $start, int $uid, string $field = 'song_id'): array
    {
        $song = $songId > 0 ? Song::findPublished($songId, $uid) : null;
        if ($song === null) {
            throw ActionError::field($field, 'Esa canción ya no está disponible en la biblioteca de música.');
        }
        $clip = min((int) Config::get('app.limits.song_clip_seconds', 30), $song['duration']);
        return [
            'id'       => $song['id'],
            'start'    => max(0, min($start, $song['duration'] - $clip)),
            'duration' => $song['duration'],
        ];
    }

    /**
     * Catálogo único: canciones de artistas de TREVIX y pistas de Audius y Free To Use en una sola lista,
     * intercaladas. Las pistas externas que ya se usaron en TREVIX llegan como canción ('song'); las demás como
     * pista ('track'), que se guarda al elegirla (import). Si un catálogo externo no responde, la lista sigue con
     * los demás y su nombre va en 'unavailable'. Sin sesión (vista previa) solo se ve la biblioteca de TREVIX.
     *
     * @param array{term?:string, genre?:?string, sort?:string} $filters
     * @return array{items: list<array{source:string, song:?array, track:?array}>, hasMore: bool, unavailable: list<string>}
     */
    public static function browse(int $uid, array $filters, int $page): array
    {
        $term = mb_substr(trim((string) ($filters['term'] ?? '')), 0, 80);
        $genre = isset(Song::GENRES[(string) ($filters['genre'] ?? '')]) ? (string) $filters['genre'] : null;
        $sort = isset(Song::SORTS[(string) ($filters['sort'] ?? '')]) ? (string) $filters['sort'] : 'recent';
        $page = max(1, min(25, $page));

        $local = Song::library($uid, ['term' => $term, 'genre' => $genre, 'sort' => $sort, 'source' => 'trevix'], $page, self::BROWSE_LOCAL);
        $lists = [array_map(static fn (array $s): array => ['source' => 'trevix', 'song' => $s, 'track' => null], $local['songs'])];
        $hasMore = $local['hasMore'];
        // Sonidos originales de los videos: se buscan por la persona que los publicó; sin búsqueda, los más usados.
        if ($genre === null) {
            $originals = Song::library($uid, ['term' => $term, 'sort' => $term === '' ? 'popular' : $sort, 'source' => 'original'], $page, self::BROWSE_EXTERNAL);
            $lists[] = array_map(static fn (array $s): array => ['source' => 'original', 'song' => $s, 'track' => null], $originals['songs']);
            $hasMore = $hasMore || $originals['hasMore'];
        }
        $unavailable = [];

        $external = [];
        if ($uid > 0) {
            try {
                Guard::rateLimit('catalog_search', 'user:' . $uid, 'Hiciste demasiadas búsquedas. Espera {min} min.');
                RateLimit::hit('catalog_search', 'user:' . $uid);
                $external = MusicCatalog::searchMany(array_keys(MusicCatalog::SOURCES), $term, $page, self::BROWSE_EXTERNAL);
            } catch (ActionError) {
                $unavailable = array_values(MusicCatalog::SOURCES);
            }
        }
        foreach ($external as $source => $result) {
            if ($result instanceof RuntimeException) {
                $unavailable[] = MusicCatalog::SOURCES[$source];
                continue;
            }
            $hasMore = $hasMore || $result['hasMore'];
            $tracks = $genre === null ? $result['tracks'] : array_values(array_filter($result['tracks'], static fn (array $t): bool => $t['genre'] === $genre));
            $known = Song::externalCards($source, array_column($tracks, 'external_id'));
            $list = [];
            foreach ($tracks as $track) {
                if (!array_key_exists($track['external_id'], $known)) {
                    $list[] = ['source' => $source, 'song' => null, 'track' => $track];
                } elseif ($known[$track['external_id']] !== null) {
                    $list[] = ['source' => $source, 'song' => $known[$track['external_id']], 'track' => null];
                }
            }
            $lists[] = $list;
        }

        $items = [];
        for ($i = 0, $max = max(array_map('count', $lists)); $i < $max; $i++) {
            foreach ($lists as $list) {
                if (isset($list[$i])) {
                    $items[] = $list[$i];
                }
            }
        }
        return ['items' => $items, 'hasMore' => $hasMore, 'unavailable' => $unavailable];
    }

    /**
     * Búsqueda en un catálogo externo (Audius o Free To Use).
     *
     * @return array{tracks: list<array>, hasMore: bool}
     */
    public static function catalog(int $uid, string $source, string $term, int $page): array
    {
        if (!isset(MusicCatalog::SOURCES[$source])) {
            throw new ActionError('Catálogo de música no válido.', 400);
        }
        Guard::rateLimit('catalog_search', 'user:' . $uid, 'Hiciste demasiadas búsquedas. Espera {min} min.');
        RateLimit::hit('catalog_search', 'user:' . $uid);
        try {
            return MusicCatalog::search($source, $term, $page);
        } catch (RuntimeException) {
            throw new ActionError(t('No se pudo conectar con {source}. Inténtalo de nuevo en unos minutos.', ['source' => MusicCatalog::SOURCES[$source]]), 502);
        }
    }

    /** Toma una pista de un catálogo externo para usarla en TREVIX; devuelve la canción (Song::cardsFor). */
    public static function import(int $uid, string $source, string $externalId): array
    {
        Guard::rateLimit('song_import', 'user:' . $uid, 'Elegiste demasiadas canciones nuevas. Espera {min} min.');
        try {
            $song = MusicCatalog::import($source, $externalId, $uid);
        } catch (RuntimeException $e) {
            throw new ActionError($e->getMessage(), 422);
        }
        RateLimit::hit('song_import', 'user:' . $uid);
        return $song;
    }
}
