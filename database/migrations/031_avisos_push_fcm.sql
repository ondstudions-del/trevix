-- TREVIX · Avisos con la app cerrada por Firebase Cloud Messaging (Android e iPhone) y envíos desde el panel.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Teléfonos que reciben avisos por Firebase. Cada token es de un teléfono y de la sesión de la API con la que se
-- registró: al cerrar o revocar esa sesión el teléfono deja de recibir avisos (ON DELETE CASCADE). En iPhone se
-- guardan los cursores de lo ya avisado para no repetir nada.
CREATE TABLE IF NOT EXISTS push_devices (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    token_id     BIGINT UNSIGNED NOT NULL,
    platform     ENUM('android','ios') NOT NULL,
    fcm_token    VARCHAR(400)    CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    app_version  VARCHAR(20)     NULL,
    locale       CHAR(2)         NULL COMMENT 'Idioma de la app en ese teléfono (textos de los avisos de iPhone)',
    cursor_json  VARCHAR(255)    NULL,
    last_error   VARCHAR(40)     NULL COMMENT 'Último error de Firebase con este teléfono (NULL si el último envío llegó)',
    failures     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    last_sent_at DATETIME        NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_push_devices_token (fcm_token),
    KEY idx_push_devices_user (user_id),
    KEY idx_push_devices_session (token_id),
    KEY idx_push_devices_platform (platform, id),
    CONSTRAINT fk_push_devices_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_push_devices_session FOREIGN KEY (token_id) REFERENCES api_tokens (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Avisos enviados desde el panel de administración (a una persona o masivos) y su resultado.
CREATE TABLE IF NOT EXISTS push_campaigns (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    admin_id       BIGINT UNSIGNED NULL,
    title          VARCHAR(80)     NOT NULL,
    body           VARCHAR(240)    NOT NULL,
    link           VARCHAR(255)    NULL,
    audience       ENUM('user','all','android','ios') NOT NULL,
    target_user_id BIGINT UNSIGNED NULL,
    status         ENUM('sending','done','failed') NOT NULL DEFAULT 'sending',
    total          INT UNSIGNED    NOT NULL DEFAULT 0,
    sent           INT UNSIGNED    NOT NULL DEFAULT 0,
    failed         INT UNSIGNED    NOT NULL DEFAULT 0,
    last_device_id BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Hasta dónde llegó el envío (para continuarlo si se interrumpe)',
    error          VARCHAR(255)    NULL,
    created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at    DATETIME        NULL,
    PRIMARY KEY (id),
    KEY idx_push_campaigns_created (created_at),
    CONSTRAINT fk_push_campaigns_admin FOREIGN KEY (admin_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_push_campaigns_target FOREIGN KEY (target_user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
