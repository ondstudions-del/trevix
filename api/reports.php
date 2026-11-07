<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Envío de reportes (con JavaScript responde JSON; sin él, redirige con un aviso). */
(new Trevix\Controllers\ReportController())->api();
