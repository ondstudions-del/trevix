<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Bloquear y desbloquear cuentas. */
(new Trevix\Controllers\RelationshipController())->blocks();
