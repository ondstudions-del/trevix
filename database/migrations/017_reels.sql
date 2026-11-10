-- Reels: miniatura de los videos de publicaciones y búsqueda rápida de las publicaciones con video.
ALTER TABLE post_media
    ADD COLUMN poster_path VARCHAR(255) NULL AFTER path,
    ADD KEY idx_post_media_type (type, post_id);
