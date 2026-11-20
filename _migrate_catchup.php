<?php
declare(strict_types=1);

/**
 * Aplica migraciones 040, 041 y 042 en producción (una sola visita).
 * Token: clcatchup- + sha256('trevix-catchup-040-042')
 */
$token = 'clcatchup-' . hash('sha256', 'trevix-catchup-040-042');
if (!hash_equals($token, (string) ($_GET['t'] ?? ''))) {
    http_response_code(404);
    exit('missing');
}

require __DIR__ . '/app/bootstrap.php';

use Trevix\Core\Database;

header('Content-Type: text/plain; charset=utf-8');

$files = [
    '040' => __DIR__ . '/database/migrations/040_comment_media_paypal.sql',
    '041' => __DIR__ . '/database/migrations/041_profile_photos.sql',
    '042' => __DIR__ . '/database/migrations/042_livekit.sql',
];
// Modo portable: un solo archivo PHP (sin carpeta database/) en el servidor.
if (!is_file($files['041'])) {
    $files['041'] = __DIR__ . '/041_profile_photos.embedded.sql';
    if (!is_file($files['041'])) {
        $embedded = <<<'SQL'
ALTER TABLE users
    ADD COLUMN avatar_caption VARCHAR(500) NULL AFTER avatar_path,
    ADD COLUMN avatar_alt VARCHAR(300) NULL AFTER avatar_caption,
    ADD COLUMN avatar_privacy VARCHAR(20) NOT NULL DEFAULT 'public' COMMENT 'public|followers|only_me' AFTER avatar_alt,
    ADD COLUMN avatar_notify_muted TINYINT(1) NOT NULL DEFAULT 0 AFTER avatar_privacy,
    ADD COLUMN avatar_updated_at DATETIME NULL AFTER avatar_notify_muted,
    ADD COLUMN cover_caption VARCHAR(500) NULL AFTER cover_path,
    ADD COLUMN cover_alt VARCHAR(300) NULL AFTER cover_caption,
    ADD COLUMN cover_privacy VARCHAR(20) NOT NULL DEFAULT 'public' COMMENT 'public|followers|only_me' AFTER cover_alt,
    ADD COLUMN cover_notify_muted TINYINT(1) NOT NULL DEFAULT 0 AFTER cover_privacy,
    ADD COLUMN cover_updated_at DATETIME NULL AFTER cover_notify_muted;

CREATE TABLE IF NOT EXISTS profile_photo_likes (
    owner_id   BIGINT UNSIGNED NOT NULL,
    kind       ENUM('avatar', 'cover') NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, owner_id, kind),
    KEY idx_profile_photo_likes_owner (owner_id, kind),
    CONSTRAINT fk_profile_photo_likes_owner FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_profile_photo_likes_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS profile_photo_comments (
    id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_id   BIGINT UNSIGNED NOT NULL,
    kind       ENUM('avatar', 'cover') NOT NULL,
    user_id    BIGINT UNSIGNED NOT NULL,
    body       VARCHAR(1000)   NOT NULL,
    created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_profile_photo_comments_owner (owner_id, kind, id),
    CONSTRAINT fk_profile_photo_comments_owner FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_profile_photo_comments_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL;
        file_put_contents($files['041'], $embedded);
    }
}
$already = [1060, 1061, 1050, 1826];
$out = [];

try {
    $pdo = Database::connection();
    foreach ($files as $label => $path) {
        if (!is_file($path)) {
            $out[] = "FAIL $label: falta $path";
            continue;
        }
        $sql = (string) file_get_contents($path);
        $parts = array_filter(array_map('trim', preg_split('/;\s*\n/', $sql) ?: []));
        foreach ($parts as $i => $statement) {
            if ($statement === '') {
                continue;
            }
            $step = "$label#" . ($i + 1);
            try {
                $pdo->exec($statement);
                $out[] = "OK $step";
            } catch (PDOException $e) {
                $code = (int) ($e->errorInfo[1] ?? 0);
                $out[] = (in_array($code, $already, true) ? 'SKIP' : 'FAIL ' . $code) . " $step: " . $e->getMessage();
            }
        }
    }
    @unlink(__FILE__);
    echo implode("\n", $out) . "\nDONE\n";
} catch (Throwable $e) {
    http_response_code(500);
    echo 'FAIL: ' . $e->getMessage() . "\n";
}