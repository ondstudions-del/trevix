<?php
declare(strict_types=1);

require __DIR__ . '/app/bootstrap.php';

/* Invitación a un grupo de mensajes por enlace. */
(new Trevix\Controllers\GroupInviteController())->show();
