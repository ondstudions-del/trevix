<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Crear comentarios y respuestas, y eliminarlos. */
(new Trevix\Controllers\CommentController())->api();
