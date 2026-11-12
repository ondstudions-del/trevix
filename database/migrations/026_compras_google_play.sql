-- TREVIX · Recargas del monedero con Google Play Billing (app de Android): cada compra comprobada con la Google Play
-- Developer API se guarda una sola vez (token único) y acredita el precio menos la comisión de Google. Solo para
-- bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

CREATE TABLE IF NOT EXISTS play_purchases (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NULL,
    product_id      VARCHAR(64)     NOT NULL,
    token_hash      CHAR(64)        NOT NULL COMMENT 'SHA-256 del token de compra',
    purchase_token  VARCHAR(1024)   NOT NULL,
    order_id        VARCHAR(100)    NULL,
    price_cents     INT UNSIGNED    NOT NULL,
    credited_cents  INT UNSIGNED    NOT NULL COMMENT 'Precio menos la comisión de Google',
    is_test         TINYINT(1)      NOT NULL DEFAULT 0 COMMENT 'Compra de prueba (cuentas de prueba de Play Console)',
    consumed        TINYINT(1)      NOT NULL DEFAULT 0,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_play_purchases_token (token_hash),
    KEY idx_play_purchases_user (user_id, created_at),
    CONSTRAINT fk_play_purchases_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
