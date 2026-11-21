-- TREVIX · Alpha 3.0.5: likes/viewers en lives, mensajes de chat y regalos en live.

ALTER TABLE live_sessions
    ADD COLUMN likes_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER title,
    ADD COLUMN viewers_peak INT UNSIGNED NOT NULL DEFAULT 0 AFTER likes_count;

CREATE TABLE IF NOT EXISTS live_session_messages (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    session_id      BIGINT UNSIGNED NOT NULL,
    user_id         INT UNSIGNED    NOT NULL,
    body            VARCHAR(280)    NOT NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_live_msg_session (session_id, id),
    KEY idx_live_msg_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE gift_sends
    MODIFY COLUMN context ENUM('profile', 'message', 'post', 'story', 'live') NOT NULL DEFAULT 'profile',
    ADD COLUMN live_session_id BIGINT UNSIGNED NULL AFTER story_id;
