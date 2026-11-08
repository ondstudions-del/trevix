<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Sugerencias de @menciones mientras se escribe (compositor y editor de historias). */
(new Trevix\Controllers\MentionController())->suggest();
