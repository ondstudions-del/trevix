-- TREVIX · Avisos al instante de la app de Android (GET /api/v1/me/push): las reacciones a mensajes se buscan por fecha.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

ALTER TABLE message_reactions ADD KEY idx_message_reactions_created (created_at);
