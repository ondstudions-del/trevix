-- TREVIX · Restricciones parciales de cuenta + ajustes/reglas de comunidades

ALTER TABLE users
    ADD COLUMN restricted_until DATETIME NULL DEFAULT NULL AFTER suspension_reason,
    ADD COLUMN restriction_reason VARCHAR(500) NULL DEFAULT NULL AFTER restricted_until,
    ADD COLUMN restriction_parts JSON NULL DEFAULT NULL AFTER restriction_reason;

ALTER TABLE communities
    ADD COLUMN color VARCHAR(20) NULL DEFAULT NULL AFTER category,
    ADD COLUMN location VARCHAR(120) NULL DEFAULT NULL AFTER color,
    ADD COLUMN hidden TINYINT(1) NOT NULL DEFAULT 0 AFTER visibility,
    ADD COLUMN welcome_message TEXT NULL DEFAULT NULL AFTER description,
    ADD COLUMN settings JSON NULL DEFAULT NULL AFTER welcome_message;

CREATE TABLE IF NOT EXISTS community_rules (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    community_id BIGINT UNSIGNED NOT NULL,
    title VARCHAR(50) NOT NULL,
    body VARCHAR(500) NOT NULL,
    position TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_community_rules_community (community_id, position),
    CONSTRAINT fk_community_rules_community FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Reutiliza el tipo ENUM «community» ya existente para «X publicó en comunidad».
