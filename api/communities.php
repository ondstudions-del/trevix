<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Comunidades: crear, editar, unirse, salir, solicitudes, moderación de miembros y publicaciones. */
(new Trevix\Controllers\CommunityController())->api();
