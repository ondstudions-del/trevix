-- TREVIX · Regalos (catálogo del panel, compra con el monedero, inventario y envíos con comisión) y avisos de perfil
-- (la campana del perfil: publicaciones, notas e historias de una cuenta). Solo para bases creadas antes de este
-- cambio; trevix_db.sql ya lo incluye.

CREATE TABLE IF NOT EXISTS gift_categories (
    id          INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    name        VARCHAR(60)       NOT NULL,
    position    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    is_active   TINYINT(1)        NOT NULL DEFAULT 1,
    created_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gift_categories_position (is_active, position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gifts (
    id           INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    category_id  INT UNSIGNED      NULL,
    name         VARCHAR(60)       NOT NULL,
    kind         ENUM('gif', 'sticker') NOT NULL DEFAULT 'sticker',
    source       ENUM('upload', 'giphy') NOT NULL,
    media_path   VARCHAR(255)      NULL COMMENT 'Archivo subido (uploads/gifts)',
    giphy_id     VARCHAR(64)       NULL,
    media_url    VARCHAR(500)      NULL COMMENT 'URL de GIPHY',
    width        SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    height       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    price_cents  INT UNSIGNED      NOT NULL,
    position     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    is_active    TINYINT(1)        NOT NULL DEFAULT 1,
    created_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gifts_catalog (is_active, category_id, position),
    CONSTRAINT fk_gifts_category FOREIGN KEY (category_id) REFERENCES gift_categories (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Regalos comprados para enviar después: una fila por unidad, con lo que se pagó por ella.
CREATE TABLE IF NOT EXISTS gift_inventory (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    gift_id      INT UNSIGNED    NOT NULL,
    price_cents  INT UNSIGNED    NOT NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gift_inventory_user (user_id, gift_id, id),
    CONSTRAINT fk_gift_inventory_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_gift_inventory_gift FOREIGN KEY (gift_id) REFERENCES gifts (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cada regalo enviado, con una copia del nombre y la imagen (el panel puede editarlo o retirarlo después).
CREATE TABLE IF NOT EXISTS gift_sends (
    id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    sender_id         BIGINT UNSIGNED NULL,
    recipient_id      BIGINT UNSIGNED NOT NULL,
    gift_id           INT UNSIGNED    NULL,
    gift_name         VARCHAR(60)     NOT NULL,
    gift_kind         ENUM('gif', 'sticker') NOT NULL,
    media             VARCHAR(500)    NOT NULL COMMENT 'Ruta subida o URL de GIPHY',
    width             SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    height            SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    price_cents       INT UNSIGNED    NOT NULL,
    commission_cents  INT UNSIGNED    NOT NULL COMMENT 'Comisión de TREVIX',
    earning_cents     INT UNSIGNED    NOT NULL COMMENT 'Lo que recibe quien lo recibe',
    context           ENUM('profile', 'message', 'post', 'story') NOT NULL DEFAULT 'profile',
    post_id           BIGINT UNSIGNED NULL,
    story_id          BIGINT UNSIGNED NULL COMMENT 'Sin FK: las historias caducan y se borran',
    message_id        BIGINT UNSIGNED NULL,
    from_inventory    TINYINT(1)      NOT NULL DEFAULT 0,
    created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gift_sends_recipient (recipient_id, id),
    KEY idx_gift_sends_sender (sender_id, id),
    CONSTRAINT fk_gift_sends_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_gift_sends_recipient FOREIGN KEY (recipient_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_gift_sends_gift FOREIGN KEY (gift_id) REFERENCES gifts (id) ON DELETE SET NULL,
    CONSTRAINT fk_gift_sends_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- La campana del perfil: user_id recibe un aviso cuando target_id publica, comparte una nota o sube una historia.
CREATE TABLE IF NOT EXISTS profile_alerts (
    user_id     BIGINT UNSIGNED NOT NULL,
    target_id   BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, target_id),
    KEY idx_profile_alerts_target (target_id),
    CONSTRAINT fk_profile_alerts_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_profile_alerts_target FOREIGN KEY (target_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE wallet_transactions MODIFY COLUMN type ENUM('topup', 'subscription', 'earning', 'withdrawal', 'withdrawal_refund', 'adjustment',
    'gift_purchase', 'gift_received') NOT NULL;

ALTER TABLE messages MODIFY COLUMN context ENUM('story_reaction', 'note_reply', 'gift') NULL COMMENT 'Reacción a una historia, respuesta a una nota o regalo';
ALTER TABLE messages ADD COLUMN gift_send_id BIGINT UNSIGNED NULL COMMENT 'Regalo enviado en el chat' AFTER gif_title;

ALTER TABLE notifications MODIFY COLUMN type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
    'community', 'community_request', 'community_accepted', 'system',
    'song_approved', 'song_rejected', 'song_removed',
    'story_mention', 'event_going', 'featured',
    'warning', 'verification_approved', 'verification_rejected',
    'appeal_accepted', 'appeal_rejected',
    'subscription', 'topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected',
    'wallet_adjusted', 'collaborator_enabled',
    'gift', 'new_post', 'new_note', 'new_story') NOT NULL;
