-- TREVIX · Colaboradores habilitados por la administración (sin requisitos) y ajustes de saldo (reembolsos).
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

CREATE TABLE IF NOT EXISTS collaborator_grants (
    user_id     BIGINT UNSIGNED NOT NULL,
    granted_by  BIGINT UNSIGNED NULL,
    note        VARCHAR(255)    NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_collaborator_grants_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_collaborator_grants_admin FOREIGN KEY (granted_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE notifications MODIFY COLUMN type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
    'community', 'community_request', 'community_accepted', 'system',
    'song_approved', 'song_rejected', 'song_removed',
    'story_mention', 'event_going', 'featured',
    'warning', 'verification_approved', 'verification_rejected',
    'appeal_accepted', 'appeal_rejected',
    'subscription', 'topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected',
    'wallet_adjusted', 'collaborator_enabled') NOT NULL;
