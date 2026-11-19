<?php
declare(strict_types=1);

require __DIR__ . '/app/bootstrap.php';

/* Acceso anticipado a la app de Android: nombre y correo. */
(new Trevix\Controllers\EarlyAccessController())->index();
