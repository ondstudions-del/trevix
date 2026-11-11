<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;
use Trevix\Models\Song;

/**
 * Catálogos de música externos que se pueden usar en publicaciones e historias igual que las canciones de
 * artistas de TREVIX:
 *  - Audius (api.audius.co): música de artistas independientes; solo pistas que el artista deja reproducir
 *    libremente (is_streamable y sin acceso restringido). El audio se escucha desde los nodos de Audius.
 *  - Free To Use (freetouse.com): música libre de derechos con atribución obligatoria
 *    («Música: título de artista — Free To Use»), que se muestra junto a la canción.
 *
 * La búsqueda consulta el catálogo en vivo (con caché corta). Al elegir una pista se vuelve a pedir al
 * catálogo por su id (nunca se confía en los datos que envía el navegador) y se guarda en songs.
 */
final class MusicCatalog
{
    public const SOURCES = ['audius' => 'Audius', 'freetouse' => 'Free To Use'];

    private const AUDIUS = 'https://api.audius.co/v1';
    private const FREETOUSE = 'https://api.freetouse.com/v3';
    private const PAGE = 20;

    /** Género del catálogo → género de TREVIX (Song::GENRES). */
    private const GENRE_MAP = [
        'pop' => 'pop', 'k-pop' => 'pop', 'dance' => 'pop',
        'rock' => 'rock', 'metal' => 'rock', 'punk' => 'rock', 'hard rock' => 'rock',
        'hip-hop/rap' => 'hiphop', 'hip hop' => 'hiphop', 'hip-hop' => 'hiphop', 'rap' => 'hiphop', 'trap' => 'hiphop',
        'reggaeton' => 'reggaeton', 'urbano' => 'reggaeton', 'latin' => 'latin', 'tropical' => 'latin', 'reggae' => 'latin',
        'electronic' => 'electronic', 'electronica' => 'electronic', 'house' => 'electronic', 'techno' => 'electronic',
        'trance' => 'electronic', 'dubstep' => 'electronic', 'drum & bass' => 'electronic', 'deep house' => 'electronic',
        'tech house' => 'electronic', 'future house' => 'electronic', 'future bass' => 'electronic', 'tropical house' => 'electronic',
        'progressive house' => 'electronic', 'electro' => 'electronic', 'downtempo' => 'electronic', 'moombahton' => 'electronic',
        'jersey club' => 'electronic', 'jungle' => 'electronic', 'hardstyle' => 'electronic', 'glitch hop' => 'electronic',
        'r&b/soul' => 'rnb', 'r&b' => 'rnb', 'soul' => 'rnb', 'funk' => 'rnb',
        'alternative' => 'indie', 'indie' => 'indie', 'lo-fi' => 'indie', 'lofi' => 'indie', 'chill' => 'indie',
        'jazz' => 'jazz', 'blues' => 'jazz',
        'classical' => 'classical', 'ambient' => 'classical', 'instrumental' => 'classical', 'soundtrack' => 'classical',
        'cinematic' => 'classical', 'easy listening' => 'classical', 'piano' => 'classical', 'orchestral' => 'classical',
        'folk' => 'regional', 'country' => 'regional', 'world' => 'regional', 'acoustic' => 'regional',
    ];

    /**
     * Pistas del catálogo: búsqueda por texto o, sin texto, las destacadas (tendencias en Audius, recientes en Free To Use).
     *
     * @return array{tracks: list<array>, hasMore: bool}
     * @throws RuntimeException si el catálogo no responde.
     */
    public static function search(string $source, string $term, int $page, int $limit = self::PAGE): array
    {
        $url = self::searchUrl($source, $term, $page, $limit);
        return self::parse($source, HttpClient::getJson($url, self::ttl()), $limit);
    }

    /**
     * Busca en varios catálogos a la vez (en paralelo). Un catálogo que no responde no impide ver los demás.
     *
     * @param list<string> $sources
     * @return array<string, array{tracks: list<array>, hasMore: bool}|RuntimeException>
     */
    public static function searchMany(array $sources, string $term, int $page, int $limit): array
    {
        $urls = [];
        foreach ($sources as $source) {
            $urls[$source] = self::searchUrl($source, $term, $page, $limit);
        }
        $out = [];
        foreach (HttpClient::getJsonMany($urls, self::ttl()) as $source => $data) {
            $out[$source] = $data instanceof RuntimeException ? $data : self::parse($source, $data, $limit);
        }
        return $out;
    }

    private static function searchUrl(string $source, string $term, int $page, int $limit): string
    {
        $term = mb_substr(trim($term), 0, 80);
        $limit = max(1, min(self::PAGE, $limit));
        $offset = (max(1, min(25, $page)) - 1) * $limit;
        if ($source === 'audius') {
            $query = ['app_name' => self::appName(), 'limit' => $limit, 'offset' => $offset];
            return $term === ''
                ? self::AUDIUS . '/tracks/trending?' . http_build_query($query)
                : self::AUDIUS . '/tracks/search?' . http_build_query(['query' => $term] + $query);
        }
        if ($source === 'freetouse') {
            $query = ['limit' => $limit, 'offset' => $offset];
            return $term === ''
                ? self::FREETOUSE . '/music/tracks/all?' . http_build_query($query)
                : self::FREETOUSE . '/music/tracks/search?' . http_build_query(['query' => $term] + $query);
        }
        throw new RuntimeException('Catálogo desconocido.');
    }

    /** @return array{tracks: list<array>, hasMore: bool} */
    private static function parse(string $source, array $data, int $limit): array
    {
        $rows = array_values(array_filter((array) ($data['data'] ?? []), 'is_array'));
        $map = $source === 'audius' ? [self::class, 'fromAudius'] : [self::class, 'fromFreeToUse'];
        $tracks = array_values(array_filter(array_map($map, $rows)));
        return ['tracks' => $tracks, 'hasMore' => count($rows) >= max(1, min(self::PAGE, $limit))];
    }

    private static function ttl(): int
    {
        return (int) Config::get('app.services.cache_ttl', 600);
    }

    /**
     * Guarda la pista como canción de TREVIX (o devuelve la ya guardada) y la entrega lista para usar.
     *
     * @throws RuntimeException si la pista no existe, no se puede reproducir o fue retirada por moderación.
     */
    public static function import(string $source, string $externalId, int $viewerId): array
    {
        if (!isset(self::SOURCES[$source]) || !preg_match('/^[A-Za-z0-9-]{1,64}$/', $externalId)) {
            throw new RuntimeException('La canción no existe.');
        }
        $existing = Song::findExternal($source, $externalId);
        if ($existing !== null) {
            if ($existing['status'] !== 'published') {
                throw new RuntimeException('Esta canción no está disponible en TREVIX.');
            }
            $id = (int) $existing['id'];
        } else {
            $track = self::fetchTrack($source, $externalId);
            if ($track === null) {
                throw new RuntimeException(t('Esta canción ya no está disponible en {source}.', ['source' => self::SOURCES[$source]]));
            }
            $id = Song::createExternal($track);
        }
        $song = Song::findPublished($id, $viewerId);
        if ($song === null) {
            throw new RuntimeException('Esta canción no está disponible en TREVIX.');
        }
        return $song;
    }

    /** Datos actuales de una pista pedidos al catálogo por su id; null si no existe o no se puede reproducir. */
    private static function fetchTrack(string $source, string $externalId): ?array
    {
        try {
            if ($source === 'audius') {
                $data = HttpClient::getJson(self::AUDIUS . '/tracks/' . rawurlencode($externalId) . '?app_name=' . rawurlencode(self::appName()));
                $track = is_array($data['data'] ?? null) ? self::fromAudius($data['data']) : null;
            } else {
                $data = HttpClient::getJson(self::FREETOUSE . '/music/tracks/' . rawurlencode($externalId));
                $row = $data['data'] ?? null;
                $row = is_array($row) && array_is_list($row) ? ($row[0] ?? null) : $row;
                $track = is_array($row) ? self::fromFreeToUse($row) : null;
            }
        } catch (RuntimeException) {
            throw new RuntimeException(t('No se pudo conectar con {source}. Inténtalo de nuevo.', ['source' => self::SOURCES[$source]]));
        }
        return $track !== null && $track['external_id'] === $externalId ? $track : null;
    }

    /** Pista de Audius normalizada; null si no se puede reproducir libremente. */
    private static function fromAudius(mixed $t): ?array
    {
        if (!is_array($t) || !is_string($t['id'] ?? null) || !preg_match('/^[A-Za-z0-9]{1,64}$/', $t['id'])) {
            return null;
        }
        if (($t['is_streamable'] ?? false) !== true || !empty($t['is_stream_gated']) || !empty($t['is_delete'])
            || (array_key_exists('is_available', $t) && $t['is_available'] === false)) {
            return null;
        }
        $duration = (int) round((float) ($t['duration'] ?? 0));
        $user = is_array($t['user'] ?? null) ? $t['user'] : [];
        $artwork = is_array($t['artwork'] ?? null) ? $t['artwork'] : [];
        $permalink = is_string($t['permalink'] ?? null) && str_starts_with($t['permalink'], '/') ? 'https://audius.co' . $t['permalink'] : null;
        return self::track(
            'audius',
            $t['id'],
            (string) ($t['title'] ?? ''),
            (string) ($user['name'] ?? $user['handle'] ?? 'Artista de Audius'),
            (string) ($t['genre'] ?? ''),
            $duration,
            self::AUDIUS . '/tracks/' . rawurlencode($t['id']) . '/stream?app_name=' . rawurlencode(self::appName()),
            self::httpsUrl($artwork['480x480'] ?? $artwork['150x150'] ?? null),
            $permalink
        );
    }

    /** Pista de Free To Use normalizada; null si es premium (requiere suscripción) o no trae MP3. */
    private static function fromFreeToUse(mixed $t): ?array
    {
        if (!is_array($t) || !is_string($t['id'] ?? null) || !preg_match('/^[a-f0-9-]{36}$/', $t['id']) || !empty($t['is_premium'])) {
            return null;
        }
        $audio = self::httpsUrl($t['files']['mp3'] ?? null);
        if ($audio === null) {
            return null;
        }
        $names = [];
        foreach ((array) ($t['artists'] ?? []) as $entry) {
            $artist = is_array($entry) ? ($entry[1] ?? $entry) : null;
            if (is_array($artist) && is_string($artist['name'] ?? null)) {
                $names[] = $artist['name'];
            }
        }
        $thumbs = is_array($t['thumbnails'] ?? null) ? $t['thumbnails'] : [];
        return self::track(
            'freetouse',
            $t['id'],
            (string) ($t['title'] ?? ''),
            $names !== [] ? implode(', ', $names) : 'Free To Use',
            (string) ($t['genre'] ?? ''),
            (int) round((float) ($t['duration'] ?? 0)),
            $audio,
            self::httpsUrl($thumbs['md'] ?? $thumbs['sm'] ?? null),
            'https://freetouse.com/music'
        );
    }

    private static function track(string $source, string $id, string $title, string $artist, string $genre, int $duration, string $audio, ?string $cover, ?string $page): ?array
    {
        $title = trim(preg_replace('/\s+/u', ' ', $title) ?? '');
        if ($title === '' || $duration < 5 || $duration > 65535) {
            return null;
        }
        $genreKey = self::GENRE_MAP[mb_strtolower(trim($genre))] ?? 'other';
        return [
            'source'       => $source,
            'source_label' => self::SOURCES[$source],
            'external_id'  => $id,
            'title'        => mb_substr($title, 0, 100),
            'artist'       => mb_substr(trim($artist), 0, 160),
            'genre'        => $genreKey,
            'genre_label'  => Song::GENRES[$genreKey],
            'duration'     => $duration,
            'audio_url'    => $audio,
            'cover_url'    => $cover,
            'page_url'     => $page,
        ];
    }

    private static function httpsUrl(mixed $url): ?string
    {
        return is_string($url) && strlen($url) <= 500 && preg_match('#^https://[a-z0-9.-]+(:\d+)?/[^\s"\'<>]*$#i', $url) ? $url : null;
    }

    private static function appName(): string
    {
        return (string) Config::get('app.services.audius.app_name', 'TREVIX');
    }
}
