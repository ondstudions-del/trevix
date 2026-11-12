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
    phone             VARCHAR(20)     NULL COMMENT 'Privado: solo lo ven la persona y la administración',
    password_hash     VARCHAR(255)    NOT NULL,
    display_name      VARCHAR(60)     NOT NULL,
    bio               VARCHAR(300)    NULL,
    avatar_path       VARCHAR(255)    NULL,
    cover_path        VARCHAR(255)    NULL,
    birth_date        DATE            NULL,
    country           CHAR(2)         NULL,
    locale            CHAR(2)         NULL COMMENT 'Idioma de la interfaz (es, en); NULL = el del navegador',
    website           VARCHAR(255)    NULL,
    is_private        TINYINT(1)      NOT NULL DEFAULT 0,
    is_verified       TINYINT(1)      NOT NULL DEFAULT 0,
    account_type      ENUM('personal', 'creator') NOT NULL DEFAULT 'personal',
    creator_category  ENUM('music_artist', 'influencer', 'blogger', 'other') NULL,
    show_activity     TINYINT(1)      NOT NULL DEFAULT 1,
    read_receipts     TINYINT(1)      NOT NULL DEFAULT 1 COMMENT 'Confirmación de lectura (recíproca)',
    chat_reactions    VARCHAR(200)    NULL COMMENT 'Reacciones rápidas del chat (JSON); NULL = las predeterminadas',
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
-- Datos personales del perfil (solo la app los edita). city_key / hometown_key: la ciudad sin mayúsculas ni
-- acentos, para sugerir personas de la misma ciudad. details_audience decide quién ve ciudades, cumpleaños,
-- situación sentimental, género y contactos (los enlaces e intereses son públicos).
-- links: [{"title","url"}] · contacts: [{"type","value"}] · song_*: canción del perfil (fragmento de 30 s).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_profiles (
    user_id             BIGINT UNSIGNED NOT NULL,
    city                VARCHAR(80)     NULL,
    city_key            VARCHAR(80)     NULL,
    hometown            VARCHAR(80)     NULL,
    hometown_key        VARCHAR(80)     NULL,
    relationship_status ENUM('single', 'in_relationship', 'engaged', 'married', 'civil_union', 'open', 'complicated',
                             'separated', 'divorced', 'widowed') NULL,
    gender              ENUM('female', 'male', 'nonbinary', 'other') NULL,
    links               JSON            NULL,
    contacts            JSON            NULL,
    details_audience    ENUM('everyone', 'followers', 'friends', 'nobody') NOT NULL DEFAULT 'everyone',
    show_birth_year     TINYINT(1)      NOT NULL DEFAULT 0,
    song_id             BIGINT UNSIGNED NULL,
    song_start          INT UNSIGNED    NULL,
    updated_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    KEY idx_user_profiles_city (city_key),
    KEY idx_user_profiles_hometown (hometown_key),
    CONSTRAINT fk_user_profiles_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_profiles_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Intereses del perfil (hasta 15). interest_key normalizado para encontrar intereses en común.
CREATE TABLE IF NOT EXISTS user_interests (
    user_id      BIGINT UNSIGNED NOT NULL,
    interest_key VARCHAR(40)     NOT NULL,
    label        VARCHAR(40)     NOT NULL,
    position     TINYINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, interest_key),
    KEY idx_user_interests_key (interest_key),
    CONSTRAINT fk_user_interests_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sugerencias de personas que el usuario quitó con «No me interesa» (no vuelven a aparecer en 90 días).
CREATE TABLE IF NOT EXISTS suggestion_dismissals (
    user_id     BIGINT UNSIGNED NOT NULL,
    target_id   BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, target_id),
    KEY idx_suggestion_dismissals_target (target_id),
    CONSTRAINT fk_suggestion_dismissals_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_suggestion_dismissals_target FOREIGN KEY (target_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Advertencias que el equipo da a una cuenta. Las que tienen menos de 30 días y no se retiraron impiden pedir
-- el verificado. target_*: lo que motivó la advertencia (publicación, comentario, mensaje, historia o la cuenta).
CREATE TABLE IF NOT EXISTS user_warnings (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    issued_by    BIGINT UNSIGNED NULL,
    reason       VARCHAR(255)    NOT NULL,
    target_type  VARCHAR(20)     NULL,
    target_id    BIGINT UNSIGNED NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at   DATETIME        NULL,
    revoked_by   BIGINT UNSIGNED NULL,
    PRIMARY KEY (id),
    KEY idx_user_warnings_user (user_id, created_at),
    CONSTRAINT fk_user_warnings_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_warnings_issuer FOREIGN KEY (issued_by) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_user_warnings_revoker FOREIGN KEY (revoked_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Solicitudes de verificado, con las cifras con las que se pidió (seguidores, promedio de Me gusta y
-- publicaciones contadas) para que el equipo vea por qué cumplía.
CREATE TABLE IF NOT EXISTS verification_requests (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED NOT NULL,
    category         ENUM('creator', 'artist', 'public_figure', 'brand', 'journalist', 'athlete', 'other') NOT NULL,
    full_name        VARCHAR(80)     NOT NULL,
    note             VARCHAR(500)    NULL,
    followers_count  INT UNSIGNED    NOT NULL DEFAULT 0,
    avg_likes        INT UNSIGNED    NOT NULL DEFAULT 0,
    posts_counted    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    status           ENUM('pending', 'approved', 'rejected', 'cancelled') NOT NULL DEFAULT 'pending',
    reviewed_by      BIGINT UNSIGNED NULL,
    reviewed_at      DATETIME        NULL,
    decision_note    VARCHAR(255)    NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_verification_status (status, created_at),
    KEY idx_verification_user (user_id, created_at),
    CONSTRAINT fk_verification_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_verification_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
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
    visibility      ENUM('public', 'followers', 'private', 'subscribers') NOT NULL DEFAULT 'public',
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
    poster_path       VARCHAR(255)     NULL,
    mime_type         VARCHAR(100)     NOT NULL,
    size_bytes        INT UNSIGNED     NOT NULL,
    width             SMALLINT UNSIGNED NULL,
    height            SMALLINT UNSIGNED NULL,
    duration_seconds  SMALLINT UNSIGNED NULL,
    alt_text          VARCHAR(300)     NULL,
    filter            VARCHAR(20)      NULL COMMENT 'Filtro de color (StoryOverlays::FILTERS) que se aplica al mostrarla',
    song_sync         TINYINT(1)       NOT NULL DEFAULT 0 COMMENT 'Video grabado sobre la canción de la publicación: sin sonido propio, la canción suena desde song_start al compás del video',
    position          TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_post_media_position (post_id, position),
    KEY idx_post_media_type (type, post_id),
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
                     'story_mention', 'event_going', 'featured',
                     'warning', 'verification_approved', 'verification_rejected',
                     'appeal_accepted', 'appeal_rejected',
                     'subscription', 'topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected',
                     'wallet_adjusted', 'collaborator_enabled',
                     'gift', 'new_post', 'new_note', 'new_story',
                     'ad_approved', 'ad_rejected', 'ad_finished') NOT NULL,
    post_id     BIGINT UNSIGNED NULL,
    comment_id  BIGINT UNSIGNED NULL,
    community_id BIGINT UNSIGNED NULL,
    song_id     BIGINT UNSIGNED NULL,
    ref_id      BIGINT UNSIGNED NULL COMMENT 'Advertencia o solicitud de verificado a la que se refiere el aviso',
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
    title            VARCHAR(80)     NULL COMMENT 'Nombre del grupo',
    description      VARCHAR(500)    NULL,
    avatar_path      VARCHAR(255)    NULL,
    cover_path       VARCHAR(255)    NULL,
    theme            VARCHAR(30)     NULL COMMENT 'Estilo del chat (lo ven todos los participantes)',
    wallpaper        VARCHAR(30)     NULL COMMENT 'Fondo del chat (lo ven todos los participantes)',
    visibility       ENUM('private', 'public') NULL COMMENT 'Grupos: public = se entra directo con el enlace',
    invite_code      CHAR(16)        NULL COMMENT 'Enlace de invitación del grupo',
    created_by       BIGINT UNSIGNED NULL,
    last_message_id  BIGINT UNSIGNED NULL,
    last_message_at  DATETIME        NULL,
    disappear_seconds INT UNSIGNED   NULL COMMENT 'Mensajes temporales (NULL = desactivados)',
    e2ee             TINYINT(1)      NOT NULL DEFAULT 0 COMMENT 'Cifrado de extremo a extremo activo',
    key_epoch        INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT 'Época vigente de la clave del chat',
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_conversations_direct (direct_key),
    UNIQUE KEY uq_conversations_invite (invite_code),
    KEY idx_conversations_public (type, visibility),
    KEY idx_conversations_last (last_message_at),
    KEY idx_conversations_last_message (last_message_id),
    CONSTRAINT fk_conversations_creator FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_conversations_last_message FOREIGN KEY (last_message_id) REFERENCES messages (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS conversation_participants (
    conversation_id       BIGINT UNSIGNED NOT NULL,
    user_id               BIGINT UNSIGNED NOT NULL,
    role                  ENUM('owner', 'admin', 'member') NOT NULL DEFAULT 'member' COMMENT 'Rol en el grupo',
    last_read_message_id  BIGINT UNSIGNED NULL,
    last_delivered_message_id BIGINT UNSIGNED NULL COMMENT 'Último mensaje entregado (Info del mensaje)',
    is_muted              TINYINT(1)      NOT NULL DEFAULT 0,
    nickname              VARCHAR(40)     NULL COMMENT 'Apodo de la otra persona (solo lo ve este participante)',
    pinned_at             DATETIME        NULL COMMENT 'Chat fijado arriba en la bandeja (hasta app.chat.max_pinned_chats)',
    is_favorite           TINYINT(1)      NOT NULL DEFAULT 0 COMMENT 'En el filtro «Favoritos» de la bandeja',
    cleared_until_id      BIGINT UNSIGNED NULL COMMENT 'Vaciar chat: los mensajes hasta este id ya no los ve',
    hidden_at             DATETIME        NULL COMMENT 'Eliminar chat: fuera de la bandeja hasta que llegue un mensaje nuevo',
    typing_at             DATETIME        NULL COMMENT 'Última señal de «escribiendo…»',
    joined_at             DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at               DATETIME        NULL,
    PRIMARY KEY (conversation_id, user_id),
    KEY idx_participants_user (user_id),
    KEY idx_participants_pinned (user_id, pinned_at),
    KEY idx_participants_last_read (last_read_message_id),
    CONSTRAINT fk_participants_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_participants_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_participants_last_read FOREIGN KEY (last_read_message_id) REFERENCES messages (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS messages (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    conversation_id  BIGINT UNSIGNED NOT NULL,
    sender_id        BIGINT UNSIGNED NULL,
    kind             ENUM('message', 'system') NOT NULL DEFAULT 'message' COMMENT 'system = aviso dentro del chat (body = código)',
    context          ENUM('story_reaction', 'note_reply', 'gift') NULL COMMENT 'Reacción a una historia, respuesta a una nota o regalo',
    reply_to_id      BIGINT UNSIGNED NULL,
    forwarded        TINYINT(1)      NOT NULL DEFAULT 0,
    sent_by_ix       TINYINT(1)      NOT NULL DEFAULT 0 COMMENT 'Lo escribió IX desde la cuenta de soporte',
    body             TEXT            NULL,
    e2ee_epoch       INT UNSIGNED    NULL COMMENT 'Mensaje cifrado de extremo a extremo con la clave de esa época (body = cifrado)',
    media_path       VARCHAR(255)    NULL,
    media_mime       VARCHAR(100)    NULL COMMENT 'image/* = foto, video/* = video, audio/* = nota de voz',
    media_duration   SMALLINT UNSIGNED NULL COMMENT 'Segundos de la nota de voz o del video',
    media_size       INT UNSIGNED    NULL COMMENT 'Bytes del archivo (almacenamiento del chat)',
    media_width      SMALLINT UNSIGNED NULL,
    media_height     SMALLINT UNSIGNED NULL,
    media_poster     VARCHAR(255)    NULL COMMENT 'Miniatura del video',
    media_cleared_at DATETIME        NULL COMMENT 'Quien lo envió borró el archivo para liberar espacio',
    view_once        TINYINT(1)      NOT NULL DEFAULT 0 COMMENT 'Foto o video de visualización única',
    view_seconds     TINYINT UNSIGNED NULL COMMENT 'Segundos visibles (3, 5 o 10); NULL = hasta cerrarla',
    story_id         BIGINT UNSIGNED NULL COMMENT 'Historia a la que responde (sin FK: las historias caducan y se borran)',
    note_text        VARCHAR(60)     NULL COMMENT 'Texto de la nota a la que responde (las notas caducan a las 6 horas)',
    song_id          BIGINT UNSIGNED NULL,
    gif_id           VARCHAR(64)     NULL,
    gif_kind         ENUM('gif', 'sticker') NULL,
    gif_url          VARCHAR(500)    NULL,
    gif_width        SMALLINT UNSIGNED NULL,
    gif_height       SMALLINT UNSIGNED NULL,
    gif_title        VARCHAR(140)    NULL,
    gift_send_id     BIGINT UNSIGNED NULL COMMENT 'Regalo enviado en el chat',
    location_lat     DECIMAL(9,6)    NULL,
    location_lng     DECIMAL(9,6)    NULL,
    location_name    VARCHAR(120)    NULL,
    pinned_at        DATETIME        NULL,
    pinned_by        BIGINT UNSIGNED NULL,
    expires_at       DATETIME        NULL COMMENT 'Mensajes temporales: al caducar se vacían y dejan de mostrarse',
    edited_at        DATETIME        NULL,
    deleted_at       DATETIME        NULL,
    updated_at       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP COMMENT 'Reacciones, fijados o borrados (sondeo de la app)',
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_messages_conversation (conversation_id, id),
    KEY idx_messages_sender (sender_id),
    KEY idx_messages_sender_created (sender_id, created_at),
    KEY idx_messages_story (story_id),
    KEY idx_messages_song (song_id),
    KEY idx_messages_expires (expires_at),
    KEY idx_messages_updated (conversation_id, updated_at),
    CONSTRAINT fk_messages_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_messages_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS message_reactions (
    message_id  BIGINT UNSIGNED NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    emoji       VARCHAR(32)     NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id),
    KEY idx_message_reactions_user (user_id),
    KEY idx_message_reactions_created (created_at),
    CONSTRAINT fk_message_reactions_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_message_reactions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- «Eliminar para ti»
CREATE TABLE IF NOT EXISTS message_hidden (
    user_id     BIGINT UNSIGNED NOT NULL,
    message_id  BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, message_id),
    KEY idx_message_hidden_message (message_id),
    CONSTRAINT fk_message_hidden_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_message_hidden_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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

-- Cifrado de extremo a extremo: clave pública de cada cuenta (X25519) y copia de la privada cifrada con el PIN.
CREATE TABLE IF NOT EXISTS user_keys (
    user_id     BIGINT UNSIGNED NOT NULL,
    key_id      INT UNSIGNED    NOT NULL DEFAULT 1 COMMENT 'Sube cada vez que la cuenta crea una clave nueva',
    public_key  VARCHAR(64)     NOT NULL,
    backup_blob VARCHAR(512)    NULL COMMENT 'Clave privada cifrada con una clave derivada del PIN',
    backup_salt VARCHAR(64)     NULL,
    backup_auth VARCHAR(255)    NULL COMMENT 'password_hash de la prueba derivada del PIN',
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_user_keys_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Clave de cada época del chat cifrada para cada participante.
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

-- Quién abrió una foto de visualización única.
CREATE TABLE IF NOT EXISTS message_views (
    message_id BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    viewed_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id),
    KEY idx_message_views_user (user_id),
    CONSTRAINT fk_message_views_message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE,
    CONSTRAINT fk_message_views_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
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
    is_live           TINYINT(1)       NOT NULL DEFAULT 0 COMMENT 'Foto en movimiento: el video corto se repite en bucle con la etiqueta LIVE',
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

-- -----------------------------------------------------------------------------
-- Notas (6 horas): una activa por persona, para sus seguidores, sus amigos (se siguen mutuamente)
-- o sus mejores amigos (lista privada close_friends).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_notes (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id     BIGINT UNSIGNED NOT NULL,
    body        VARCHAR(60)     NOT NULL DEFAULT '',
    audience    ENUM('followers', 'friends', 'close_friends') NOT NULL DEFAULT 'followers',
    gif_id      VARCHAR(64)     NULL COMMENT 'Sticker de GIPHY',
    gif_kind    ENUM('gif', 'sticker') NULL,
    gif_url     VARCHAR(500)    NULL,
    gif_width   SMALLINT UNSIGNED NULL,
    gif_height  SMALLINT UNSIGNED NULL,
    gif_title   VARCHAR(140)    NULL,
    song_id     BIGINT UNSIGNED NULL,
    song_start  SMALLINT UNSIGNED NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at  DATETIME        NOT NULL,
    PRIMARY KEY (id),
    KEY idx_user_notes_user (user_id, expires_at),
    KEY idx_user_notes_expires (expires_at),
    CONSTRAINT fk_user_notes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_user_notes_song FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Quién vio cada nota (quien la publicó no cuenta) y quién le dio me gusta.
CREATE TABLE IF NOT EXISTS note_views (
    note_id    BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    viewed_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (note_id, user_id),
    KEY idx_note_views_user (user_id),
    CONSTRAINT fk_note_views_note FOREIGN KEY (note_id) REFERENCES user_notes (id) ON DELETE CASCADE,
    CONSTRAINT fk_note_views_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS note_likes (
    note_id    BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (note_id, user_id),
    KEY idx_note_likes_user (user_id),
    CONSTRAINT fk_note_likes_note FOREIGN KEY (note_id) REFERENCES user_notes (id) ON DELETE CASCADE,
    CONSTRAINT fk_note_likes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS close_friends (
    user_id     BIGINT UNSIGNED NOT NULL,
    friend_id   BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, friend_id),
    KEY idx_close_friends_friend (friend_id),
    CONSTRAINT fk_close_friends_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_close_friends_friend FOREIGN KEY (friend_id) REFERENCES users (id) ON DELETE CASCADE
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

-- Apelaciones: una suspensión (se envía con usuario y contraseña desde el inicio de sesión) o una advertencia.
CREATE TABLE IF NOT EXISTS appeals (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED NOT NULL,
    type             ENUM('suspension', 'warning') NOT NULL,
    warning_id       BIGINT UNSIGNED NULL,
    sanction_reason  VARCHAR(255)    NULL COMMENT 'Motivo de la sanción cuando se apeló',
    message          VARCHAR(1000)   NOT NULL,
    status           ENUM('pending', 'accepted', 'rejected') NOT NULL DEFAULT 'pending',
    reviewed_by      BIGINT UNSIGNED NULL,
    reviewed_at      DATETIME        NULL,
    resolution_note  VARCHAR(500)    NULL,
    created_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_appeals_status (status, created_at),
    KEY idx_appeals_user (user_id, created_at),
    CONSTRAINT fk_appeals_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_appeals_warning FOREIGN KEY (warning_id) REFERENCES user_warnings (id) ON DELETE CASCADE,
    CONSTRAINT fk_appeals_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Traducción con IA de una publicación a un idioma; source_hash invalida la copia si se edita el texto.
CREATE TABLE IF NOT EXISTS post_translations (
    post_id      BIGINT UNSIGNED NOT NULL,
    target_lang  CHAR(2)         NOT NULL,
    source_lang  VARCHAR(8)      NULL,
    source_hash  CHAR(40)        NOT NULL,
    body         TEXT            NOT NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, target_lang),
    CONSTRAINT fk_post_translations_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Una fila por persona y publicación vista (requisito de visualizaciones de los colaboradores).
CREATE TABLE IF NOT EXISTS post_views (
    post_id    BIGINT UNSIGNED NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    viewed_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (post_id, user_id),
    KEY idx_post_views_user (user_id),
    CONSTRAINT fk_post_views_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    CONSTRAINT fk_post_views_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Medios de pago para recargar (PayPal, Llave Bre-B…): los configura la administración.
CREATE TABLE IF NOT EXISTS payment_methods (
    id                INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    name              VARCHAR(60)      NOT NULL,
    instructions      VARCHAR(1000)    NOT NULL COMMENT 'Cuenta, llave o correo y los pasos para pagar',
    min_amount_cents  INT UNSIGNED     NOT NULL DEFAULT 100,
    is_active         TINYINT(1)       NOT NULL DEFAULT 1,
    position          SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_payment_methods_active (is_active, position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS wallets (
    user_id        BIGINT UNSIGNED NOT NULL,
    balance_cents  BIGINT          NOT NULL DEFAULT 0,
    updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_wallets_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS wallet_topups (
    id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id            BIGINT UNSIGNED NOT NULL,
    payment_method_id  INT UNSIGNED    NULL,
    method_name        VARCHAR(60)     NOT NULL COMMENT 'Nombre del medio al pedirla',
    amount_cents       INT UNSIGNED    NOT NULL COMMENT 'Lo que dice haber pagado',
    credited_cents     INT UNSIGNED    NULL COMMENT 'Lo acreditado al aprobar',
    reference          VARCHAR(120)    NOT NULL COMMENT 'Número de transacción o referencia del pago',
    note               VARCHAR(500)    NULL,
    proof_path         VARCHAR(255)    NOT NULL COMMENT 'Comprobante en storage/ (no se sirve por HTTP)',
    status             ENUM('pending', 'approved', 'rejected', 'cancelled') NOT NULL DEFAULT 'pending',
    decision_note      VARCHAR(255)    NULL,
    reviewed_by        BIGINT UNSIGNED NULL,
    reviewed_at        DATETIME        NULL,
    created_at         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_wallet_topups_status (status, created_at),
    KEY idx_wallet_topups_user (user_id, created_at),
    CONSTRAINT fk_wallet_topups_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_wallet_topups_method FOREIGN KEY (payment_method_id) REFERENCES payment_methods (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_topups_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Retiros de lo ganado como colaborador: el importe se descuenta al pedirlo y se devuelve si se rechaza.
CREATE TABLE IF NOT EXISTS wallet_withdrawals (
    id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id           BIGINT UNSIGNED NOT NULL,
    amount_cents      INT UNSIGNED    NOT NULL,
    method            VARCHAR(60)     NOT NULL COMMENT 'Por dónde quiere recibirlo',
    account           VARCHAR(255)    NOT NULL COMMENT 'Cuenta, correo o llave donde recibirlo',
    status            ENUM('pending', 'paid', 'rejected', 'cancelled') NOT NULL DEFAULT 'pending',
    payout_reference  VARCHAR(120)    NULL,
    decision_note     VARCHAR(255)    NULL,
    reviewed_by       BIGINT UNSIGNED NULL,
    reviewed_at       DATETIME        NULL,
    created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_wallet_withdrawals_status (status, created_at),
    KEY idx_wallet_withdrawals_user (user_id, created_at),
    CONSTRAINT fk_wallet_withdrawals_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_wallet_withdrawals_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Recargas con Google Play Billing (app de Android): una fila por token de compra, para no acreditarla dos veces.
CREATE TABLE IF NOT EXISTS play_purchases (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NULL,
    product_id      VARCHAR(64)     NOT NULL,
    token_hash      CHAR(64)        NOT NULL COMMENT 'SHA-256 del token de compra',
    purchase_token  VARCHAR(1024)   NOT NULL,
    order_id        VARCHAR(100)    NULL,
    price_cents     INT UNSIGNED    NOT NULL,
    credited_cents  INT UNSIGNED    NOT NULL COMMENT 'Precio menos la comisión de Google',
    is_test         TINYINT(1)      NOT NULL DEFAULT 0 COMMENT 'Compra de prueba (cuentas de prueba de Play Console)',
    consumed        TINYINT(1)      NOT NULL DEFAULT 0,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_play_purchases_token (token_hash),
    KEY idx_play_purchases_user (user_id, created_at),
    CONSTRAINT fk_play_purchases_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cuentas que la administración habilitó como colaboradoras sin exigirles los requisitos.
CREATE TABLE IF NOT EXISTS collaborator_grants (
    user_id     BIGINT UNSIGNED NOT NULL,
    granted_by  BIGINT UNSIGNED NULL,
    note        VARCHAR(255)    NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_collaborator_grants_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_collaborator_grants_admin FOREIGN KEY (granted_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Plan de suscripción del colaborador: precio en USD por un número de días que elige la persona.
CREATE TABLE IF NOT EXISTS collaborator_plans (
    user_id       BIGINT UNSIGNED   NOT NULL,
    price_cents   INT UNSIGNED      NOT NULL,
    period_days   SMALLINT UNSIGNED NOT NULL,
    description   VARCHAR(300)      NULL,
    is_active     TINYINT(1)        NOT NULL DEFAULT 1 COMMENT '0 = en pausa: no acepta suscripciones nuevas',
    activated_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_collaborator_plans_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cada compra de una suscripción. Comprar otra vez antes de que venza suma los días al final del periodo actual.
CREATE TABLE IF NOT EXISTS collaborator_subscriptions (
    id                BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    collaborator_id   BIGINT UNSIGNED   NOT NULL,
    subscriber_id     BIGINT UNSIGNED   NOT NULL,
    price_cents       INT UNSIGNED      NOT NULL,
    commission_cents  INT UNSIGNED      NOT NULL COMMENT 'Comisión de TREVIX',
    earning_cents     INT UNSIGNED      NOT NULL COMMENT 'Lo que recibe el colaborador',
    period_days       SMALLINT UNSIGNED NOT NULL,
    starts_at         DATETIME          NOT NULL,
    expires_at        DATETIME          NOT NULL,
    created_at        DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_collab_subs_access (subscriber_id, collaborator_id, expires_at),
    KEY idx_collab_subs_collaborator (collaborator_id, expires_at),
    CONSTRAINT fk_collab_subs_collaborator FOREIGN KEY (collaborator_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_collab_subs_subscriber FOREIGN KEY (subscriber_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Movimientos del monedero (positivos entran, negativos salen) con el saldo que quedó.
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id              BIGINT UNSIGNED NOT NULL,
    type                 ENUM('topup', 'subscription', 'earning', 'withdrawal', 'withdrawal_refund', 'adjustment',
                              'gift_purchase', 'gift_received', 'ad_payment', 'ad_refund') NOT NULL,
    amount_cents         BIGINT          NOT NULL,
    balance_after_cents  BIGINT          NOT NULL,
    counterpart_id       BIGINT UNSIGNED NULL COMMENT 'Colaborador o suscriptor de la suscripción',
    topup_id             BIGINT UNSIGNED NULL,
    withdrawal_id        BIGINT UNSIGNED NULL,
    subscription_id      BIGINT UNSIGNED NULL,
    note                 VARCHAR(255)    NULL,
    created_at           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_wallet_transactions_user (user_id, id),
    CONSTRAINT fk_wallet_transactions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_wallet_transactions_counterpart FOREIGN KEY (counterpart_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_transactions_topup FOREIGN KEY (topup_id) REFERENCES wallet_topups (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_transactions_withdrawal FOREIGN KEY (withdrawal_id) REFERENCES wallet_withdrawals (id) ON DELETE SET NULL,
    CONSTRAINT fk_wallet_transactions_subscription FOREIGN KEY (subscription_id) REFERENCES collaborator_subscriptions (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- Regalos: catálogo del panel, compra con el monedero, inventario y envíos
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gift_categories (
    id          INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    name        VARCHAR(60)       NOT NULL,
    position    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    is_active   TINYINT(1)        NOT NULL DEFAULT 1,
    created_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gift_categories_position (is_active, position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gifts (
    id           INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    category_id  INT UNSIGNED      NULL,
    name         VARCHAR(60)       NOT NULL,
    kind         ENUM('gif', 'sticker') NOT NULL DEFAULT 'sticker',
    source       ENUM('upload', 'giphy') NOT NULL,
    media_path   VARCHAR(255)      NULL COMMENT 'Archivo subido (uploads/gifts)',
    giphy_id     VARCHAR(64)       NULL,
    media_url    VARCHAR(500)      NULL COMMENT 'URL de GIPHY',
    width        SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    height       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    price_cents  INT UNSIGNED      NOT NULL,
    position     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    is_active    TINYINT(1)        NOT NULL DEFAULT 1,
    created_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gifts_catalog (is_active, category_id, position),
    CONSTRAINT fk_gifts_category FOREIGN KEY (category_id) REFERENCES gift_categories (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Regalos comprados para enviar después: una fila por unidad, con lo que se pagó por ella.
CREATE TABLE IF NOT EXISTS gift_inventory (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id      BIGINT UNSIGNED NOT NULL,
    gift_id      INT UNSIGNED    NOT NULL,
    price_cents  INT UNSIGNED    NOT NULL,
    created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gift_inventory_user (user_id, gift_id, id),
    CONSTRAINT fk_gift_inventory_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_gift_inventory_gift FOREIGN KEY (gift_id) REFERENCES gifts (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cada regalo enviado, con una copia del nombre y la imagen (el panel puede editarlo o retirarlo después).
CREATE TABLE IF NOT EXISTS gift_sends (
    id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    sender_id         BIGINT UNSIGNED NULL,
    recipient_id      BIGINT UNSIGNED NOT NULL,
    gift_id           INT UNSIGNED    NULL,
    gift_name         VARCHAR(60)     NOT NULL,
    gift_kind         ENUM('gif', 'sticker') NOT NULL,
    media             VARCHAR(500)    NOT NULL COMMENT 'Ruta subida o URL de GIPHY',
    width             SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    height            SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    price_cents       INT UNSIGNED    NOT NULL,
    commission_cents  INT UNSIGNED    NOT NULL COMMENT 'Comisión de TREVIX',
    earning_cents     INT UNSIGNED    NOT NULL COMMENT 'Lo que recibe quien lo recibe',
    context           ENUM('profile', 'message', 'post', 'story') NOT NULL DEFAULT 'profile',
    post_id           BIGINT UNSIGNED NULL,
    story_id          BIGINT UNSIGNED NULL COMMENT 'Sin FK: las historias caducan y se borran',
    message_id        BIGINT UNSIGNED NULL,
    from_inventory    TINYINT(1)      NOT NULL DEFAULT 0,
    created_at        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_gift_sends_recipient (recipient_id, id),
    KEY idx_gift_sends_sender (sender_id, id),
    CONSTRAINT fk_gift_sends_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT fk_gift_sends_recipient FOREIGN KEY (recipient_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_gift_sends_gift FOREIGN KEY (gift_id) REFERENCES gifts (id) ON DELETE SET NULL,
    CONSTRAINT fk_gift_sends_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- La campana del perfil: user_id recibe un aviso cuando target_id publica, comparte una nota o sube una historia.
CREATE TABLE IF NOT EXISTS profile_alerts (
    user_id     BIGINT UNSIGNED NOT NULL,
    target_id   BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, target_id),
    KEY idx_profile_alerts_target (target_id),
    CONSTRAINT fk_profile_alerts_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_profile_alerts_target FOREIGN KEY (target_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- OND-ADS: anuncios y promociones pagadas con el monedero, revisadas por la administración
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ad_campaigns (
    id               BIGINT UNSIGNED   NOT NULL AUTO_INCREMENT,
    user_id          BIGINT UNSIGNED   NOT NULL,
    kind             ENUM('post', 'community', 'group', 'custom') NOT NULL,
    post_id          BIGINT UNSIGNED   NULL,
    community_id     BIGINT UNSIGNED   NULL,
    conversation_id  BIGINT UNSIGNED   NULL COMMENT 'Grupo público que se promociona',
    title            VARCHAR(80)       NULL COMMENT 'Anuncio libre',
    body             VARCHAR(300)      NULL,
    image_path       VARCHAR(255)      NULL COMMENT 'uploads/ads',
    link_url         VARCHAR(500)      NULL,
    cta              ENUM('learn_more', 'shop', 'visit', 'sign_up', 'contact') NULL,
    days             SMALLINT UNSIGNED NOT NULL,
    daily_cents      INT UNSIGNED      NOT NULL,
    total_cents      INT UNSIGNED      NOT NULL,
    reach_min        SMALLINT UNSIGNED NOT NULL COMMENT 'Personas por día garantizadas (si no se alcanza, se devuelve la parte)',
    reach_max        SMALLINT UNSIGNED NOT NULL COMMENT 'Tope de personas por día',
    status           ENUM('pending', 'active', 'finished', 'rejected', 'cancelled', 'removed') NOT NULL DEFAULT 'pending',
    review_note      VARCHAR(255)      NULL,
    reviewed_by      BIGINT UNSIGNED   NULL,
    reviewed_at      DATETIME          NULL,
    starts_at        DATETIME          NULL,
    ends_at          DATETIME          NULL,
    settled_at       DATETIME          NULL,
    refunded_cents   INT UNSIGNED      NOT NULL DEFAULT 0,
    impressions      INT UNSIGNED      NOT NULL DEFAULT 0 COMMENT 'Personas distintas de cada día, sumadas',
    clicks           INT UNSIGNED      NOT NULL DEFAULT 0,
    created_at       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ad_campaigns_user (user_id, id),
    KEY idx_ad_campaigns_status (status, ends_at),
    CONSTRAINT fk_ad_campaigns_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_ad_campaigns_post FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE SET NULL,
    CONSTRAINT fk_ad_campaigns_community FOREIGN KEY (community_id) REFERENCES communities (id) ON DELETE SET NULL,
    CONSTRAINT fk_ad_campaigns_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE SET NULL,
    CONSTRAINT fk_ad_campaigns_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Una fila por persona y día de campaña (día 0 = las primeras 24 horas desde la aprobación).
CREATE TABLE IF NOT EXISTS ad_impressions (
    campaign_id  BIGINT UNSIGNED   NOT NULL,
    day_index    SMALLINT UNSIGNED NOT NULL,
    user_id      BIGINT UNSIGNED   NOT NULL,
    clicked_at   DATETIME          NULL,
    created_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (campaign_id, day_index, user_id),
    KEY idx_ad_impressions_user (user_id, created_at),
    CONSTRAINT fk_ad_impressions_campaign FOREIGN KEY (campaign_id) REFERENCES ad_campaigns (id) ON DELETE CASCADE,
    CONSTRAINT fk_ad_impressions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Stickers y GIF de GIPHY guardados en favoritos para el chat.
CREATE TABLE IF NOT EXISTS sticker_favorites (
    user_id     BIGINT UNSIGNED   NOT NULL,
    giphy_id    VARCHAR(64)       NOT NULL,
    kind        ENUM('gif', 'sticker') NOT NULL DEFAULT 'sticker',
    url         VARCHAR(500)      NOT NULL,
    width       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    height      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    title       VARCHAR(140)      NULL,
    created_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, giphy_id),
    KEY idx_sticker_favorites_user (user_id, created_at),
    CONSTRAINT fk_sticker_favorites_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Solicitudes que IX (atención al cliente con IA en el chat de la cuenta de soporte) clasificó para el equipo.
CREATE TABLE IF NOT EXISTS support_tickets (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id         BIGINT UNSIGNED NOT NULL,
    conversation_id BIGINT UNSIGNED NULL,
    message_id      BIGINT UNSIGNED NULL COMMENT 'Último mensaje de la persona que la actualizó',
    category        ENUM('pregunta', 'saludo', 'error', 'sugerencia', 'reporte', 'queja', 'reclamo', 'peticion', 'otro') NOT NULL DEFAULT 'otro',
    priority        ENUM('baja', 'media', 'alta') NOT NULL DEFAULT 'media',
    summary         VARCHAR(255)    NOT NULL DEFAULT '',
    excerpt         VARCHAR(500)    NOT NULL DEFAULT '',
    needs_human     TINYINT(1)      NOT NULL DEFAULT 0,
    status          ENUM('open', 'closed') NOT NULL DEFAULT 'open',
    closed_by       BIGINT UNSIGNED NULL,
    closed_at       DATETIME        NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_support_tickets_status (status, needs_human, updated_at),
    KEY idx_support_tickets_user (user_id, status, category, updated_at),
    CONSTRAINT fk_support_tickets_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_support_tickets_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id) ON DELETE SET NULL,
    CONSTRAINT fk_support_tickets_closer FOREIGN KEY (closed_by) REFERENCES users (id) ON DELETE SET NULL
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
