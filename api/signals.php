<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Tiempo que una publicación estuvo en pantalla o que se compartió fuera de TREVIX (intereses de «Para ti»). */
(new Trevix\Controllers\PostController())->signal();
