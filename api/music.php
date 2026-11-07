<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Música: buscar en la biblioteca (selector de canciones), enviar canciones a revisión y gestionarlas. */
(new Trevix\Controllers\MusicController())->api();
