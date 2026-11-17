-- Quién puede escribir en un grupo + encuestas en chats.
ALTER TABLE conversations
  ADD COLUMN send_policy ENUM('all', 'admins') NOT NULL DEFAULT 'all'
    COMMENT 'Grupos: all = todos escriben; admins = solo administradores'
    AFTER visibility;

ALTER TABLE messages
  ADD COLUMN poll JSON NULL COMMENT 'Encuesta: {"q":"…","opts":["a","b"],"multi":false}' AFTER body;

CREATE TABLE IF NOT EXISTS message_poll_votes (
    message_id   BIGINT UNSIGNED NOT NULL,
    user_id      BIGINT UNSIGNED NOT NULL,
    option_index TINYINT UNSIGNED NOT NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id),
    KEY idx_message_poll_votes_option (message_id, option_index),
    CONSTRAINT fk_message_poll_votes_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_message_poll_votes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
