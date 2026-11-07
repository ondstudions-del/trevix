-- TREVIX · Cuentas de creador y música de artistas
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Tipo de cuenta: personal o creador de contenido (con su categoría).
ALTER TABLE users
    ADD COLUMN account_type ENUM('personal', 'creator') NOT NULL DEFAULT 'personal' AFTER is_verified,
    ADD COLUMN creator_category ENUM('music_artist', 'influencer', 'blogger', 'other') NULL AFTER account_type;

-- Canciones que suben los artistas. Pasan por revisión del equipo antes de llegar a la biblioteca.
CREATE TABLE IF NOT EXISTS songs (
    id                BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    artist_id         BIGINT UNSIGNED   NOT NULL,
    title             VARCHAR(100)      NOT NULL,
    featuring         VARCHAR(120)      NULL,
    genre             VARCHAR(30)       NOT NULL,
    is_explicit       TINYINT(1)        NOT NULL DEFAULT 0,
    audio_path        VARCHAR(255)      NOT NULL,
    audio_mime        VARCHAR(50)       NOT NULL,
    size_bytes        INT UNSIGNED      NOT NULL,
    duration_seconds  SMALLINT UNSIGNED NOT NULL,
    cover_path        VARCHAR(255)      NULL,
    status            ENUM('pending', 'published', 'rejected', 'cancelled', 'withdrawn', 'removed') NOT NULL DEFAULT 'pending',
    review_note       VARCHAR(255)      NULL,
    reviewed_by       BIGINT UNSIGNED   NULL,
    reviewed_at       DATETIME          NULL,
    published_at      DATETIME          NULL,
    uses_count        INT UNSIGNED      NOT NULL DEFAULT 0,
    created_at        DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_songs_artist (artist_id, status, created_at),
    KEY idx_songs_status_published (status, published_at),
    KEY idx_songs_status_uses (status, uses_count),
    CONSTRAINT fk_songs_artist FOREIGN KEY (artist_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_songs_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Canción adjunta (song_start = segundo en que empieza el fragmento de publicaciones e historias).
ALTER TABLE posts
    ADD COLUMN song_id BIGINT UNSIGNED NULL AFTER shared_post_id,
    ADD COLUMN song_start SMALLINT UNSIGNED NULL AFTER song_id,
    ADD KEY idx_posts_song (song_id, created_at),
    ADD CONSTRAINT fk_posts_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL;

ALTER TABLE stories
    ADD COLUMN song_id BIGINT UNSIGNED NULL AFTER background,
    ADD COLUMN song_start SMALLINT UNSIGNED NULL AFTER song_id,
    ADD KEY idx_stories_song (song_id),
    ADD CONSTRAINT fk_stories_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL;

ALTER TABLE messages
    ADD COLUMN song_id BIGINT UNSIGNED NULL AFTER story_id,
    ADD KEY idx_messages_song (song_id),
    ADD CONSTRAINT fk_messages_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL;

-- Avisos de la revisión de canciones (los envía TREVIX, sin persona que actúe).
ALTER TABLE notifications
    MODIFY type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
                     'community', 'community_request', 'community_accepted', 'system',
                     'song_approved', 'song_rejected', 'song_removed') NOT NULL,
    ADD COLUMN song_id BIGINT UNSIGNED NULL AFTER community_id,
    ADD CONSTRAINT fk_notifications_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE;
