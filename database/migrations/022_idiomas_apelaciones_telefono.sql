-- TREVIX · Idioma de la interfaz, teléfono privado, apelaciones de sanciones y traducciones de publicaciones con IA.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

ALTER TABLE users
    ADD COLUMN phone  VARCHAR(20) NULL COMMENT 'Privado: solo lo ven la persona y la administración' AFTER email,
    ADD COLUMN locale CHAR(2)     NULL COMMENT 'Idioma de la interfaz (es, en); NULL = el del navegador' AFTER country;

-- Apelaciones: una suspensión (se envía con usuario y contraseña desde el inicio de sesión) o una advertencia.
CREATE TABLE IF NOT EXISTS appeals (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED NOT NULL,
    type             ENUM('suspension', 'warning') NOT NULL,
    warning_id       BIGINT UNSIGNED NULL,
    sanction_reason  VARCHAR(255)    NULL COMMENT 'Motivo de la sanción cuando se apeló',
    message          VARCHAR(1000)   NOT NULL,
    status           ENUM('pending', 'accepted', 'rejected') NOT NULL DEFAULT 'pending',
    reviewed_by      BIGINT UNSIGNED NULL,
    reviewed_at      DATETIME        NULL,
    resolution_note  VARCHAR(500)    NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_appeals_status (status, created_at),
    KEY idx_appeals_user (user_id, created_at),
    CONSTRAINT fk_appeals_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_appeals_warning FOREIGN KEY (warning_id) REFERENCES user_warnings (id) ON DELETE CASCADE,
    CONSTRAINT fk_appeals_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE notifications MODIFY COLUMN type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
    'community', 'community_request', 'community_accepted', 'system',
    'song_approved', 'song_rejected', 'song_removed',
    'story_mention', 'event_going', 'featured',
    'warning', 'verification_approved', 'verification_rejected',
    'appeal_accepted', 'appeal_rejected') NOT NULL;

-- Traducción con IA de una publicación a un idioma; source_hash invalida la copia si se edita el texto.
CREATE TABLE IF NOT EXISTS post_translations (
    post_id      BIGINT UNSIGNED NOT NULL,
    target_lang  CHAR(2)         NOT NULL,
    source_lang  VARCHAR(8)      NULL,
    source_hash  CHAR(40)        NOT NULL,
    body         TEXT            NOT NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, target_lang),
    CONSTRAINT fk_post_translations_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
