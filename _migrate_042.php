<?php
declare(strict_types=1);

$token = 'cl042-' . hash('sha256', 'trevix-livekit-042');
if (!hash_equals($token, (string) ($_GET['t'] ?? ''))) {
    http_response_code(404);
    exit('missing');
}

require __DIR__ . '/app/bootstrap.php';

use Trevix\Core\Database;

header('Content-Type: text/plain; charset=utf-8');

$sql = (string) file_get_contents(__DIR__ . '/database/migrations/042_livekit.sql');
$parts = array_filter(array_map('trim', preg_split('/;\s*\n/', $sql) ?: []));
$already = [1050, 1061];

try {
    $pdo = Database::connection();
    $out = [];
    foreach ($parts as $i => $statement) {
        if ($statement === '') {
            continue;
        }
        $label = '#' . ($i + 1);
        try {
            $pdo->exec($statement);
            $out[] = "OK $label";
        } catch (PDOException $e) {
            $code = (int) $e->errorInfo[1];
            $out[] = in_array($code, $already, true) ? "SKIP $label ($code)" : throw $e;
        }
    }
    echo "DONE\n" . implode("\n", $out) . "\n";
} catch (Throwable $e) {
    http_response_code(500);
    echo 'FAIL: ' . $e->getMessage();
}