-- TREVIX · Videos en los chats, entregas e info de los mensajes, confirmación de lectura y notas con vistas,
-- me gusta, sticker y canción.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.
-- Una columna por sentencia: si la migración se corta, se puede volver a ejecutar.

-- Videos del chat (normales y de visualización única): tamaño y miniatura (los de visualización única no la tienen).
ALTER TABLE messages ADD COLUMN media_width SMALLINT UNSIGNED NULL AFTER media_size;
ALTER TABLE messages ADD COLUMN media_height SMALLINT UNSIGNED NULL AFTER media_width;
ALTER TABLE messages ADD COLUMN media_poster VARCHAR(255) NULL AFTER media_height;

-- Último mensaje entregado a cada participante (su app o la web consultaron sus chats), para «Info» del mensaje.
ALTER TABLE conversation_participants ADD COLUMN last_delivered_message_id BIGINT UNSIGNED NULL AFTER last_read_message_id;

-- Confirmación de lectura (recíproca): con 0, la cuenta no muestra que leyó ni ve quién leyó sus mensajes.
ALTER TABLE users ADD COLUMN read_receipts TINYINT(1) NOT NULL DEFAULT 1 AFTER show_activity;

-- Notas: el texto pasa a ser opcional (puede llevar solo un sticker o una canción).
ALTER TABLE user_notes MODIFY body VARCHAR(60) NOT NULL DEFAULT '';
ALTER TABLE user_notes ADD COLUMN gif_id VARCHAR(64) NULL AFTER audience;
ALTER TABLE user_notes ADD COLUMN gif_kind ENUM('gif', 'sticker') NULL AFTER gif_id;
ALTER TABLE user_notes ADD COLUMN gif_url VARCHAR(500) NULL AFTER gif_kind;
ALTER TABLE user_notes ADD COLUMN gif_width SMALLINT UNSIGNED NULL AFTER gif_url;
ALTER TABLE user_notes ADD COLUMN gif_height SMALLINT UNSIGNED NULL AFTER gif_width;
ALTER TABLE user_notes ADD COLUMN gif_title VARCHAR(140) NULL AFTER gif_height;
ALTER TABLE user_notes ADD COLUMN song_id BIGINT UNSIGNED NULL AFTER gif_title;
ALTER TABLE user_notes ADD COLUMN song_start SMALLINT UNSIGNED NULL AFTER song_id;
ALTER TABLE user_notes ADD CONSTRAINT fk_user_notes_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL;

-- Quién vio cada nota (quien la publicó no cuenta) y quién le dio me gusta. Se borran con la nota.
CREATE TABLE IF NOT EXISTS note_views (
    note_id    BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    viewed_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (note_id, user_id),
    KEY idx_note_views_user (user_id),
    CONSTRAINT fk_note_views_note FOREIGN KEY (note_id) REFERENCES user_notes (id) ON DELETE CASCADE,
    CONSTRAINT fk_note_views_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS note_likes (
    note_id    BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (note_id, user_id),
    KEY idx_note_likes_user (user_id),
    CONSTRAINT fk_note_likes_note FOREIGN KEY (note_id) REFERENCES user_notes (id) ON DELETE CASCADE,
    CONSTRAINT fk_note_likes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
