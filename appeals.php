<?php
declare(strict_types=1);

require __DIR__ . '/app/bootstrap.php';

/* Advertencias de la cuenta y sus apelaciones. */
(new Trevix\Controllers\AppealController())->mine();
