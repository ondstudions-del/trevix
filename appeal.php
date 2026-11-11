<?php
declare(strict_types=1);

require __DIR__ . '/app/bootstrap.php';

/* Apelar una suspensión o un baneo (sin sesión: con usuario y contraseña). */
(new Trevix\Controllers\AppealController())->suspension();
