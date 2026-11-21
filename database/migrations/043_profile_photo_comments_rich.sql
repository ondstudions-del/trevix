-- Respuestas, GIF/foto y reacciones en comentarios de foto de perfil/portada.
ALTER TABLE profile_photo_comments
    ADD COLUMN parent_id BIGINT UNSIGNED NULL AFTER user_id,
    ADD COLUMN gif_id VARCHAR(64) NULL AFTER body,
    ADD COLUMN gif_kind VARCHAR(20) NULL AFTER gif_id,
    ADD COLUMN gif_url VARCHAR(500) NULL AFTER gif_kind,
    ADD COLUMN gif_width INT UNSIGNED NULL AFTER gif_url,
    ADD COLUMN gif_height INT UNSIGNED NULL AFTER gif_width,
    ADD COLUMN gif_title VARCHAR(255) NULL AFTER gif_height,
    ADD COLUMN media_path VARCHAR(500) NULL AFTER gif_title,
    ADD COLUMN media_width INT UNSIGNED NULL AFTER media_path,
    ADD COLUMN media_height INT UNSIGNED NULL AFTER media_width,
    ADD KEY idx_profile_photo_comments_parent (owner_id, kind, parent_id, id),
    ADD CONSTRAINT fk_profile_photo_comments_parent
        FOREIGN KEY (parent_id) REFERENCES profile_photo_comments (id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS profile_photo_comment_reactions (
    comment_id BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    value      ENUM('like', 'dislike') NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (comment_id, user_id),
    KEY idx_ppc_reactions_user (user_id),
    CONSTRAINT fk_ppc_reactions_comment FOREIGN KEY (comment_id) REFERENCES profile_photo_comments (id) ON DELETE CASCADE,
    CONSTRAINT fk_ppc_reactions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
