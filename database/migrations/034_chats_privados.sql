-- TREVIX · Chats privados con PIN (Alpha 1.9).
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Chat privado para este participante: no sale en la bandeja, la búsqueda, los avisos con nombre ni los destinos
-- para compartir; se abre escribiendo el PIN en el buscador de los chats.
ALTER TABLE conversation_participants ADD COLUMN private_at DATETIME NULL COMMENT 'Chat privado: fuera de la bandeja, se abre con el PIN' AFTER hidden_at;
ALTER TABLE conversation_participants ADD KEY idx_participants_private (user_id, private_at);

-- PIN de los chats privados (hash). Al cambiarlo dejan de valer los desbloqueos anteriores.
CREATE TABLE IF NOT EXISTS private_chat_pins (
    user_id    BIGINT UNSIGNED NOT NULL,
    pin_hash   VARCHAR(255)    NOT NULL,
    created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_private_pins_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
