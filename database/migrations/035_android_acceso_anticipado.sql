-- TREVIX · Acceso anticipado para Android (lista de verificadores / testers).
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

CREATE TABLE IF NOT EXISTS android_early_access (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name        VARCHAR(120)    NOT NULL,
    email            VARCHAR(190)    NOT NULL,
    status           ENUM('pending', 'accepted', 'rejected') NOT NULL DEFAULT 'pending',
    reviewed_by      BIGINT UNSIGNED NULL,
    reviewed_at      DATETIME        NULL,
    resolution_note  VARCHAR(500)    NULL,
    ip               VARBINARY(16)   NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_android_early_email (email),
    KEY idx_android_early_status (status, id),
    CONSTRAINT fk_android_early_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
