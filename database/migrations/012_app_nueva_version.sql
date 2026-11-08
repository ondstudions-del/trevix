-- TREVIX · Nueva versión de la app: datos personales y música del perfil, sugerencias de amigos.
-- Solo para bases creadas antes de este cambio; trevix_db.sql ya lo incluye.

-- Datos personales del perfil (solo la app los edita). city_key / hometown_key: la ciudad sin mayúsculas ni
-- acentos, para sugerir personas de la misma ciudad. details_audience decide quién ve ciudades, cumpleaños,
-- situación sentimental, género y contactos (los enlaces e intereses son públicos).
-- links: [{"title","url"}] · contacts: [{"type","value"}] · song_*: canción del perfil (fragmento de 30 s).
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