-- TREVIX · Monedero (recargas con comprobante y retiros revisados por el equipo), colaboradores con suscripción
-- pagada desde el monedero, publicaciones solo para suscriptores y visualizaciones únicas de publicaciones.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.
-- Importes en centavos de dólar (USD) para no perder precisión.

ALTER TABLE posts MODIFY COLUMN visibility ENUM('public', 'followers', 'private', 'subscribers') NOT NULL DEFAULT 'public';

-- Una fila por persona y publicación vista (requisito de visualizaciones de los colaboradores).
CREATE TABLE IF NOT EXISTS post_views (
    post_id    BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    viewed_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, user_id),
    KEY idx_post_views_user (user_id),
    CONSTRAINT fk_post_views_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_views_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Medios de pago para recargar (PayPal, Llave Bre-B…): los configura la administración.
CREATE TABLE IF NOT EXISTS payment_methods (
    id                INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    name              VARCHAR(60)      NOT NULL,
    instructions      VARCHAR(1000)    NOT NULL COMMENT 'Cuenta, llave o correo y los pasos para pagar',
    min_amount_cents  INT UNSIGNED     NOT NULL DEFAULT 100,
    is_active         TINYINT(1)       NOT NULL DEFAULT 1,
    position          SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_payment_methods_active (is_active, position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS wallets (
    user_id        BIGINT UNSIGNED NOT NULL,
    balance_cents  BIGINT          NOT NULL DEFAULT 0,
    updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_wallets_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS wallet_topups (
    id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id            BIGINT UNSIGNED NOT NULL,
    payment_method_id  INT UNSIGNED    NULL,
    method_name        VARCHAR(60)     NOT NULL COMMENT 'Nombre del medio al pedirla',
    amount_cents       INT UNSIGNED    NOT NULL COMMENT 'Lo que dice haber pagado',
    credited_cents     INT UNSIGNED    NULL COMMENT 'Lo acreditado al aprobar',
    reference          VARCHAR(120)    NOT NULL COMMENT 'Número de transacción o referencia del pago',
    note               VARCHAR(500)    NULL,
    proof_path         VARCHAR(255)    NOT NULL COMMENT 'Comprobante en storage/ (no se sirve por HTTP)',
    status             ENUM('pending', 'approved', 'rejected', 'cancelled') NOT NULL DEFAULT 'pending',
    decision_note      VARCHAR(255)    NULL,
    reviewed_by        BIGINT UNSIGNED NULL,
    reviewed_at        DATETIME        NULL,
    created_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_wallet_topups_status (status, created_at),
    KEY idx_wallet_topups_user (user_id, created_at),
    CONSTRAINT fk_wallet_topups_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_wallet_topups_method FOREIGN KEY (payment_method_id) REFERENCES payment_methods (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_topups_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Retiros de lo ganado como colaborador: el importe se descuenta al pedirlo y se devuelve si se rechaza.
CREATE TABLE IF NOT EXISTS wallet_withdrawals (
    id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id           BIGINT UNSIGNED NOT NULL,
    amount_cents      INT UNSIGNED    NOT NULL,
    method            VARCHAR(60)     NOT NULL COMMENT 'Por dónde quiere recibirlo',
    account           VARCHAR(255)    NOT NULL COMMENT 'Cuenta, correo o llave donde recibirlo',
    status            ENUM('pending', 'paid', 'rejected', 'cancelled') NOT NULL DEFAULT 'pending',
    payout_reference  VARCHAR(120)    NULL,
    decision_note     VARCHAR(255)    NULL,
    reviewed_by       BIGINT UNSIGNED NULL,
    reviewed_at       DATETIME        NULL,
    created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_wallet_withdrawals_status (status, created_at),
    KEY idx_wallet_withdrawals_user (user_id, created_at),
    CONSTRAINT fk_wallet_withdrawals_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_wallet_withdrawals_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Plan de suscripción del colaborador: precio en USD por un número de días que elige la persona.
CREATE TABLE IF NOT EXISTS collaborator_plans (
    user_id       BIGINT UNSIGNED   NOT NULL,
    price_cents   INT UNSIGNED      NOT NULL,
    period_days   SMALLINT UNSIGNED NOT NULL,
    description   VARCHAR(300)      NULL,
    is_active     TINYINT(1)        NOT NULL DEFAULT 1 COMMENT '0 = en pausa: no acepta suscripciones nuevas',
    activated_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_collaborator_plans_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cada compra de una suscripción. Comprar otra vez antes de que venza suma los días al final del periodo actual.
CREATE TABLE IF NOT EXISTS collaborator_subscriptions (
    id                BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    collaborator_id   BIGINT UNSIGNED   NOT NULL,
    subscriber_id     BIGINT UNSIGNED   NOT NULL,
    price_cents       INT UNSIGNED      NOT NULL,
    commission_cents  INT UNSIGNED      NOT NULL COMMENT 'Comisión de TREVIX',
    earning_cents     INT UNSIGNED      NOT NULL COMMENT 'Lo que recibe el colaborador',
    period_days       SMALLINT UNSIGNED NOT NULL,
    starts_at         DATETIME          NOT NULL,
    expires_at        DATETIME          NOT NULL,
    created_at        DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_collab_subs_access (subscriber_id, collaborator_id, expires_at),
    KEY idx_collab_subs_collaborator (collaborator_id, expires_at),
    CONSTRAINT fk_collab_subs_collaborator FOREIGN KEY (collaborator_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_collab_subs_subscriber FOREIGN KEY (subscriber_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Movimientos del monedero (positivos entran, negativos salen) con el saldo que quedó.
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id              BIGINT UNSIGNED NOT NULL,
    type                 ENUM('topup', 'subscription', 'earning', 'withdrawal', 'withdrawal_refund', 'adjustment') NOT NULL,
    amount_cents         BIGINT          NOT NULL,
    balance_after_cents  BIGINT          NOT NULL,
    counterpart_id       BIGINT UNSIGNED NULL COMMENT 'Colaborador o suscriptor de la suscripción',
    topup_id             BIGINT UNSIGNED NULL,
    withdrawal_id        BIGINT UNSIGNED NULL,
    subscription_id      BIGINT UNSIGNED NULL,
    note                 VARCHAR(255)    NULL,
    created_at           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_wallet_transactions_user (user_id, id),
    CONSTRAINT fk_wallet_transactions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_wallet_transactions_counterpart FOREIGN KEY (counterpart_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_transactions_topup FOREIGN KEY (topup_id) REFERENCES wallet_topups (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_transactions_withdrawal FOREIGN KEY (withdrawal_id) REFERENCES wallet_withdrawals (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_transactions_subscription FOREIGN KEY (subscription_id) REFERENCES collaborator_subscriptions (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE notifications MODIFY COLUMN type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
    'community', 'community_request', 'community_accepted', 'system',
    'song_approved', 'song_rejected', 'song_removed',
    'story_mention', 'event_going', 'featured',
    'warning', 'verification_approved', 'verification_rejected',
    'appeal_accepted', 'appeal_rejected',
    'subscription', 'topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected') NOT NULL;
