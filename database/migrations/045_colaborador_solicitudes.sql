-- TREVIX · Solicitudes de colaborador + impulso trimestral

CREATE TABLE IF NOT EXISTS collaborator_applications (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    status ENUM('pending', 'approved', 'rejected') NOT NULL DEFAULT 'pending',
    fee_cents INT UNSIGNED NOT NULL DEFAULT 1000,
    fee_paid TINYINT(1) NOT NULL DEFAULT 0,
    wallet_tx_id BIGINT UNSIGNED NULL DEFAULT NULL,
    note VARCHAR(500) NULL DEFAULT NULL,
    review_note VARCHAR(500) NULL DEFAULT NULL,
    reviewed_by BIGINT UNSIGNED NULL DEFAULT NULL,
    reviewed_at DATETIME NULL DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_collab_app_user (user_id, status),
    KEY idx_collab_app_status (status, created_at),
    CONSTRAINT fk_collab_app_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_collab_app_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE users
    ADD COLUMN collaborator_boost_at DATETIME NULL DEFAULT NULL AFTER following_count;
