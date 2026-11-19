-- Fotos en comentarios y PayPal como proveedor de recarga.
ALTER TABLE comments
    ADD COLUMN media_path VARCHAR(255) NULL AFTER gif_title,
    ADD COLUMN media_width INT UNSIGNED NULL AFTER media_path,
    ADD COLUMN media_height INT UNSIGNED NULL AFTER media_width;

ALTER TABLE payment_methods
    ADD COLUMN provider VARCHAR(20) NOT NULL DEFAULT 'manual' COMMENT 'manual|paypal' AFTER name;