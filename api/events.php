<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* «Asistiré» / «Me interesa» de la sesión actual en un evento. */
(new Trevix\Controllers\EventController())->respond();
