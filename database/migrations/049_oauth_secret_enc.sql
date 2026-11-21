ALTER TABLE oauth_apps
    ADD COLUMN client_secret_enc TEXT NULL AFTER client_secret_hash;
