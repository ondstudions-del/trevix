-- OND-ADS: tipos de creatividad, superficies (feed, perfil, historias, reels, comunidad) y preferencias de usuario.

ALTER TABLE ad_campaigns
    ADD COLUMN creative_type ENUM('native', 'app', 'website', 'product', 'video') NOT NULL DEFAULT 'native' AFTER kind,
    ADD COLUMN placements VARCHAR(120) NOT NULL DEFAULT 'feed,profile,stories,reels,community' AFTER creative_type,
    ADD COLUMN video_path VARCHAR(255) NULL COMMENT 'uploads/ads' AFTER image_path,
    ADD COLUMN product_label VARCHAR(60) NULL COMMENT 'Precio o etiqueta de producto' AFTER body;

ALTER TABLE users
    ADD COLUMN ads_personalized TINYINT(1) NOT NULL DEFAULT 1 AFTER notify_mentions,
    ADD COLUMN ads_feed TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_personalized,
    ADD COLUMN ads_profile TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_feed,
    ADD COLUMN ads_stories TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_profile,
    ADD COLUMN ads_reels TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_stories,
    ADD COLUMN ads_community TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_reels;