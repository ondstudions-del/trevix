<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Core\Database;
use Trevix\Services\AudioUpload;
use Trevix\Services\ImageUpload;
use Trevix\Services\MediaUpload;

/**
 * Canciones de artistas. Solo las publicadas (aprobadas por el equipo) de cuentas activas forman la
 * biblioteca y suenan donde se usaron; si la canción se retira, se elimina o el artista deja de estar
 * activo, en publicaciones, historias y mensajes aparece como «Canción no disponible».
 */
final class Song extends Model
{
    public const STATUSES = [
        'pending'   => 'En revisión',
        'published' => 'Publicada',
        'rejected'  => 'Rechazada',
        'cancelled' => 'Cancelada',
        'withdrawn' => 'Retirada',
        'removed'   => 'Retirada por moderación',
    ];

    public const GENRES = [
        'pop'         => 'Pop',
        'rock'        => 'Rock',
        'hiphop'      => 'Hip hop / Rap',
        'reggaeton'   => 'Reguetón / Urbano',
        'latin'       => 'Latina / Tropical',
        'electronic'  => 'Electrónica',
        'rnb'         => 'R&B / Soul',
        'indie'       => 'Indie / Alternativa',
        'jazz'        => 'Jazz / Blues',
        'classical'   => 'Clásica / Instrumental',
        'regional'    => 'Regional / Folclor',
        'other'       => 'Otro',
    ];

    public const SORTS = ['recent' => 'Recientes', 'popular' => 'Más usadas'];

    /** Origen de la canción: subida por un artista de TREVIX o tomada de un catálogo externo. */
    public const SOURCES = ['trevix' => 'TREVIX', 'audius' => 'Audius', 'freetouse' => 'Free To Use', 'original' => 'Sonido original'];

    /**
     * Un sonido original se puede usar mientras su video siga publicado y público (si el autor lo oculta o lo
     * pasa a privado, deja de estar disponible). Al borrar el video el sonido conserva su propia copia del audio.
     */
    private const ORIGIN_OK = "(s.origin_post_id IS NULL OR EXISTS (SELECT 1 FROM posts op WHERE op.id = s.origin_post_id
            AND op.status = 'published' AND op.visibility = 'public' AND op.community_id IS NULL))";

    private const CARD_COLUMNS = 's.id, s.source, s.external_id, s.artist_id, s.external_artist, s.external_url, s.title, s.featuring,
            s.genre, s.is_explicit, s.audio_path, s.audio_mime, s.duration_seconds, s.cover_path, s.status, s.uses_count, s.published_at,
            s.origin_post_id, ' . self::ORIGIN_OK . ' AS origin_ok,
            u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS artist_status';

    /** Las canciones externas no tienen cuenta de artista: solo cuenta su estado. */
    private const ARTIST_ACTIVE = "(s.artist_id IS NULL OR u.status = 'active')";

    // -------------------------------------------------------------------------
    // Lectura
    // -------------------------------------------------------------------------

    /**
     * Canciones adjuntas por id, listas para mostrar. Las que ya no están disponibles solo traen
     * ['id', 'available' => false]: no se revela el audio ni los datos de una canción retirada.
     *
     * @return array<int, array>
     */
    public static function cardsFor(array $ids): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids))));
        if ($ids === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT ' . self::CARD_COLUMNS . ' FROM songs s LEFT JOIN users u ON u.id = s.artist_id
             WHERE s.id IN (' . implode(',', array_fill(0, count($ids), '?')) . ')',
            $ids
        );
        $out = [];
        foreach ($ids as $id) {
            $out[$id] = self::unavailable($id);
        }
        foreach ($rows as $r) {
            if ($r['status'] === 'published' && ($r['artist_id'] === null || $r['artist_status'] === 'active') && !empty($r['origin_ok'])) {
                $out[(int) $r['id']] = self::card($r);
            }
        }
        return $out;
    }

    public static function unavailable(int $id): array
    {
        return ['id' => $id, 'available' => false];
    }

    /** Canción publicada que el usuario puede ver (sin bloqueo con el artista). */
    public static function findPublished(int $id, int $viewerId): ?array
    {
        $row = self::fetchOne(
            'SELECT ' . self::CARD_COLUMNS . " FROM songs s LEFT JOIN users u ON u.id = s.artist_id
             WHERE s.id = ? AND s.status = 'published' AND " . self::ARTIST_ACTIVE . ' AND ' . self::ORIGIN_OK . ' AND ' . self::notBlocked() . ' LIMIT 1',
            [$id, $viewerId, $viewerId]
        );
        return $row !== null ? self::card($row) : null;
    }

    /**
     * Biblioteca: canciones publicadas, con búsqueda por título, invitados o artista, género y orden.
     * Por defecto solo las de artistas de TREVIX ('source' => 'all' incluye las ya tomadas de catálogos externos).
     *
     * @param array{term?:string, genre?:?string, sort?:string, artist_id?:int, source?:string} $filters
     * @return array{songs: list<array>, hasMore: bool}
     */
    public static function library(int $viewerId, array $filters, int $page, int $limit): array
    {
        $where = ["s.status = 'published'", self::ARTIST_ACTIVE, self::ORIGIN_OK, self::notBlocked()];
        $params = [$viewerId, $viewerId];

        $source = (string) ($filters['source'] ?? 'trevix');
        if ($source !== 'all') {
            $where[] = 's.source = ?';
            $params[] = isset(self::SOURCES[$source]) ? $source : 'trevix';
        }
        $term = trim((string) ($filters['term'] ?? ''));
        if ($term !== '') {
            $like = '%' . self::likeEscape(ltrim($term, '@')) . '%';
            $where[] = '(s.title LIKE ? OR s.featuring LIKE ? OR u.display_name LIKE ? OR u.username LIKE ? OR s.external_artist LIKE ?)';
            array_push($params, $like, $like, $like, $like, $like);
        }
        if (!empty($filters['genre']) && isset(self::GENRES[$filters['genre']])) {
            $where[] = 's.genre = ?';
            $params[] = $filters['genre'];
        }
        if (!empty($filters['artist_id'])) {
            $where[] = 's.artist_id = ?';
            $params[] = (int) $filters['artist_id'];
        }
        $order = ($filters['sort'] ?? 'recent') === 'popular'
            ? 's.uses_count DESC, s.published_at DESC, s.id DESC'
            : 's.published_at DESC, s.id DESC';

        $limit = max(1, min(50, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT ' . self::CARD_COLUMNS . ' FROM songs s LEFT JOIN users u ON u.id = s.artist_id
             WHERE ' . implode(' AND ', $where) . " ORDER BY $order LIMIT " . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return [
            'songs'   => array_map([self::class, 'card'], array_slice($rows, 0, $limit)),
            'hasMore' => count($rows) > $limit,
        ];
    }

    public static function publishedCountForArtist(int $artistId): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM songs WHERE artist_id = ? AND status = 'published' AND source <> 'original'", [$artistId]);
    }

    /** Canción del artista (cualquier estado) para gestionarla. */
    public static function findOwn(int $id, int $artistId): ?array
    {
        return self::fetchOne('SELECT * FROM songs WHERE id = ? AND artist_id = ? LIMIT 1', [$id, $artistId]);
    }

    public static function findRaw(int $id): ?array
    {
        return self::fetchOne(
            'SELECT s.*, u.username, u.display_name, u.role AS artist_role FROM songs s LEFT JOIN users u ON u.id = s.artist_id WHERE s.id = ? LIMIT 1',
            [$id]
        );
    }

    /** Id de una canción de catálogo externo ya guardada (en cualquier estado). */
    public static function findExternal(string $source, string $externalId): ?array
    {
        return self::fetchOne('SELECT id, status FROM songs WHERE source = ? AND external_id = ? LIMIT 1', [$source, $externalId]);
    }

    /**
     * Pistas de un catálogo externo que ya se guardaron en TREVIX, por su id en el catálogo.
     * Las retiradas por moderación vienen como null (no se deben mostrar ni volver a importar).
     *
     * @param list<string> $externalIds
     * @return array<string, ?array> external_id => canción lista para mostrar, o null si fue retirada
     */
    public static function externalCards(string $source, array $externalIds): array
    {
        $externalIds = array_values(array_unique(array_filter($externalIds, 'is_string')));
        if ($externalIds === []) {
            return [];
        }
        $rows = self::fetchAll(
            'SELECT ' . self::CARD_COLUMNS . ' FROM songs s LEFT JOIN users u ON u.id = s.artist_id
             WHERE s.source = ? AND s.external_id IN (' . implode(',', array_fill(0, count($externalIds), '?')) . ')',
            [$source, ...$externalIds]
        );
        $out = [];
        foreach ($rows as $row) {
            $out[(string) $row['external_id']] = $row['status'] === 'published' ? self::card($row) : null;
        }
        return $out;
    }

    /**
     * Panel del artista: sus canciones por estado ('used' = las que ya se usaron alguna vez), con los usos
     * actuales en publicaciones, historias activas y mensajes.
     *
     * @return array{songs: list<array>, hasMore: bool}
     */
    public static function forArtist(int $artistId, ?string $filter, int $page, int $limit): array
    {
        $where = "s.artist_id = ? AND s.source <> 'original'";
        $params = [$artistId];
        if ($filter === 'used') {
            $where .= ' AND s.uses_count > 0';
        } elseif ($filter !== null && isset(self::STATUSES[$filter])) {
            $where .= ' AND s.status = ?';
            $params[] = $filter;
        }
        $limit = max(1, min(50, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            "SELECT s.*,
                    (SELECT COUNT(*) FROM posts p WHERE p.song_id = s.id AND p.status = 'published') AS post_uses,
                    (SELECT COUNT(*) FROM stories st WHERE st.song_id = s.id AND st.expires_at > NOW()) AS story_uses,
                    (SELECT COUNT(*) FROM messages m WHERE m.song_id = s.id AND m.deleted_at IS NULL) AS message_uses
             FROM songs s WHERE $where ORDER BY s.id DESC LIMIT " . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return ['songs' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** @return array{all:int, used:int, uses:int, pending:int, published:int, rejected:int, cancelled:int, withdrawn:int, removed:int} */
    public static function countsForArtist(int $artistId): array
    {
        $counts = array_fill_keys(array_keys(self::STATUSES), 0) + ['all' => 0, 'used' => 0, 'uses' => 0];
        $rows = self::fetchAll(
            'SELECT status, COUNT(*) AS n, SUM(uses_count > 0) AS used, SUM(uses_count) AS uses FROM songs WHERE artist_id = ? AND source <> \'original\' GROUP BY status',
            [$artistId]
        );
        foreach ($rows as $r) {
            $counts[$r['status']] = (int) $r['n'];
            $counts['all'] += (int) $r['n'];
            $counts['used'] += (int) $r['used'];
            $counts['uses'] += (int) $r['uses'];
        }
        return $counts;
    }

    /**
     * Publicaciones visibles que usan la canción (la más reciente primero).
     */
    public static function posts(int $songId, int $viewerId, array $paging): array
    {
        return Post::feed($viewerId, ['where' => 'p.song_id = ?', 'params' => [$songId]] + $paging);
    }

    // -------------------------------------------------------------------------
    // Escritura
    // -------------------------------------------------------------------------

    /** @param array{title:string, featuring:?string, genre:string, explicit:bool, audio:array, cover:?string} $data */
    public static function create(int $artistId, array $data): int
    {
        self::execute(
            'INSERT INTO songs (artist_id, title, featuring, genre, is_explicit, audio_path, audio_mime, size_bytes, duration_seconds, cover_path)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $artistId, $data['title'], $data['featuring'], $data['genre'], $data['explicit'] ? 1 : 0,
                $data['audio']['path'], $data['audio']['mime'], $data['audio']['size'], $data['audio']['duration'], $data['cover'],
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    /**
     * Guarda una pista de catálogo externo como canción publicada (no pasa por revisión: el catálogo ya la
     * distribuye; la moderación puede retirarla igual que cualquier otra). Si otra petición la guardó a la
     * vez, devuelve la existente.
     *
     * @param array{source:string, external_id:string, title:string, artist:string, genre:string, duration:int,
     *              audio_url:string, cover_url:?string, page_url:?string} $track
     */
    public static function createExternal(array $track): int
    {
        self::execute(
            "INSERT INTO songs (source, external_id, artist_id, external_artist, title, genre, audio_path, audio_mime, size_bytes,
                                duration_seconds, cover_path, external_url, status, published_at)
             VALUES (?, ?, NULL, ?, ?, ?, ?, 'audio/mpeg', 0, ?, ?, ?, 'published', NOW())
             ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)",
            [
                $track['source'], $track['external_id'], $track['artist'], $track['title'], $track['genre'], $track['audio_url'],
                $track['duration'], $track['cover_url'], $track['page_url'],
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    /**
     * Sonido original de un video: el audio es el propio video (se reproduce solo el sonido), a nombre de quien
     * lo publicó. Queda publicado al instante, como cualquier publicación.
     *
     * @param array{path:string, mime_type:string, size_bytes:int, duration_seconds:?int, poster_path:?string} $video
     */
    public static function createOriginal(int $userId, int $postId, array $video): int
    {
        self::execute(
            "INSERT INTO songs (source, artist_id, title, genre, audio_path, audio_mime, size_bytes, duration_seconds, cover_path,
                                origin_post_id, status, published_at)
             VALUES ('original', ?, 'Sonido original', 'other', ?, ?, ?, ?, ?, ?, 'published', NOW())",
            [
                $userId, $video['path'], $video['mime_type'], (int) $video['size_bytes'], max(1, (int) ($video['duration_seconds'] ?? 1)),
                $video['poster_path'] ?? null, $postId,
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    /**
     * Antes de borrar un video con sonido original: si otras publicaciones, historias o mensajes lo usan, el
     * sonido se queda con su propia copia del archivo; si no, se retira.
     */
    public static function releaseOrigin(int $postId): void
    {
        $song = self::fetchOne("SELECT id, audio_path FROM songs WHERE origin_post_id = ? AND source = 'original' LIMIT 1", [$postId]);
        if ($song === null) {
            return;
        }
        $copy = self::fetchValue('SELECT uses_count FROM songs WHERE id = ?', [(int) $song['id']]) > 1
            ? MediaUpload::duplicate((string) $song['audio_path'])
            : null;
        if ($copy !== null) {
            self::execute('UPDATE songs SET audio_path = ?, size_bytes = ?, cover_path = NULL, origin_post_id = NULL WHERE id = ?', [$copy['path'], $copy['size_bytes'], (int) $song['id']]);
        } else {
            self::execute("UPDATE songs SET status = 'removed', cover_path = NULL, origin_post_id = NULL WHERE id = ?", [(int) $song['id']]);
        }
    }

    /**
     * Cambia el estado solo si la canción sigue en uno de los estados de origen (evita carreras entre
     * el artista y la moderación). Devuelve true si cambió.
     *
     * @param list<string> $from
     */
    public static function transition(int $id, array $from, string $to, ?int $reviewerId = null, ?string $note = null): bool
    {
        $sets = 'status = ?';
        $params = [$to];
        if ($reviewerId !== null) {
            $sets .= ', reviewed_by = ?, reviewed_at = NOW(), review_note = ?';
            array_push($params, $reviewerId, $note);
        }
        if ($to === 'published') {
            $sets .= ', published_at = COALESCE(published_at, NOW())';
        }
        $params[] = $id;
        array_push($params, ...$from);
        return self::execute(
            "UPDATE songs SET $sets WHERE id = ? AND status IN (" . implode(',', array_fill(0, count($from), '?')) . ')',
            $params
        ) > 0;
    }

    /** Suma un uso (publicación, historia o mensaje). No se descuenta: es el historial de usos. */
    public static function incrementUses(int $id): void
    {
        self::execute('UPDATE songs SET uses_count = uses_count + 1 WHERE id = ?', [$id]);
    }

    /** Borra la canción y sus archivos. */
    public static function delete(array $song): void
    {
        self::execute('DELETE FROM songs WHERE id = ?', [(int) $song['id']]);
        if (($song['source'] ?? '') === 'original') {
            // Mientras el video exista, el audio es el propio video: solo se borra la copia propia del sonido.
            if (empty($song['origin_post_id'])) {
                MediaUpload::delete($song['audio_path'] ?? null);
            }
            return;
        }
        AudioUpload::delete($song['audio_path'] ?? null);
        ImageUpload::delete($song['cover_path'] ?? null);
    }

    /** Archivos de todas las canciones de un artista (para limpiar el disco al eliminar la cuenta). */
    public static function filesByArtist(int $artistId): array
    {
        $rows = self::fetchAll("SELECT audio_path, cover_path FROM songs WHERE artist_id = ? AND source <> 'original'", [$artistId]);
        return [
            'audio'  => array_column($rows, 'audio_path'),
            'covers' => array_values(array_filter(array_column($rows, 'cover_path'))),
        ];
    }

    // -------------------------------------------------------------------------
    // Panel de administración
    // -------------------------------------------------------------------------

    public static function pendingCount(): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM songs WHERE status = 'pending'");
    }

    /**
     * Canciones por estado y texto (título, invitados o @artista). Las pendientes, de la más antigua a la
     * más nueva (orden de llegada); el resto, de la más reciente a la más antigua.
     *
     * @return array{songs: list<array>, hasMore: bool}
     */
    public static function adminList(string $status, string $term, int $page, int $limit): array
    {
        $where = ['s.status = ?'];
        $params = [$status];
        $term = trim($term);
        if (str_starts_with($term, '@')) {
            $where[] = 'u.username = ?';
            $params[] = mb_strtolower(substr($term, 1));
        } elseif ($term !== '') {
            $like = '%' . self::likeEscape($term) . '%';
            $where[] = '(s.title LIKE ? OR s.featuring LIKE ? OR s.external_artist LIKE ?)';
            array_push($params, $like, $like, $like);
        }
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        $rows = self::fetchAll(
            'SELECT s.*, u.username, u.display_name, u.avatar_path, u.status AS artist_status, r.username AS reviewer_username
             FROM songs s LEFT JOIN users u ON u.id = s.artist_id LEFT JOIN users r ON r.id = s.reviewed_by
             WHERE ' . implode(' AND ', $where) . ' ORDER BY s.id ' . ($status === 'pending' ? 'ASC' : 'DESC')
            . ' LIMIT ' . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            $params
        );
        return ['songs' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** @return array<string,int> estado => cantidad */
    public static function adminCounts(): array
    {
        $counts = array_fill_keys(array_keys(self::STATUSES), 0);
        foreach (self::fetchAll('SELECT status, COUNT(*) AS n FROM songs GROUP BY status') as $r) {
            $counts[$r['status']] = (int) $r['n'];
        }
        return $counts;
    }

    // -------------------------------------------------------------------------

    private static function notBlocked(): string
    {
        return 'NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ? AND b.blocked_id = s.artist_id) OR (b.blocker_id = s.artist_id AND b.blocked_id = ?))';
    }

    private static function card(array $r): array
    {
        $external = $r['artist_id'] === null;
        return [
            'id'          => (int) $r['id'],
            'available'   => true,
            'source'      => $r['source'],
            'source_label' => t(self::SOURCES[$r['source']] ?? 'TREVIX'),
            'external_url' => $r['external_url'],
            'title'       => $r['source'] === 'original' ? t('Sonido original') : $r['title'],
            'origin_post_id' => isset($r['origin_post_id']) ? (int) $r['origin_post_id'] : null,
            'featuring'   => $r['featuring'],
            'genre'       => $r['genre'],
            'is_explicit' => (bool) $r['is_explicit'],
            'duration'    => (int) $r['duration_seconds'],
            'src'         => $r['audio_path'],
            'mime'        => $r['audio_mime'],
            'cover'       => $r['cover_path'],
            'uses_count'  => (int) $r['uses_count'],
            'published_at' => $r['published_at'],
            'artist'      => $external
                ? ['id' => 0, 'username' => null, 'display_name' => (string) $r['external_artist'], 'avatar_path' => null, 'is_verified' => false]
                : [
                    'id'           => (int) $r['artist_id'],
                    'username'     => $r['username'],
                    'display_name' => $r['display_name'],
                    'avatar_path'  => $r['avatar_path'],
                    'is_verified'  => (bool) $r['is_verified'],
                ],
        ];
    }
}
