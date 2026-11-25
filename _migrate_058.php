<?php
declare(strict_types=1);

$token = 'cl058-' . hash('sha256', 'trevix-ond-ads-placements-058');
if (!hash_equals($token, (string) ($_GET['t'] ?? ''))) {
    http_response_code(404);
    exit;
}

require __DIR__ . '/app/bootstrap.php';

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');

use Trevix\Core\Database;

$sql = file_get_contents(__DIR__ . '/database/migrations/058_ond_ads_placements.sql');
if ($sql === false || trim($sql) === '') {
    $sql = <<<'SQL'
ALTER TABLE ad_campaigns
    ADD COLUMN creative_type ENUM('native', 'app', 'website', 'product', 'video') NOT NULL DEFAULT 'native' AFTER kind,
    ADD COLUMN placements VARCHAR(120) NOT NULL DEFAULT 'feed,profile,stories,reels,community' AFTER creative_type,
    ADD COLUMN video_path VARCHAR(255) NULL COMMENT 'uploads/ads' AFTER image_path,
    ADD COLUMN product_label VARCHAR(60) NULL COMMENT 'Precio o etiqueta de producto' AFTER body;

ALTER TABLE users
    ADD COLUMN ads_personalized TINYINT(1) NOT NULL DEFAULT 1 AFTER notify_mentions,
    ADD COLUMN ads_feed TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_personalized,
    ADD COLUMN ads_profile TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_feed,
    ADD COLUMN ads_stories TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_profile,
    ADD COLUMN ads_reels TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_stories,
    ADD COLUMN ads_community TINYINT(1) NOT NULL DEFAULT 1 AFTER ads_reels;
SQL;
}

try {
    Database::connection()->exec($sql);
    echo "058 OK\n";
} catch (Throwable $e) {
    http_response_code(500);
    echo 'FAIL: ' . $e->getMessage();
}