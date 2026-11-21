-- TREVIX · Live setup: metadatos de stream, speakers y respuestas en chat.

ALTER TABLE live_sessions
    ADD COLUMN description TEXT NULL AFTER title,
    ADD COLUMN hashtags VARCHAR(255) NULL AFTER description,
    ADD COLUMN category VARCHAR(64) NULL AFTER hashtags,
    ADD COLUMN cover_url VARCHAR(512) NULL AFTER category,
    ADD COLUMN live_mode ENUM('camera', 'voice_chat') NOT NULL DEFAULT 'camera' AFTER cover_url,
    ADD COLUMN gifts_total_cents INT UNSIGNED NOT NULL DEFAULT 0 AFTER viewers_peak,
    ADD COLUMN unique_viewers INT UNSIGNED NOT NULL DEFAULT 0 AFTER gifts_total_cents,
    ADD COLUMN join_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER unique_viewers;

ALTER TABLE users
    MODIFY COLUMN creator_category ENUM(
        'music_artist',
        'influencer',
        'blogger',
        'developer',
        'stream',
        'other'
    ) NULL;

CREATE TABLE IF NOT EXISTS live_session_speakers (
    session_id BIGINT UNSIGNED NOT NULL,
    user_id    INT UNSIGNED    NOT NULL,
    status     ENUM('invited', 'active', 'removed') NOT NULL DEFAULT 'invited',
    PRIMARY KEY (session_id, user_id),
    KEY idx_live_speaker_user (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE live_session_messages
    ADD COLUMN reply_to_id BIGINT UNSIGNED NULL AFTER body;