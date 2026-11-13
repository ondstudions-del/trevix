-- TREVIX · Feed con IA (temas y predicción de gustos), contenido para adultos oculto a menores, «No me importa»,
-- me gusta y no me gusta en comentarios y encuestas como publicación.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Contenido para adultos (+18): lo marca el autor al publicar o la IA al revisar la publicación. Solo lo ven las
-- cuentas con 18 años o más según su fecha de nacimiento.
ALTER TABLE posts ADD COLUMN is_adult TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Contenido para adultos (+18): oculto a menores' AFTER visibility;
ALTER TABLE posts ADD COLUMN adult_source ENUM('author', 'ai', 'moderator') NULL COMMENT 'Quién lo marcó como +18' AFTER is_adult;
ALTER TABLE posts ADD COLUMN ai_checked_at DATETIME NULL COMMENT 'Cuándo la IA revisó la publicación (temas y +18)' AFTER adult_source;
ALTER TABLE posts ADD KEY idx_posts_ai_pending (ai_checked_at, created_at);

-- Temas de cada publicación según la IA (fútbol, cocina, memes…): se usan para ordenar «Para ti» y los reels.
CREATE TABLE IF NOT EXISTS topics (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name        VARCHAR(40)     NOT NULL,
    posts_count INT UNSIGNED    NOT NULL DEFAULT 0,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_topics_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS post_topics (
    post_id     BIGINT UNSIGNED NOT NULL,
    topic_id    BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, topic_id),
    KEY idx_post_topics_topic (topic_id, created_at),
    CONSTRAINT fk_post_topics_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_topics_topic FOREIGN KEY (topic_id) REFERENCES topics (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Interés de cada persona por tema (igual que hashtag_interests; «No me importa» resta puntos y puede quedar en negativo).
CREATE TABLE IF NOT EXISTS topic_interests (
    user_id     BIGINT UNSIGNED NOT NULL,
    topic_id    BIGINT UNSIGNED NOT NULL,
    score       FLOAT           NOT NULL DEFAULT 0,
    updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, topic_id),
    KEY idx_topic_interests_top (user_id, score),
    CONSTRAINT fk_topic_interests_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_topic_interests_topic FOREIGN KEY (topic_id) REFERENCES topics (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Predicción de la IA de lo que le gustará a cada persona: peso de -1 (lo evita) a 1 (le encantará) por tema.
-- Se rehace como mucho una vez al día por persona.
CREATE TABLE IF NOT EXISTS topic_predictions (
    user_id     BIGINT UNSIGNED NOT NULL,
    topic_id    BIGINT UNSIGNED NOT NULL,
    weight      FLOAT           NOT NULL DEFAULT 0,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, topic_id),
    CONSTRAINT fk_topic_predictions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_topic_predictions_topic FOREIGN KEY (topic_id) REFERENCES topics (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS taste_profiles (
    user_id       BIGINT UNSIGNED NOT NULL,
    predicted_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status        ENUM('ok', 'empty', 'failed') NOT NULL DEFAULT 'ok',
    PRIMARY KEY (user_id),
    CONSTRAINT fk_taste_profiles_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- «No me importa»: la publicación sale del feed y de los reels de esa persona y sus temas y hashtags pierden puntos.
CREATE TABLE IF NOT EXISTS post_not_interested (
    user_id     BIGINT UNSIGNED NOT NULL,
    post_id     BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, post_id),
    KEY idx_post_not_interested_post (post_id),
    CONSTRAINT fk_post_not_interested_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_not_interested_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Me gusta (1) y no me gusta (-1) en comentarios: uno por persona y comentario.
ALTER TABLE comments ADD COLUMN dislikes_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER likes_count;

CREATE TABLE IF NOT EXISTS comment_reactions (
    user_id     BIGINT UNSIGNED NOT NULL,
    comment_id  BIGINT UNSIGNED NOT NULL,
    value       TINYINT         NOT NULL COMMENT '1 me gusta, -1 no me gusta',
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, comment_id),
    KEY idx_comment_reactions_comment (comment_id),
    CONSTRAINT fk_comment_reactions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_comment_reactions_comment FOREIGN KEY (comment_id) REFERENCES comments (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Encuestas como publicación: la pregunta es el texto del post; de 2 a 4 respuestas y un voto por persona.
CREATE TABLE IF NOT EXISTS post_polls (
    post_id      BIGINT UNSIGNED NOT NULL,
    ends_at      DATETIME        NOT NULL,
    votes_count  INT UNSIGNED    NOT NULL DEFAULT 0,
    PRIMARY KEY (post_id),
    CONSTRAINT fk_post_polls_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS post_poll_options (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    post_id      BIGINT UNSIGNED NOT NULL,
    position     TINYINT UNSIGNED NOT NULL,
    label        VARCHAR(80)     NOT NULL,
    votes_count  INT UNSIGNED    NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_post_poll_options_position (post_id, position),
    CONSTRAINT fk_post_poll_options_poll FOREIGN KEY (post_id) REFERENCES post_polls (post_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS post_poll_votes (
    post_id     BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    option_id   BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, user_id),
    KEY idx_post_poll_votes_user (user_id),
    KEY idx_post_poll_votes_option (option_id),
    CONSTRAINT fk_post_poll_votes_poll FOREIGN KEY (post_id) REFERENCES post_polls (post_id) ON DELETE CASCADE,
    CONSTRAINT fk_post_poll_votes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_poll_votes_option FOREIGN KEY (option_id) REFERENCES post_poll_options (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
