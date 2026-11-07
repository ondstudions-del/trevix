-- TREVIX · Fase 5 (notificaciones y mensajería privada)
-- Solo para bases creadas antes de la Fase 5; trevix_db.sql ya incluye estas columnas.

ALTER TABLE users
    ADD COLUMN show_activity   TINYINT(1) NOT NULL DEFAULT 1 AFTER is_verified,
    ADD COLUMN message_privacy ENUM('everyone', 'following', 'nobody') NOT NULL DEFAULT 'everyone' AFTER show_activity,
    ADD COLUMN notify_follows  TINYINT(1) NOT NULL DEFAULT 1 AFTER message_privacy,
    ADD COLUMN notify_likes    TINYINT(1) NOT NULL DEFAULT 1 AFTER notify_follows,
    ADD COLUMN notify_comments TINYINT(1) NOT NULL DEFAULT 1 AFTER notify_likes,
    ADD COLUMN notify_mentions TINYINT(1) NOT NULL DEFAULT 1 AFTER notify_comments;
