<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Seguir, dejar de seguir y responder solicitudes de seguimiento. */
(new Trevix\Controllers\RelationshipController())->follows();
