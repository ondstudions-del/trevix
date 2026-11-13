<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Listas de reproducción de reels: crear, editar, eliminar, agregar y quitar videos. */
(new Trevix\Controllers\PlaylistController())->api();
