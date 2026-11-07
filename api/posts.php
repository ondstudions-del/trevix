<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Crear (multipart, con adjuntos o compartiendo otra publicación) y eliminar publicaciones. */
(new Trevix\Controllers\PostController())->api();
