<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* GIF y stickers de GIPHY para comentarios y mensajes (la clave de GIPHY no sale del servidor). */
(new Trevix\Controllers\GifController())->api();
