<?php
declare(strict_types=1);

require dirname(__DIR__) . '/app/bootstrap.php';

/* Campana del perfil: avisos de publicaciones, notas e historias de una cuenta. */
(new Trevix\Controllers\RelationshipController())->alerts();
