-- TREVIX · Compartir publicaciones y reels en los chats (Alpha 1.7).
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Publicación o reel que se envió por mensaje (sin FK: si se borra, el chat muestra «ya no está disponible»).
-- En los chats cifrados de extremo a extremo la referencia va dentro del mensaje cifrado y esta columna queda vacía.
ALTER TABLE messages ADD COLUMN shared_post_id BIGINT UNSIGNED NULL COMMENT 'Publicación o reel compartido en el chat' AFTER story_id;
ALTER TABLE messages ADD KEY idx_messages_shared_post (shared_post_id);
