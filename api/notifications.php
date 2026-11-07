<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Contadores de avisos sin leer (sondeo) y marcar todas las notificaciones como leídas. */
(new Trevix\Controllers\NotificationController())->api();
