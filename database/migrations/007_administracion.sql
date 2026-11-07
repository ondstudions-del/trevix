-- TREVIX · Fase 7 (administración, reportes y auditoría)
-- Solo para bases creadas antes de la Fase 7; trevix_db.sql ya incluye estos cambios.

-- Hasta ahora no se exigía el correo verificado para participar: se conserva ese comportamiento
-- y el administrador puede activarlo desde Configuración del panel.
UPDATE app_settings SET setting_value = '0' WHERE setting_key = 'require_email_verification';

INSERT INTO app_settings (setting_key, setting_value) VALUES
    ('site_announcement', '')
ON DUPLICATE KEY UPDATE setting_key = setting_key;

-- Las historias también se pueden reportar.
ALTER TABLE reports MODIFY target_type ENUM('post', 'comment', 'user', 'community', 'message', 'story') NOT NULL;

-- Listados del panel: reportes por estado y objetivo, y auditoría por fecha y acción.
ALTER TABLE reports ADD KEY idx_reports_target_status (target_type, target_id, status);
ALTER TABLE admin_audit_log ADD KEY idx_audit_created (created_at), ADD KEY idx_audit_action (action, created_at);
