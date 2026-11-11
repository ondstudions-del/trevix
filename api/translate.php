<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Traducir una publicación con IA (POST post_id, lang opcional). */
(new Trevix\Controllers\PostController())->translate();
