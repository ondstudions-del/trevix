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
                : (mb_strlen($title) > (int) $limits['song_title'] ? 'El título no puede superar los ' . (int) $limits['song_title'] . ' caracteres.' : null),
            'featuring' => $featuring !== null && mb_strlen($featuring) > (int) $limits['song_featuring']
                ? 'Los artistas invitados no pueden superar los ' . (int) $limits['song_featuring'] . ' caracteres.' : null,
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
                return 'Cancelaste el envío de «' . $song['title'] . '».';
            case 'withdraw':
                if (!Song::transition($songId, ['published'], 'withdrawn')) {
                    throw new ActionError('Solo puedes retirar canciones publicadas.', 409);
                }
                return 'Retiraste «' . $song['title'] . '»: ya no aparece en la biblioteca ni suena donde se usó.';
            case 'republish':
                if (!Song::transition($songId, ['withdrawn'], 'published')) {
                    throw new ActionError('Solo puedes volver a publicar canciones que retiraste tú.', 409);
                }
                return '«' . $song['title'] . '» vuelve a estar en la biblioteca.';
            case 'delete':
                if (!in_array($song['status'], self::DELETABLE, true)) {
                    throw new ActionError($song['status'] === 'pending'
                        ? 'Cancela el envío antes de eliminar la canción.'
                        : ($song['status'] === 'published' ? 'Retira la canción antes de eliminarla.' : 'Esta canción no se puede eliminar.'), 409);
                }
                Song::delete($song);
                return 'Eliminaste «' . $song['title'] . '».';
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
}
