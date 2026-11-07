-- TREVIX · Fase 8 (API v1 para la app móvil)
-- Solo para bases creadas antes de la Fase 8; trevix_db.sql ya incluye estos cambios.

CREATE TABLE IF NOT EXISTS api_tokens (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    name         VARCHAR(80)     NOT NULL,
    token_hash   CHAR(64)        NOT NULL,
    password_fp  CHAR(64)        NOT NULL,
    last_used_at DATETIME        NULL,
    last_ip      VARBINARY(16)   NULL,
    expires_at   DATETIME        NOT NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_api_tokens_hash (token_hash),
    KEY idx_api_tokens_user (user_id),
    KEY idx_api_tokens_expires (expires_at),
    CONSTRAINT fk_api_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
