-- TREVIX · Chat de la app: reacciones, respuestas, reenviar, eliminar para ti, fijar, ubicación, mensajes
-- temporales, apodos y estilo del chat. Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- kind: «system» son los avisos dentro del chat (p. ej. «activó los mensajes temporales»; body = código del aviso).
-- expires_at: mensajes temporales; al caducar se vacían y dejan de mostrarse. updated_at: reacciones, fijados o
-- borrados, para que el sondeo de la app actualice los mensajes ya cargados.
ALTER TABLE messages ADD COLUMN kind ENUM('message', 'system') NOT NULL DEFAULT 'message' AFTER sender_id;
ALTER TABLE messages ADD COLUMN reply_to_id BIGINT UNSIGNED NULL AFTER kind;
ALTER TABLE messages ADD COLUMN forwarded TINYINT(1) NOT NULL DEFAULT 0 AFTER reply_to_id;
ALTER TABLE messages ADD COLUMN location_lat DECIMAL(9,6) NULL AFTER gif_title;
ALTER TABLE messages ADD COLUMN location_lng DECIMAL(9,6) NULL AFTER location_lat;
ALTER TABLE messages ADD COLUMN location_name VARCHAR(120) NULL AFTER location_lng;
ALTER TABLE messages ADD COLUMN pinned_at DATETIME NULL AFTER location_name;
ALTER TABLE messages ADD COLUMN pinned_by BIGINT UNSIGNED NULL AFTER pinned_at;
ALTER TABLE messages ADD COLUMN expires_at DATETIME NULL AFTER pinned_by;
ALTER TABLE messages ADD COLUMN updated_at DATETIME NULL ON UPDATE CURRENT_TIMESTAMP AFTER deleted_at;
ALTER TABLE messages ADD KEY idx_messages_expires (expires_at);
ALTER TABLE messages ADD KEY idx_messages_updated (conversation_id, updated_at);

-- Mensajes temporales de la conversación (segundos; NULL = desactivados). Lo decide cualquiera de los dos.
ALTER TABLE conversations ADD COLUMN disappear_seconds INT UNSIGNED NULL AFTER last_message_at;

-- Apodo de la otra persona y fondo del chat: solo los ve quien los pone.
ALTER TABLE conversation_participants ADD COLUMN nickname VARCHAR(40) NULL AFTER is_muted;
ALTER TABLE conversation_participants ADD COLUMN wallpaper VARCHAR(30) NULL AFTER nickname;

-- Una reacción por persona y mensaje.
CREATE TABLE IF NOT EXISTS message_reactions (
    message_id  BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    emoji       VARCHAR(32)     NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id),
    KEY idx_message_reactions_user (user_id),
    CONSTRAINT fk_message_reactions_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_message_reactions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- «Eliminar para ti»: el mensaje deja de mostrarse solo a esa persona.
CREATE TABLE IF NOT EXISTS message_hidden (
    user_id     BIGINT UNSIGNED NOT NULL,
    message_id  BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, message_id),
    KEY idx_message_hidden_message (message_id),
    CONSTRAINT fk_message_hidden_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_message_hidden_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
