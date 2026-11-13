-- TREVIX · Alpha 1.5: portada propia de los sonidos originales, intereses por hashtag para «Para ti», tiempo visto
-- de cada publicación y listas de reproducción de reels de los creadores de contenido.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

ALTER TABLE songs
    ADD COLUMN cover_custom TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'La portada la subió quien publicó el sonido (no es el póster del video)' AFTER cover_path;

ALTER TABLE post_views
    ADD COLUMN watched_seconds SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Lo más largo que la persona la tuvo en pantalla' AFTER user_id;

-- Interés de cada persona por cada hashtag: sube al dar me gusta, comentar, guardar, compartir o ver mucho tiempo
-- una publicación con esa etiqueta, y se va enfriando con los días (InterestService).
CREATE TABLE IF NOT EXISTS hashtag_interests (
    user_id     BIGINT UNSIGNED NOT NULL,
    hashtag_id  BIGINT UNSIGNED NOT NULL,
    score       FLOAT           NOT NULL DEFAULT 0,
    updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, hashtag_id),
    KEY idx_hashtag_interests_top (user_id, score),
    CONSTRAINT fk_hashtag_interests_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_hashtag_interests_tag FOREIGN KEY (hashtag_id) REFERENCES hashtags (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Listas de reproducción de reels (solo creadores de contenido). Los videos se ven en el orden en que se
-- agregaron a la lista.
CREATE TABLE IF NOT EXISTS playlists (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    title        VARCHAR(80)     NOT NULL,
    description  VARCHAR(300)    NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_playlists_user (user_id, created_at),
    CONSTRAINT fk_playlists_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS playlist_posts (
    playlist_id  BIGINT UNSIGNED NOT NULL,
    post_id      BIGINT UNSIGNED NOT NULL,
    added_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (playlist_id, post_id),
    KEY idx_playlist_posts_order (playlist_id, added_at),
    KEY idx_playlist_posts_post (post_id),
    CONSTRAINT fk_playlist_posts_list FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
    CONSTRAINT fk_playlist_posts_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
