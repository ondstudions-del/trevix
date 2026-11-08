-- TREVIX · Publicaciones destacadas, lugar, fondos de color, GIF, acontecimientos importantes, eventos
-- y editor de historias (texto, stickers, ubicación, encuesta, menciones, enlace y filtros).
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Eventos: portada, fecha y hora, lugar y descripción. Se publican en el inicio como una publicación (posts.event_id).
CREATE TABLE IF NOT EXISTS events (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED NOT NULL,
    title            VARCHAR(120)    NOT NULL,
    description      TEXT            NULL,
    place            VARCHAR(160)    NOT NULL,
    starts_at        DATETIME        NOT NULL,
    ends_at          DATETIME        NULL,
    cover_path       VARCHAR(255)    NULL,
    going_count      INT UNSIGNED    NOT NULL DEFAULT 0,
    interested_count INT UNSIGNED    NOT NULL DEFAULT 0,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_events_starts (starts_at),
    KEY idx_events_user (user_id, starts_at),
    CONSTRAINT fk_events_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- «Asistiré» (going) o «Me interesa» (interested): una respuesta por persona y evento.
CREATE TABLE IF NOT EXISTS event_responses (
    event_id    BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    status      ENUM('going', 'interested') NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id, user_id),
    KEY idx_event_responses_user (user_id),
    CONSTRAINT fk_event_responses_event FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
    CONSTRAINT fk_event_responses_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- background: fondo de color de un hilo (mismas claves que las historias de texto).
-- location_*: lugar elegido al publicar (nombre visible; coordenadas redondeadas a ~100 m).
-- gif_*: GIF o sticker de GIPHY publicado. life_event: acontecimiento importante (trabajo, mudanza, graduación…).
-- featured_at / featured_by: publicación destacada por la administración.
ALTER TABLE posts
    ADD COLUMN event_id BIGINT UNSIGNED NULL AFTER song_start,
    ADD COLUMN background VARCHAR(30) NULL AFTER format,
    ADD COLUMN life_event VARCHAR(30) NULL AFTER background,
    ADD COLUMN location_name VARCHAR(120) NULL AFTER body,
    ADD COLUMN location_lat DECIMAL(8,5) NULL AFTER location_name,
    ADD COLUMN location_lng DECIMAL(8,5) NULL AFTER location_lat,
    ADD COLUMN gif_id VARCHAR(64) NULL AFTER location_lng,
    ADD COLUMN gif_kind ENUM('gif', 'sticker') NULL AFTER gif_id,
    ADD COLUMN gif_url VARCHAR(500) NULL AFTER gif_kind,
    ADD COLUMN gif_width SMALLINT UNSIGNED NULL AFTER gif_url,
    ADD COLUMN gif_height SMALLINT UNSIGNED NULL AFTER gif_width,
    ADD COLUMN gif_title VARCHAR(140) NULL AFTER gif_height,
    ADD COLUMN featured_at DATETIME NULL AFTER saves_count,
    ADD COLUMN featured_by BIGINT UNSIGNED NULL AFTER featured_at,
    ADD KEY idx_posts_featured (featured_at),
    ADD KEY idx_posts_event (event_id),
    ADD CONSTRAINT fk_posts_event FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_posts_featured_by FOREIGN KEY (featured_by) REFERENCES users (id) ON DELETE SET NULL;

-- Historias con foto o video: capas (texto, stickers de GIPHY, ubicación, encuesta, menciones y enlace) y filtro.
ALTER TABLE stories
    ADD COLUMN overlays JSON NULL AFTER background,
    ADD COLUMN filter VARCHAR(20) NULL AFTER overlays;

CREATE TABLE IF NOT EXISTS story_poll_votes (
    story_id    BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    choice      TINYINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (story_id, user_id),
    KEY idx_story_poll_votes_user (user_id),
    CONSTRAINT fk_story_poll_votes_story FOREIGN KEY (story_id) REFERENCES stories (id) ON DELETE CASCADE,
    CONSTRAINT fk_story_poll_votes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Avisos nuevos: te mencionaron en una historia, alguien asistirá a tu evento (post_id = publicación del evento),
-- la administración destacó tu publicación.
ALTER TABLE notifications
    MODIFY type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
                     'community', 'community_request', 'community_accepted', 'system',
                     'song_approved', 'song_rejected', 'song_removed',
                     'story_mention', 'event_going', 'featured') NOT NULL;
