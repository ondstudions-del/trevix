-- TREVIX · Notas de 6 horas (con su público), lista de mejores amigos y reacciones a las historias.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Una nota activa por persona (publicar otra reemplaza la anterior). audience: seguidores, amigos (se siguen
-- mutuamente) o mejores amigos (la lista close_friends de quien publica).
CREATE TABLE IF NOT EXISTS user_notes (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id     BIGINT UNSIGNED NOT NULL,
    body        VARCHAR(60)     NOT NULL,
    audience    ENUM('followers', 'friends', 'close_friends') NOT NULL DEFAULT 'followers',
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at  DATETIME        NOT NULL,
    PRIMARY KEY (id),
    KEY idx_user_notes_user (user_id, expires_at),
    KEY idx_user_notes_expires (expires_at),
    CONSTRAINT fk_user_notes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Mejores amigos: lista privada de quien la arma (la otra persona no recibe aviso).
CREATE TABLE IF NOT EXISTS close_friends (
    user_id     BIGINT UNSIGNED NOT NULL,
    friend_id   BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, friend_id),
    KEY idx_close_friends_friend (friend_id),
    CONSTRAINT fk_close_friends_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_close_friends_friend FOREIGN KEY (friend_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Una reacción por persona e historia (además llega como mensaje privado al autor).
CREATE TABLE IF NOT EXISTS story_reactions (
    story_id    BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    emoji       VARCHAR(32)     NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (story_id, user_id),
    KEY idx_story_reactions_user (user_id),
    CONSTRAINT fk_story_reactions_story FOREIGN KEY (story_id) REFERENCES stories (id) ON DELETE CASCADE,
    CONSTRAINT fk_story_reactions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- context: el mensaje es una reacción a una historia (story_id) o una respuesta a una nota (note_text guarda
-- el texto de la nota, que caduca a las 6 horas).
ALTER TABLE messages ADD COLUMN context ENUM('story_reaction', 'note_reply') NULL AFTER kind;
ALTER TABLE messages ADD COLUMN note_text VARCHAR(60) NULL AFTER story_id;
