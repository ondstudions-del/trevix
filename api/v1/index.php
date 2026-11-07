<?php
declare(strict_types=1);

/* API REST v1 para las apps (iOS y Android): JSON con token Bearer. Referencia en docs/API.md. */
define('TREVIX_API', true);

require dirname(__DIR__, 2) . '/app/bootstrap.php';

Trevix\Api\Kernel::run();
