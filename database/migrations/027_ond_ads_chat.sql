-- TREVIX · OND-ADS (anuncios y promociones pagadas con el monedero, revisadas por la administración y repartidas en el
-- feed por días), stickers favoritos del chat y reacciones rápidas propias. Solo para bases creadas antes de este
-- cambio; trevix_db.sql ya lo incluye.

CREATE TABLE IF NOT EXISTS ad_campaigns (
    id               BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED   NOT NULL,
    kind             ENUM('post', 'community', 'group', 'custom') NOT NULL,
    post_id          BIGINT UNSIGNED   NULL,
    community_id     BIGINT UNSIGNED   NULL,
    conversation_id  BIGINT UNSIGNED   NULL COMMENT 'Grupo público que se promociona',
    title            VARCHAR(80)       NULL COMMENT 'Anuncio libre',
    body             VARCHAR(300)      NULL,
    image_path       VARCHAR(255)      NULL COMMENT 'uploads/ads',
    link_url         VARCHAR(500)      NULL,
    cta              ENUM('learn_more', 'shop', 'visit', 'sign_up', 'contact') NULL,
    days             SMALLINT UNSIGNED NOT NULL,
    daily_cents      INT UNSIGNED      NOT NULL,
    total_cents      INT UNSIGNED      NOT NULL,
    reach_min        SMALLINT UNSIGNED NOT NULL COMMENT 'Personas por día garantizadas (si no se alcanza, se devuelve la parte)',
    reach_max        SMALLINT UNSIGNED NOT NULL COMMENT 'Tope de personas por día',
    status           ENUM('pending', 'active', 'finished', 'rejected', 'cancelled', 'removed') NOT NULL DEFAULT 'pending',
    review_note      VARCHAR(255)      NULL,
    reviewed_by      BIGINT UNSIGNED   NULL,
    reviewed_at      DATETIME          NULL,
    starts_at        DATETIME          NULL,
    ends_at          DATETIME          NULL,
    settled_at       DATETIME          NULL,
    refunded_cents   INT UNSIGNED      NOT NULL DEFAULT 0,
    impressions      INT UNSIGNED      NOT NULL DEFAULT 0 COMMENT 'Personas distintas de cada día, sumadas',
    clicks           INT UNSIGNED      NOT NULL DEFAULT 0,
    created_at       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ad_campaigns_user (user_id, id),
    KEY idx_ad_campaigns_status (status, ends_at),
    CONSTRAINT fk_ad_campaigns_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_ad_campaigns_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE SET NULL,
    CONSTRAINT fk_ad_campaigns_community FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE SET NULL,
    CONSTRAINT fk_ad_campaigns_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE SET NULL,
    CONSTRAINT fk_ad_campaigns_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Una fila por persona y día de campaña (día 0 = las primeras 24 horas desde la aprobación).
CREATE TABLE IF NOT EXISTS ad_impressions (
    campaign_id  BIGINT UNSIGNED   NOT NULL,
    day_index    SMALLINT UNSIGNED NOT NULL,
    user_id      BIGINT UNSIGNED   NOT NULL,
    clicked_at   DATETIME          NULL,
    created_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (campaign_id, day_index, user_id),
    KEY idx_ad_impressions_user (user_id, created_at),
    CONSTRAINT fk_ad_impressions_campaign FOREIGN KEY (campaign_id) REFERENCES ad_campaigns (id) ON DELETE CASCADE,
    CONSTRAINT fk_ad_impressions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Stickers y GIF de GIPHY guardados en favoritos para el chat.
CREATE TABLE IF NOT EXISTS sticker_favorites (
    user_id     BIGINT UNSIGNED   NOT NULL,
    giphy_id    VARCHAR(64)       NOT NULL,
    kind        ENUM('gif', 'sticker') NOT NULL DEFAULT 'sticker',
    url         VARCHAR(500)      NOT NULL,
    width       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    height      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    title       VARCHAR(140)      NULL,
    created_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, giphy_id),
    KEY idx_sticker_favorites_user (user_id, created_at),
    CONSTRAINT fk_sticker_favorites_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE users ADD COLUMN chat_reactions VARCHAR(200) NULL COMMENT 'Reacciones rápidas del chat (JSON); NULL = las predeterminadas' AFTER read_receipts;

ALTER TABLE wallet_transactions MODIFY COLUMN type ENUM('topup', 'subscription', 'earning', 'withdrawal', 'withdrawal_refund', 'adjustment',
    'gift_purchase', 'gift_received', 'ad_payment', 'ad_refund') NOT NULL;

ALTER TABLE notifications MODIFY COLUMN type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
    'community', 'community_request', 'community_accepted', 'system',
    'song_approved', 'song_rejected', 'song_removed',
    'story_mention', 'event_going', 'featured',
    'warning', 'verification_approved', 'verification_rejected',
    'appeal_accepted', 'appeal_rejected',
    'subscription', 'topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected',
    'wallet_adjusted', 'collaborator_enabled',
    'gift', 'new_post', 'new_note', 'new_story',
    'ad_approved', 'ad_rejected', 'ad_finished') NOT NULL;
