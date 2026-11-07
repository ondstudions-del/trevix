<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Alterna el "me gusta" de la sesión actual sobre una publicación. */
(new Trevix\Controllers\PostController())->toggle('like');
