-- TREVIX · Alpha 1.3: sonidos originales (el audio de un video publicado, a nombre de quien lo subió, que otros
-- pueden usar en sus videos, historias, notas, publicaciones y perfil) e historias «Solo yo» (Guardado › Solo yo).
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

ALTER TABLE songs
    MODIFY COLUMN source ENUM('trevix', 'audius', 'freetouse', 'original') NOT NULL DEFAULT 'trevix',
    ADD COLUMN origin_post_id BIGINT UNSIGNED NULL AFTER external_url,
    ADD KEY idx_songs_origin (origin_post_id);

ALTER TABLE stories
    ADD COLUMN is_private TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Solo yo: nadie más la ve y no se borra al vencer (Guardado › Solo yo)' AFTER is_live,
    ADD KEY idx_stories_private (user_id, is_private, created_at);
