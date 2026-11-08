<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Nombre del lugar a partir de la ubicación actual (para publicar con ubicación). */
(new Trevix\Controllers\GeoController())->reverse();
