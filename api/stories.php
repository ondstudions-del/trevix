<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Historias: publicar, registrar visitas, ver quién la vio, eliminar y responder por mensaje privado. */
(new Trevix\Controllers\StoryController())->api();
