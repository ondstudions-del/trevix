CREATE TABLE IF NOT EXISTS oauth_apps (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(80) NOT NULL,
    description VARCHAR(500) NOT NULL DEFAULT '',
    icon_path VARCHAR(255) NULL DEFAULT NULL,
    platform ENUM('android', 'ios', 'web') NOT NULL DEFAULT 'android',
    package_name VARCHAR(200) NULL DEFAULT NULL,
    website_url VARCHAR(500) NULL DEFAULT NULL,
    redirect_uris TEXT NOT NULL,
    client_id VARCHAR(64) NOT NULL,
    client_secret_hash VARCHAR(255) NOT NULL,
    status ENUM('pending', 'approved', 'rejected', 'revoked') NOT NULL DEFAULT 'pending',
    review_note VARCHAR(500) NULL DEFAULT NULL,
    reviewed_by BIGINT UNSIGNED NULL DEFAULT NULL,
    reviewed_at DATETIME NULL DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_oauth_apps_client (client_id),
    KEY idx_oauth_apps_owner (owner_id, status),
    KEY idx_oauth_apps_status (status, created_at),
    CONSTRAINT fk_oauth_apps_owner FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_oauth_apps_reviewer FOREIGN KEY (reviewed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS oauth_authorization_codes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    app_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    code VARCHAR(64) NOT NULL,
    redirect_uri VARCHAR(500) NOT NULL,
    expires_at DATETIME NOT NULL,
    used_at DATETIME NULL DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_oauth_code (code),
    KEY idx_oauth_code_app (app_id),
    CONSTRAINT fk_oauth_code_app FOREIGN KEY (app_id) REFERENCES oauth_apps (id) ON DELETE CASCADE,
    CONSTRAINT fk_oauth_code_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS oauth_access_tokens (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    app_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    revoked_at DATETIME NULL DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_oauth_token (token_hash),
    KEY idx_oauth_token_user (user_id, app_id),
    CONSTRAINT fk_oauth_token_app FOREIGN KEY (app_id) REFERENCES oauth_apps (id) ON DELETE CASCADE,
    CONSTRAINT fk_oauth_token_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
