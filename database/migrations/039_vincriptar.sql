-- VINCRIPTAR: el dispositivo nuevo crea el reto; host_user_id queda NULL hasta el escaneo.
-- TTL de aplicación: 60 segundos (DeviceLink::TTL_SECONDS).

ALTER TABLE device_link_challenges
  DROP FOREIGN KEY fk_device_link_host;

ALTER TABLE device_link_challenges
  MODIFY COLUMN host_user_id BIGINT UNSIGNED NULL
    COMMENT 'Cuenta que autoriza (NULL hasta que escanea el VINCODE)',
  MODIFY COLUMN code CHAR(8) NOT NULL
    COMMENT 'Código VINCODE / entrada manual (Crockford)',
  MODIFY COLUMN guest_device_name VARCHAR(120) NULL
    COMMENT 'Dispositivo solicitante (el que genera el VINCODE)',
  MODIFY COLUMN guest_device_type VARCHAR(20) NULL
    COMMENT 'phone, tablet, web, desktop, other';

ALTER TABLE device_link_challenges
  ADD CONSTRAINT fk_device_link_host
    FOREIGN KEY (host_user_id) REFERENCES users (id) ON DELETE CASCADE;
