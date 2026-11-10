-- TREVIX · IX, la inteligencia artificial de atención al cliente en el chat de la cuenta de soporte (@soport).
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Mensajes que escribió IX (los de la cuenta de soporte con 0 los escribió una persona del equipo y pausan a IX).
ALTER TABLE messages ADD COLUMN sent_by_ix TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Lo escribió IX desde la cuenta de soporte' AFTER forwarded;

-- Solicitudes que IX clasificó para el equipo (panel › Soporte IX).
CREATE TABLE IF NOT EXISTS support_tickets (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NOT NULL,
    conversation_id BIGINT UNSIGNED NULL,
    message_id      BIGINT UNSIGNED NULL COMMENT 'Último mensaje de la persona que la actualizó',
    category        ENUM('pregunta', 'saludo', 'error', 'sugerencia', 'reporte', 'queja', 'reclamo', 'peticion', 'otro') NOT NULL DEFAULT 'otro',
    priority        ENUM('baja', 'media', 'alta') NOT NULL DEFAULT 'media',
    summary         VARCHAR(255)    NOT NULL DEFAULT '',
    excerpt         VARCHAR(500)    NOT NULL DEFAULT '',
    needs_human     TINYINT(1)      NOT NULL DEFAULT 0,
    status          ENUM('open', 'closed') NOT NULL DEFAULT 'open',
    closed_by       BIGINT UNSIGNED NULL,
    closed_at       DATETIME        NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_support_tickets_status (status, needs_human, updated_at),
    KEY idx_support_tickets_user (user_id, status, category, updated_at),
    CONSTRAINT fk_support_tickets_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_support_tickets_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE SET NULL,
    CONSTRAINT fk_support_tickets_closer FOREIGN KEY (closed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- La cuenta de soporte no usa cifrado de extremo a extremo: IX tiene que poder leer sus chats.
DELETE FROM user_keys WHERE user_id IN (SELECT id FROM users WHERE username = 'soport');
