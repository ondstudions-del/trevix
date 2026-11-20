-- TREVIX · Alpha 2.4: sesiones LiveKit (llamadas 1:1 y live).

CREATE TABLE IF NOT EXISTS live_sessions (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_name       VARCHAR(80)     NOT NULL,
    kind            ENUM('audio','video','live') NOT NULL,
    host_user_id    INT UNSIGNED    NOT NULL,
    peer_user_id    INT UNSIGNED    NULL DEFAULT NULL,
    status          ENUM('ringing','active','ended','declined','missed') NOT NULL DEFAULT 'ringing',
    title           VARCHAR(120)    NULL DEFAULT NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at      DATETIME        NULL DEFAULT NULL,
    ended_at        DATETIME        NULL DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_live_room (room_name),
    KEY idx_live_host (host_user_id, status, created_at),
    KEY idx_live_peer (peer_user_id, status, created_at),
    KEY idx_live_kind (kind, status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;