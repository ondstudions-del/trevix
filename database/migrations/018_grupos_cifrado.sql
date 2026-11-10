-- TREVIX · Grupos de mensajes, cifrado de extremo a extremo, fotos de visualización única y almacenamiento del chat.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Grupos: nombre (title), descripción, foto, portada, estilo (theme, también en los chats de dos), visibilidad
-- (public: se entra directo con el enlace y aparece en la búsqueda; private: el enlace crea una solicitud) y el
-- código del enlace de invitación. e2ee/key_epoch: el chat está cifrado y la clave vigente (ver conversation_keys).
ALTER TABLE conversations
    ADD COLUMN description VARCHAR(500) NULL AFTER title,
    ADD COLUMN avatar_path VARCHAR(255) NULL AFTER description,
    ADD COLUMN cover_path VARCHAR(255) NULL AFTER avatar_path,
    ADD COLUMN theme VARCHAR(30) NULL AFTER cover_path,
    ADD COLUMN visibility ENUM('private', 'public') NULL AFTER theme,
    ADD COLUMN invite_code CHAR(16) NULL AFTER visibility,
    ADD COLUMN e2ee TINYINT(1) NOT NULL DEFAULT 0 AFTER disappear_seconds,
    ADD COLUMN key_epoch INT UNSIGNED NOT NULL DEFAULT 0 AFTER e2ee,
    ADD UNIQUE KEY uq_conversations_invite (invite_code),
    ADD KEY idx_conversations_public (type, visibility);

-- Rol dentro del grupo (en los chats de dos todos son «member»).
ALTER TABLE conversation_participants
    ADD COLUMN role ENUM('owner', 'admin', 'member') NOT NULL DEFAULT 'member' AFTER user_id;

-- Ahora cada participante ve solo los mensajes desde que entró (joined_at); en los chats de dos, desde que existe el chat.
UPDATE conversation_participants cp
JOIN conversations c ON c.id = cp.conversation_id
SET cp.joined_at = c.created_at
WHERE c.type = 'direct' AND cp.joined_at > c.created_at;

-- e2ee_epoch: el texto (body) es el mensaje cifrado con la clave de esa época; el servidor no puede leerlo.
-- media_size: bytes del archivo (almacenamiento). media_cleared_at: quien lo envió borró el archivo para liberar
-- espacio. view_once / view_seconds: foto de visualización única (hasta cerrarla o durante 3, 5 o 10 segundos).
ALTER TABLE messages
    ADD COLUMN e2ee_epoch INT UNSIGNED NULL AFTER body,
    ADD COLUMN media_size INT UNSIGNED NULL AFTER media_duration,
    ADD COLUMN media_cleared_at DATETIME NULL AFTER media_size,
    ADD COLUMN view_once TINYINT(1) NOT NULL DEFAULT 0 AFTER media_cleared_at,
    ADD COLUMN view_seconds TINYINT UNSIGNED NULL AFTER view_once,
    ADD KEY idx_messages_sender_created (sender_id, created_at);

-- Solicitudes para entrar a un grupo privado con su enlace.
CREATE TABLE IF NOT EXISTS conversation_requests (
    conversation_id BIGINT UNSIGNED NOT NULL,
    user_id         BIGINT UNSIGNED NOT NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (conversation_id, user_id),
    KEY idx_conversation_requests_user (user_id),
    CONSTRAINT fk_conversation_requests_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_requests_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Clave pública de cada cuenta (X25519). La privada nunca llega al servidor: solo su copia cifrada con una clave
-- derivada del PIN de 6 dígitos (backup_blob) y una prueba del PIN (backup_auth, con password_hash) para devolverla.
-- key_id sube cada vez que la cuenta crea una clave nueva (los chats vuelven a repartir su clave).
CREATE TABLE IF NOT EXISTS user_keys (
    user_id     BIGINT UNSIGNED NOT NULL,
    key_id      INT UNSIGNED    NOT NULL DEFAULT 1,
    public_key  VARCHAR(64)     NOT NULL,
    backup_blob VARCHAR(512)    NULL,
    backup_salt VARCHAR(64)     NULL,
    backup_auth VARCHAR(255)    NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_user_keys_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Clave de cada época del chat, cifrada para cada participante con su clave pública (la reparte la app de quien
-- la crea). Una época nueva cada vez que cambian los participantes o la clave de alguno.
CREATE TABLE IF NOT EXISTS conversation_keys (
    conversation_id BIGINT UNSIGNED NOT NULL,
    epoch           INT UNSIGNED    NOT NULL,
    user_id         BIGINT UNSIGNED NOT NULL,
    user_key_id     INT UNSIGNED    NOT NULL,
    wrapped         VARCHAR(255)    NOT NULL,
    wrapped_by      BIGINT UNSIGNED NULL,
    wrapper_public  VARCHAR(64)     NOT NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (conversation_id, epoch, user_id),
    KEY idx_conversation_keys_user (user_id),
    CONSTRAINT fk_conversation_keys_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_keys_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_conversation_keys_wrapper FOREIGN KEY (wrapped_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Quién abrió una foto de visualización única (no se puede volver a abrir).
CREATE TABLE IF NOT EXISTS message_views (
    message_id BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    viewed_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id),
    KEY idx_message_views_user (user_id),
    CONSTRAINT fk_message_views_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_message_views_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
