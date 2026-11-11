-- TREVIX · Fondo del chat compartido, «escribiendo…» y la bandeja con chats fijados, favoritos, vaciar y eliminar.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- El fondo del chat pasa a ser de la conversación (lo ven todos, como el estilo). Se conserva el que alguien ya
-- había elegido.
ALTER TABLE conversations ADD COLUMN wallpaper VARCHAR(30) NULL COMMENT 'Fondo del chat (lo ven todos los participantes)' AFTER theme;
UPDATE conversations c
JOIN (SELECT conversation_id, MAX(wallpaper) AS wallpaper FROM conversation_participants WHERE wallpaper IS NOT NULL GROUP BY conversation_id) w
  ON w.conversation_id = c.id
SET c.wallpaper = w.wallpaper;
ALTER TABLE conversation_participants DROP COLUMN wallpaper;

ALTER TABLE conversation_participants
    ADD COLUMN pinned_at DATETIME NULL COMMENT 'Chat fijado arriba en la bandeja (hasta app.chat.max_pinned_chats)' AFTER nickname,
    ADD COLUMN is_favorite TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'En el filtro «Favoritos» de la bandeja' AFTER pinned_at,
    ADD COLUMN cleared_until_id BIGINT UNSIGNED NULL COMMENT 'Vaciar chat: los mensajes hasta este id ya no los ve' AFTER is_favorite,
    ADD COLUMN hidden_at DATETIME NULL COMMENT 'Eliminar chat: fuera de la bandeja hasta que llegue un mensaje nuevo' AFTER cleared_until_id,
    ADD COLUMN typing_at DATETIME NULL COMMENT 'Última señal de «escribiendo…»' AFTER hidden_at,
    ADD KEY idx_participants_pinned (user_id, pinned_at);
