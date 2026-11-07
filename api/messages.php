<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Mensajes privados: enviar, consultar nuevos (sondeo), eliminar y silenciar. */
(new Trevix\Controllers\MessageController())->api();
