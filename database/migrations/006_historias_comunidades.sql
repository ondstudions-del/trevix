-- TREVIX · Fase 6 (historias y comunidades)
-- Solo para bases creadas antes de la Fase 6; trevix_db.sql ya incluye estos cambios.

ALTER TABLE notifications
    MODIFY COLUMN type ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
        'community', 'community_request', 'community_accepted', 'system') NOT NULL;

-- Respuestas a historias: el mensaje recuerda a qué historia respondía (sin clave foránea, porque las
-- historias caducan y se borran; una referencia a una historia que ya no existe simplemente no se muestra).
ALTER TABLE messages
    ADD COLUMN story_id BIGINT UNSIGNED NULL AFTER media_mime,
    ADD KEY idx_messages_story (story_id);
