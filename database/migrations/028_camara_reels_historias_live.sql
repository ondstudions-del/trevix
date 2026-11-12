-- TREVIX · Alpha 1.2: filtro y canción sincronizada en los videos grabados con la cámara de reels, e historias con
-- foto en movimiento (Live Photo de iPhone o foto en movimiento de Android). Solo para bases creadas antes de este
-- cambio; trevix_db.sql ya lo incluye.

ALTER TABLE post_media
    ADD COLUMN filter    VARCHAR(20) NULL COMMENT 'Filtro de color (StoryOverlays::FILTERS) que se aplica al mostrarla' AFTER alt_text,
    ADD COLUMN song_sync TINYINT(1)  NOT NULL DEFAULT 0 COMMENT 'Video grabado sobre la canción de la publicación: sin sonido propio, la canción suena desde song_start al compás del video' AFTER filter;

ALTER TABLE stories
    ADD COLUMN is_live TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Foto en movimiento: el video corto se repite en bucle con la etiqueta LIVE' AFTER filter;
