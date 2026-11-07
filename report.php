<?php
declare(strict_types=1);

require __DIR__ . '/app/bootstrap.php';

/* Formulario para reportar una publicación, comentario, cuenta, comunidad, mensaje o historia. */
(new Trevix\Controllers\ReportController())->page();
