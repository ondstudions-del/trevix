-- Privacidad de listas de conexiones + vinculación de dispositivos por QR.
ALTER TABLE users
  ADD COLUMN connections_privacy ENUM('everyone', 'followers', 'nobody') NOT NULL DEFAULT 'everyone'
    COMMENT 'Quién ve seguidores y siguiendo: everyone, followers o nobody (solo yo)'
    AFTER message_privacy;

ALTER TABLE api_tokens
  ADD COLUMN device_type VARCHAR(20) NULL COMMENT 'phone, tablet, web, desktop, other' AFTER name;

CREATE TABLE IF NOT EXISTS device_link_challenges (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    code            CHAR(8)         NOT NULL COMMENT 'Código corto para QR y entrada manual',
    host_user_id    BIGINT UNSIGNED NOT NULL,
    status          ENUM('pending', 'claimed', 'approved', 'expired', 'cancelled') NOT NULL DEFAULT 'pending',
    guest_device_name VARCHAR(120)  NULL,
    guest_device_type VARCHAR(20)   NULL,
    guest_ip        VARCHAR(45)     NULL,
    token_plain     VARCHAR(96)     NULL COMMENT 'Token trx_ emitido al aprobar (solo se envía una vez al guest)',
    token_id        BIGINT UNSIGNED NULL,
    expires_at      DATETIME        NOT NULL,
    claimed_at      DATETIME        NULL,
    approved_at     DATETIME        NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_device_link_code (code),
    KEY idx_device_link_host (host_user_id, status),
    KEY idx_device_link_expires (expires_at),
    CONSTRAINT fk_device_link_host FOREIGN KEY (host_user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_device_link_token FOREIGN KEY (token_id) REFERENCES api_tokens (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
