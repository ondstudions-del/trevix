-- TREVIX · Catálogos de música externos (Audius y Free To Use), GIF y stickers de GIPHY, notas de voz
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Canciones de catálogos externos: se guardan al elegirlas por primera vez (source + external_id únicos),
-- sin cuenta de artista en TREVIX (artist_id NULL) y con el audio y la portada servidos por el catálogo.
ALTER TABLE songs
    ADD COLUMN source ENUM('trevix', 'audius', 'freetouse') NOT NULL DEFAULT 'trevix' AFTER id,
    ADD COLUMN external_id VARCHAR(64) NULL AFTER source,
    MODIFY artist_id BIGINT UNSIGNED NULL,
    ADD COLUMN external_artist VARCHAR(160) NULL AFTER artist_id,
    MODIFY audio_path VARCHAR(500) NOT NULL,
    MODIFY cover_path VARCHAR(500) NULL,
    ADD COLUMN external_url VARCHAR(500) NULL AFTER cover_path,
    ADD UNIQUE KEY uq_songs_external (source, external_id),
    ADD KEY idx_songs_source (source, status, published_at);

-- GIF o sticker de GIPHY en comentarios (el texto pasa a ser opcional si hay GIF).
ALTER TABLE comments
    ADD COLUMN gif_id VARCHAR(64) NULL AFTER body,
    ADD COLUMN gif_kind ENUM('gif', 'sticker') NULL AFTER gif_id,
    ADD COLUMN gif_url VARCHAR(500) NULL AFTER gif_kind,
    ADD COLUMN gif_width SMALLINT UNSIGNED NULL AFTER gif_url,
    ADD COLUMN gif_height SMALLINT UNSIGNED NULL AFTER gif_width,
    ADD COLUMN gif_title VARCHAR(140) NULL AFTER gif_height;

-- Mensajes: GIF o sticker y notas de voz (media_mime audio/* con su duración en segundos).
ALTER TABLE messages
    ADD COLUMN media_duration SMALLINT UNSIGNED NULL AFTER media_mime,
    ADD COLUMN gif_id VARCHAR(64) NULL AFTER song_id,
    ADD COLUMN gif_kind ENUM('gif', 'sticker') NULL AFTER gif_id,
    ADD COLUMN gif_url VARCHAR(500) NULL AFTER gif_kind,
    ADD COLUMN gif_width SMALLINT UNSIGNED NULL AFTER gif_url,
    ADD COLUMN gif_height SMALLINT UNSIGNED NULL AFTER gif_width,
    ADD COLUMN gif_title VARCHAR(140) NULL AFTER gif_height;
