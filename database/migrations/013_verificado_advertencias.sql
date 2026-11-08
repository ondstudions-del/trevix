-- TREVIX · Advertencias de moderación y solicitudes de verificado.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Advertencias que el equipo da a una cuenta. Las que tienen menos de 30 días y no se retiraron impiden pedir
-- el verificado. target_*: lo que motivó la advertencia (publicación, comentario, mensaje, historia o la cuenta).
CREATE TABLE IF NOT EXISTS user_warnings (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    issued_by    BIGINT UNSIGNED NULL,
    reason       VARCHAR(255)    NOT NULL,
    target_type  VARCHAR(20)     NULL,
    target_id    BIGINT UNSIGNED NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at   DATETIME        NULL,
    revoked_by   BIGINT UNSIGNED NULL,
    PRIMARY KEY (id),
    KEY idx_user_warnings_user (user_id, created_at),
    CONSTRAINT fk_user_warnings_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_warnings_issuer FOREIGN KEY (issued_by) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_user_warnings_revoker FOREIGN KEY (revoked_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Solicitudes de verificado. Guardan las cifras con las que se pidió (seguidores, promedio de Me gusta y
-- publicaciones contadas) para que el equipo vea por qué cumplía.
CREATE TABLE IF NOT EXISTS verification_requests (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED NOT NULL,
    category         ENUM('creator', 'artist', 'public_figure', 'brand', 'journalist', 'athlete', 'other') NOT NULL,
    full_name        VARCHAR(80)     NOT NULL,
    note             VARCHAR(500)    NULL,
    followers_count  INT UNSIGNED    NOT NULL DEFAULT 0,
    avg_likes        INT UNSIGNED    NOT NULL DEFAULT 0,
    posts_counted    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    status           ENUM('pending', 'approved', 'rejected', 'cancelled') NOT NULL DEFAULT 'pending',
    reviewed_by      BIGINT UNSIGNED NULL,
    reviewed_at      DATETIME        NULL,
    decision_note    VARCHAR(255)    NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_verification_status (status, created_at),
    KEY idx_verification_user (user_id, created_at),
    CONSTRAINT fk_verification_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Avisos del equipo (sin persona que actúe): advertencia, verificado aprobado o rechazado.
-- ref_id: la advertencia o la solicitud a la que se refiere el aviso.
ALTER TABLE notifications
    MODIFY type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
                     'community', 'community_request', 'community_accepted', 'system',
                     'song_approved', 'song_rejected', 'song_removed',
                     'story_mention', 'event_going', 'featured',
                     'warning', 'verification_approved', 'verification_rejected') NOT NULL;

ALTER TABLE notifications ADD COLUMN ref_id BIGINT UNSIGNED NULL AFTER song_id;
