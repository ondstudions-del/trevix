-- =============================================================================
-- TREVIX · Esquema de base de datos
-- MySQL 8.0+ / MariaDB 10.6+ · InnoDB · utf8mb4
--
-- Instalación:
--   mysql -u root -p < database/trevix_db.sql
--
-- Convenciones:
--   * Claves primarias BIGINT UNSIGNED para escalar.
--   * Contadores desnormalizados (followers_count, likes_count…) que la aplicación
--     mantiene dentro de transacciones para evitar COUNT(*) en cada vista.
--   * Borrado lógico de usuarios y contenido mediante columnas status.
--   * No se insertan usuarios de ejemplo: el primer administrador se crea registrándose
--     y ejecutando:  UPDATE users SET role = 'admin' WHERE username = 'tu_usuario';
-- =============================================================================

CREATE DATABASE IF NOT EXISTS trevix_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE trevix_db;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- -----------------------------------------------------------------------------
-- Usuarios
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    username          VARCHAR(30)     NOT NULL,
    email             VARCHAR(190)    NOT NULL,
    password_hash     VARCHAR(255)    NOT NULL,
    display_name      VARCHAR(60)     NOT NULL,
    bio               VARCHAR(300)    NULL,
    avatar_path       VARCHAR(255)    NULL,
    cover_path        VARCHAR(255)    NULL,
    birth_date        DATE            NULL,
    country           CHAR(2)         NULL,
    website           VARCHAR(255)    NULL,
    is_private        TINYINT(1)      NOT NULL DEFAULT 0,
    is_verified       TINYINT(1)      NOT NULL DEFAULT 0,
    account_type      ENUM('personal', 'creator') NOT NULL DEFAULT 'personal',
    creator_category  ENUM('music_artist', 'influencer', 'blogger', 'other') NULL,
    show_activity     TINYINT(1)      NOT NULL DEFAULT 1,
    message_privacy   ENUM('everyone', 'following', 'nobody') NOT NULL DEFAULT 'everyone',
    notify_follows    TINYINT(1)      NOT NULL DEFAULT 1,
    notify_likes      TINYINT(1)      NOT NULL DEFAULT 1,
    notify_comments   TINYINT(1)      NOT NULL DEFAULT 1,
    notify_mentions   TINYINT(1)      NOT NULL DEFAULT 1,
    role              ENUM('user', 'moderator', 'admin') NOT NULL DEFAULT 'user',
    status            ENUM('active', 'suspended', 'deactivated', 'deleted') NOT NULL DEFAULT 'active',
    suspended_until   DATETIME        NULL,
    suspension_reason VARCHAR(255)    NULL,
    email_verified_at DATETIME        NULL,
    last_seen_at      DATETIME        NULL,
    followers_count   INT UNSIGNED    NOT NULL DEFAULT 0,
    following_count   INT UNSIGNED    NOT NULL DEFAULT 0,
    posts_count       INT UNSIGNED    NOT NULL DEFAULT 0,
    created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_username (username),
    UNIQUE KEY uq_users_email (email),
    KEY idx_users_status (status),
    KEY idx_users_role (role),
    KEY idx_users_last_seen (last_seen_at),
    KEY idx_users_created (created_at),
    FULLTEXT KEY ft_users_search (username, display_name, bio),
    CONSTRAINT chk_users_username CHECK ((username COLLATE utf8mb4_bin) REGEXP '^[a-z0-9_.]{3,30}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tokens de un solo uso (verificación de correo y recuperación de contraseña).
-- Solo se guarda el hash SHA-256 del token, nunca el token en claro.
CREATE TABLE IF NOT EXISTS user_tokens (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id     BIGINT UNSIGNED NOT NULL,
    type        ENUM('email_verification', 'password_reset', 'email_change') NOT NULL,
    token_hash  CHAR(64)        NOT NULL,
    payload     VARCHAR(190)    NULL,
    expires_at  DATETIME        NOT NULL,
    used_at     DATETIME        NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_user_tokens_hash (token_hash),
    KEY idx_user_tokens_user_type (user_id, type),
    KEY idx_user_tokens_expires (expires_at),
    CONSTRAINT fk_user_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sesiones de la app móvil (API v1). Solo se guarda el hash SHA-256 del token Bearer.
-- password_fp es la huella del hash de la contraseña al iniciar sesión: si la contraseña cambia,
-- el token deja de valer, igual que las sesiones web.
CREATE TABLE IF NOT EXISTS api_tokens (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    name         VARCHAR(80)     NOT NULL,
    token_hash   CHAR(64)        NOT NULL,
    password_fp  CHAR(64)        NOT NULL,
    last_used_at DATETIME        NULL,
    last_ip      VARBINARY(16)   NULL,
    expires_at   DATETIME        NOT NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_api_tokens_hash (token_hash),
    KEY idx_api_tokens_user (user_id),
    KEY idx_api_tokens_expires (expires_at),
    CONSTRAINT fk_api_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Registro de intentos para rate limiting (login, registro, recuperación).
CREATE TABLE IF NOT EXISTS rate_limits (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    action      VARCHAR(40)     NOT NULL,
    key_hash    CHAR(64)        NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_rate_limits_lookup (action, key_hash, created_at),
    KEY idx_rate_limits_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Bloqueos entre usuarios.
CREATE TABLE IF NOT EXISTS blocks (
    blocker_id  BIGINT UNSIGNED NOT NULL,
    blocked_id  BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (blocker_id, blocked_id),
    KEY idx_blocks_blocked (blocked_id),
    CONSTRAINT fk_blocks_blocker FOREIGN KEY (blocker_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_blocks_blocked FOREIGN KEY (blocked_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Comunidades
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS communities (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id       BIGINT UNSIGNED NOT NULL,
    slug           VARCHAR(60)     NOT NULL,
    name           VARCHAR(80)     NOT NULL,
    description    VARCHAR(500)    NULL,
    category       VARCHAR(40)     NULL,
    avatar_path    VARCHAR(255)    NULL,
    cover_path     VARCHAR(255)    NULL,
    visibility     ENUM('public', 'private') NOT NULL DEFAULT 'public',
    status         ENUM('active', 'suspended', 'deleted') NOT NULL DEFAULT 'active',
    members_count  INT UNSIGNED    NOT NULL DEFAULT 0,
    posts_count    INT UNSIGNED    NOT NULL DEFAULT 0,
    created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_communities_slug (slug),
    KEY idx_communities_owner (owner_id),
    KEY idx_communities_visibility_status (visibility, status),
    KEY idx_communities_members (members_count),
    FULLTEXT KEY ft_communities_search (name, description),
    CONSTRAINT fk_communities_owner FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_communities_slug CHECK ((slug COLLATE utf8mb4_bin) REGEXP '^[a-z0-9-]{3,60}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS community_members (
    community_id  BIGINT UNSIGNED NOT NULL,
    user_id       BIGINT UNSIGNED NOT NULL,
    role          ENUM('member', 'moderator', 'owner') NOT NULL DEFAULT 'member',
    status        ENUM('active', 'pending', 'banned') NOT NULL DEFAULT 'active',
    joined_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (community_id, user_id),
    KEY idx_community_members_user (user_id, status),
    KEY idx_community_members_status (community_id, status),
    CONSTRAINT fk_community_members_community FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE CASCADE,
    CONSTRAINT fk_community_members_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Música de artistas: pasa por revisión del equipo antes de llegar a la biblioteca.
-- Las canciones de catálogos externos (Audius, Free To Use) se guardan al elegirlas por primera vez:
-- no tienen artista en TREVIX (artist_id NULL) y su audio y portada son URL del catálogo.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS songs (
    id                BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    source            ENUM('trevix', 'audius', 'freetouse') NOT NULL DEFAULT 'trevix',
    external_id       VARCHAR(64)       NULL,
    artist_id         BIGINT UNSIGNED   NULL,
    external_artist   VARCHAR(160)      NULL,
    title             VARCHAR(100)      NOT NULL,
    featuring         VARCHAR(120)      NULL,
    genre             VARCHAR(30)       NOT NULL,
    is_explicit       TINYINT(1)        NOT NULL DEFAULT 0,
    audio_path        VARCHAR(500)      NOT NULL,
    audio_mime        VARCHAR(50)       NOT NULL,
    size_bytes        INT UNSIGNED      NOT NULL,
    duration_seconds  SMALLINT UNSIGNED NOT NULL,
    cover_path        VARCHAR(500)      NULL,
    external_url      VARCHAR(500)      NULL,
    status            ENUM('pending', 'published', 'rejected', 'cancelled', 'withdrawn', 'removed') NOT NULL DEFAULT 'pending',
    review_note       VARCHAR(255)      NULL,
    reviewed_by       BIGINT UNSIGNED   NULL,
    reviewed_at       DATETIME          NULL,
    published_at      DATETIME          NULL,
    uses_count        INT UNSIGNED      NOT NULL DEFAULT 0,
    created_at        DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_songs_external (source, external_id),
    KEY idx_songs_source (source, status, published_at),
    KEY idx_songs_artist (artist_id, status, created_at),
    KEY idx_songs_status_published (status, published_at),
    KEY idx_songs_status_uses (status, uses_count),
    CONSTRAINT fk_songs_artist FOREIGN KEY (artist_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_songs_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Eventos: portada, fecha y hora, lugar y descripción. Se publican en el inicio como una publicación (posts.event_id).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED NOT NULL,
    title            VARCHAR(120)    NOT NULL,
    description      TEXT            NULL,
    place            VARCHAR(160)    NOT NULL,
    starts_at        DATETIME        NOT NULL,
    ends_at          DATETIME        NULL,
    cover_path       VARCHAR(255)    NULL,
    going_count      INT UNSIGNED    NOT NULL DEFAULT 0,
    interested_count INT UNSIGNED    NOT NULL DEFAULT 0,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_events_starts (starts_at),
    KEY idx_events_user (user_id, starts_at),
    CONSTRAINT fk_events_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- «Asistiré» (going) o «Me interesa» (interested): una respuesta por persona y evento.
CREATE TABLE IF NOT EXISTS event_responses (
    event_id    BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    status      ENUM('going', 'interested') NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id, user_id),
    KEY idx_event_responses_user (user_id),
    CONSTRAINT fk_event_responses_event FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
    CONSTRAINT fk_event_responses_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Publicaciones
-- song_start: segundo en que empieza el fragmento de la canción adjunta.
-- background: fondo de color de un hilo (mismas claves que las historias de texto).
-- life_event: acontecimiento importante (trabajo, mudanza, graduación…).
-- location_*: lugar elegido al publicar (nombre visible; coordenadas redondeadas a ~100 m).
-- gif_*: GIF o sticker de GIPHY publicado. featured_*: publicación destacada por la administración.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS posts (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NOT NULL,
    community_id    BIGINT UNSIGNED NULL,
    shared_post_id  BIGINT UNSIGNED NULL,
    song_id         BIGINT UNSIGNED NULL,
    song_start      SMALLINT UNSIGNED NULL,
    event_id        BIGINT UNSIGNED NULL,
    format          ENUM('post', 'thread') NOT NULL DEFAULT 'post',
    background      VARCHAR(30)     NULL,
    life_event      VARCHAR(30)     NULL,
    body            TEXT            NULL,
    location_name   VARCHAR(120)    NULL,
    location_lat    DECIMAL(8,5)    NULL,
    location_lng    DECIMAL(8,5)    NULL,
    gif_id          VARCHAR(64)     NULL,
    gif_kind        ENUM('gif', 'sticker') NULL,
    gif_url         VARCHAR(500)    NULL,
    gif_width       SMALLINT UNSIGNED NULL,
    gif_height      SMALLINT UNSIGNED NULL,
    gif_title       VARCHAR(140)    NULL,
    visibility      ENUM('public', 'followers', 'private') NOT NULL DEFAULT 'public',
    status          ENUM('published', 'hidden', 'removed') NOT NULL DEFAULT 'published',
    is_edited       TINYINT(1)      NOT NULL DEFAULT 0,
    edited_at       DATETIME        NULL,
    likes_count     INT UNSIGNED    NOT NULL DEFAULT 0,
    comments_count  INT UNSIGNED    NOT NULL DEFAULT 0,
    shares_count    INT UNSIGNED    NOT NULL DEFAULT 0,
    saves_count     INT UNSIGNED    NOT NULL DEFAULT 0,
    featured_at     DATETIME        NULL,
    featured_by     BIGINT UNSIGNED NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_posts_featured (featured_at),
    KEY idx_posts_event (event_id),
    KEY idx_posts_user_created (user_id, created_at),
    KEY idx_posts_community_created (community_id, created_at),
    KEY idx_posts_status_created (status, created_at),
    KEY idx_posts_format_created (format, created_at),
    KEY idx_posts_shared (shared_post_id),
    KEY idx_posts_trending (status, likes_count, created_at),
    KEY idx_posts_song (song_id, created_at),
    FULLTEXT KEY ft_posts_body (body),
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_posts_community FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE SET NULL,
    CONSTRAINT fk_posts_shared FOREIGN KEY (shared_post_id) REFERENCES posts (id) ON DELETE SET NULL,
    CONSTRAINT fk_posts_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL,
    CONSTRAINT fk_posts_event FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
    CONSTRAINT fk_posts_featured_by FOREIGN KEY (featured_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS post_media (
    id                BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    post_id           BIGINT UNSIGNED  NOT NULL,
    type              ENUM('image', 'video') NOT NULL,
    path              VARCHAR(255)     NOT NULL,
    mime_type         VARCHAR(100)     NOT NULL,
    size_bytes        INT UNSIGNED     NOT NULL,
    width             SMALLINT UNSIGNED NULL,
    height            SMALLINT UNSIGNED NULL,
    duration_seconds  SMALLINT UNSIGNED NULL,
    alt_text          VARCHAR(300)     NULL,
    position          TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_post_media_position (post_id, position),
    CONSTRAINT fk_post_media_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS likes (
    user_id     BIGINT UNSIGNED NOT NULL,
    post_id     BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, post_id),
    KEY idx_likes_post (post_id, created_at),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS comments (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    post_id        BIGINT UNSIGNED NOT NULL,
    user_id        BIGINT UNSIGNED NOT NULL,
    parent_id      BIGINT UNSIGNED NULL,
    body           VARCHAR(1000)   NOT NULL COMMENT 'Puede quedar vacío si el comentario lleva GIF o sticker',
    gif_id         VARCHAR(64)     NULL,
    gif_kind       ENUM('gif', 'sticker') NULL,
    gif_url        VARCHAR(500)    NULL,
    gif_width      SMALLINT UNSIGNED NULL,
    gif_height     SMALLINT UNSIGNED NULL,
    gif_title      VARCHAR(140)    NULL,
    status         ENUM('published', 'hidden', 'removed') NOT NULL DEFAULT 'published',
    likes_count    INT UNSIGNED    NOT NULL DEFAULT 0,
    replies_count  INT UNSIGNED    NOT NULL DEFAULT 0,
    is_edited      TINYINT(1)      NOT NULL DEFAULT 0,
    created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_comments_post_parent (post_id, parent_id, created_at),
    KEY idx_comments_user (user_id, created_at),
    KEY idx_comments_parent (parent_id),
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_parent FOREIGN KEY (parent_id) REFERENCES comments (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS saved_posts (
    user_id     BIGINT UNSIGNED NOT NULL,
    post_id     BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, post_id),
    KEY idx_saved_posts_user_created (user_id, created_at),
    KEY idx_saved_posts_post (post_id),
    CONSTRAINT fk_saved_posts_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_saved_posts_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Hashtags y tendencias
CREATE TABLE IF NOT EXISTS hashtags (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    tag           VARCHAR(50)     NOT NULL,
    posts_count   INT UNSIGNED    NOT NULL DEFAULT 0,
    last_used_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_hashtags_tag (tag),
    KEY idx_hashtags_trending (last_used_at, posts_count)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS post_hashtags (
    post_id     BIGINT UNSIGNED NOT NULL,
    hashtag_id  BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, hashtag_id),
    KEY idx_post_hashtags_tag (hashtag_id, created_at),
    CONSTRAINT fk_post_hashtags_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_hashtags_tag FOREIGN KEY (hashtag_id) REFERENCES hashtags (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Grafo social
-- La regla "un usuario no puede seguirse a sí mismo" se valida en la aplicación:
-- MySQL no permite CHECK sobre columnas con acciones ON DELETE CASCADE.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS follows (
    follower_id   BIGINT UNSIGNED NOT NULL,
    following_id  BIGINT UNSIGNED NOT NULL,
    created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (follower_id, following_id),
    KEY idx_follows_following (following_id, created_at),
    CONSTRAINT fk_follows_follower FOREIGN KEY (follower_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_follows_following FOREIGN KEY (following_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS follow_requests (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    requester_id  BIGINT UNSIGNED NOT NULL,
    target_id     BIGINT UNSIGNED NOT NULL,
    status        ENUM('pending', 'accepted', 'rejected') NOT NULL DEFAULT 'pending',
    created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at  DATETIME        NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_follow_requests_pair (requester_id, target_id),
    KEY idx_follow_requests_target (target_id, status, created_at),
    CONSTRAINT fk_follow_requests_requester FOREIGN KEY (requester_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_follow_requests_target FOREIGN KEY (target_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Notificaciones
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id     BIGINT UNSIGNED NOT NULL,
    actor_id    BIGINT UNSIGNED NULL,
    type        ENUM('follow', 'follow_request', 'follow_accepted', 'like', 'comment', 'reply', 'mention', 'share',
                     'community', 'community_request', 'community_accepted', 'system',
                     'song_approved', 'song_rejected', 'song_removed',
                     'story_mention', 'event_going', 'featured') NOT NULL,
    post_id     BIGINT UNSIGNED NULL,
    comment_id  BIGINT UNSIGNED NULL,
    community_id BIGINT UNSIGNED NULL,
    song_id     BIGINT UNSIGNED NULL,
    read_at     DATETIME        NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_notifications_user_read (user_id, read_at, created_at),
    KEY idx_notifications_user_created (user_id, created_at),
    KEY idx_notifications_actor (actor_id),
    CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_actor FOREIGN KEY (actor_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_comment FOREIGN KEY (comment_id) REFERENCES comments (id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_community FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Mensajería privada
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    type             ENUM('direct', 'group') NOT NULL DEFAULT 'direct',
    direct_key       VARCHAR(45)     NULL COMMENT 'menorId:mayorId para garantizar una sola conversación directa por pareja',
    title            VARCHAR(80)     NULL,
    created_by       BIGINT UNSIGNED NULL,
    last_message_id  BIGINT UNSIGNED NULL,
    last_message_at  DATETIME        NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_conversations_direct (direct_key),
    KEY idx_conversations_last (last_message_at),
    KEY idx_conversations_last_message (last_message_id),
    CONSTRAINT fk_conversations_creator FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_conversations_last_message FOREIGN KEY (last_message_id) REFERENCES messages (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS conversation_participants (
    conversation_id       BIGINT UNSIGNED NOT NULL,
    user_id               BIGINT UNSIGNED NOT NULL,
    last_read_message_id  BIGINT UNSIGNED NULL,
    is_muted              TINYINT(1)      NOT NULL DEFAULT 0,
    joined_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at               DATETIME        NULL,
    PRIMARY KEY (conversation_id, user_id),
    KEY idx_participants_user (user_id),
    KEY idx_participants_last_read (last_read_message_id),
    CONSTRAINT fk_participants_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_participants_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_participants_last_read FOREIGN KEY (last_read_message_id) REFERENCES messages (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS messages (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    conversation_id  BIGINT UNSIGNED NOT NULL,
    sender_id        BIGINT UNSIGNED NULL,
    body             TEXT            NULL,
    media_path       VARCHAR(255)    NULL,
    media_mime       VARCHAR(100)    NULL COMMENT 'image/* = foto, audio/* = nota de voz',
    media_duration   SMALLINT UNSIGNED NULL COMMENT 'Segundos de la nota de voz',
    story_id         BIGINT UNSIGNED NULL COMMENT 'Historia a la que responde (sin FK: las historias caducan y se borran)',
    song_id          BIGINT UNSIGNED NULL,
    gif_id           VARCHAR(64)     NULL,
    gif_kind         ENUM('gif', 'sticker') NULL,
    gif_url          VARCHAR(500)    NULL,
    gif_width        SMALLINT UNSIGNED NULL,
    gif_height       SMALLINT UNSIGNED NULL,
    gif_title        VARCHAR(140)    NULL,
    edited_at        DATETIME        NULL,
    deleted_at       DATETIME        NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_messages_conversation (conversation_id, id),
    KEY idx_messages_sender (sender_id),
    KEY idx_messages_story (story_id),
    KEY idx_messages_song (song_id),
    CONSTRAINT fk_messages_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_messages_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Historias (24 horas)
-- overlays: capas de las historias con foto o video (texto, stickers de GIPHY, ubicación, encuesta, menciones, enlace).
-- filter: filtro de color aplicado a la foto o el video.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stories (
    id                BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    user_id           BIGINT UNSIGNED  NOT NULL,
    media_type        ENUM('image', 'video', 'text') NOT NULL,
    media_path        VARCHAR(255)     NULL,
    mime_type         VARCHAR(100)     NULL,
    body              VARCHAR(500)     NULL,
    background        VARCHAR(30)      NULL,
    overlays          JSON             NULL,
    filter            VARCHAR(20)      NULL,
    song_id           BIGINT UNSIGNED  NULL,
    song_start        SMALLINT UNSIGNED NULL,
    duration_seconds  TINYINT UNSIGNED NOT NULL DEFAULT 5,
    views_count       INT UNSIGNED     NOT NULL DEFAULT 0,
    expires_at        DATETIME         NOT NULL,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_stories_user_expires (user_id, expires_at),
    KEY idx_stories_expires (expires_at),
    KEY idx_stories_song (song_id),
    CONSTRAINT fk_stories_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_stories_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS story_views (
    story_id   BIGINT UNSIGNED NOT NULL,
    viewer_id  BIGINT UNSIGNED NOT NULL,
    viewed_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (story_id, viewer_id),
    KEY idx_story_views_viewer (viewer_id),
    CONSTRAINT fk_story_views_story FOREIGN KEY (story_id) REFERENCES stories (id) ON DELETE CASCADE,
    CONSTRAINT fk_story_views_viewer FOREIGN KEY (viewer_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Votos de la encuesta de 2 opciones de una historia (choice 0 o 1).
CREATE TABLE IF NOT EXISTS story_poll_votes (
    story_id    BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    choice      TINYINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (story_id, user_id),
    KEY idx_story_poll_votes_user (user_id),
    CONSTRAINT fk_story_poll_votes_story FOREIGN KEY (story_id) REFERENCES stories (id) ON DELETE CASCADE,
    CONSTRAINT fk_story_poll_votes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Moderación y administración
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reports (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    reporter_id      BIGINT UNSIGNED NOT NULL,
    target_type      ENUM('post', 'comment', 'user', 'community', 'message', 'story') NOT NULL,
    target_id        BIGINT UNSIGNED NOT NULL,
    reason           ENUM('spam', 'harassment', 'hate', 'violence', 'nudity', 'misinformation', 'impersonation', 'self_harm', 'other') NOT NULL,
    details          VARCHAR(1000)   NULL,
    status           ENUM('open', 'reviewing', 'resolved', 'dismissed') NOT NULL DEFAULT 'open',
    reviewed_by      BIGINT UNSIGNED NULL,
    reviewed_at      DATETIME        NULL,
    resolution_note  VARCHAR(500)    NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_reports_once (reporter_id, target_type, target_id),
    KEY idx_reports_status_created (status, created_at),
    KEY idx_reports_target (target_type, target_id),
    KEY idx_reports_target_status (target_type, target_id, status),
    CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_reports_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS admin_audit_log (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    admin_id     BIGINT UNSIGNED NULL,
    action       VARCHAR(60)     NOT NULL,
    target_type  VARCHAR(30)     NULL,
    target_id    BIGINT UNSIGNED NULL,
    details      JSON            NULL,
    ip_address   VARBINARY(16)   NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_audit_admin_created (admin_id, created_at),
    KEY idx_audit_target (target_type, target_id),
    KEY idx_audit_created (created_at),
    KEY idx_audit_action (action, created_at),
    CONSTRAINT fk_audit_admin FOREIGN KEY (admin_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_settings (
    setting_key    VARCHAR(100) NOT NULL,
    setting_value  TEXT         NULL,
    updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO app_settings (setting_key, setting_value) VALUES
    ('site_name', 'TREVIX'),
    ('registration_open', '1'),
    ('require_email_verification', '0'),
    ('maintenance_mode', '0'),
    ('site_announcement', '')
ON DUPLICATE KEY UPDATE setting_key = setting_key;

SET FOREIGN_KEY_CHECKS = 1;
