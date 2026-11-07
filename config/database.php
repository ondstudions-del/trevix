<?php
declare(strict_types=1);

return [
    'host'     => getenv('TREVIX_DB_HOST') ?: '127.0.0.1',
    'port'     => (int) (getenv('TREVIX_DB_PORT') ?: 3306),
    'name'     => getenv('TREVIX_DB_NAME') ?: 'trevix_db',
    'user'     => getenv('TREVIX_DB_USER') ?: 'root',
    'password' => getenv('TREVIX_DB_PASS') ?: '',
    'charset'  => 'utf8mb4',
];
