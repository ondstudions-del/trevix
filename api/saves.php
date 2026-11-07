<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Alterna si la publicación está en los guardados de la sesión actual. */
(new Trevix\Controllers\PostController())->toggle('save');
