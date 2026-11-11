<?php
declare(strict_types=1);

require __DIR__ . '/app/bootstrap.php';

/* Cambiar el idioma de la interfaz (español o inglés). */
(new Trevix\Controllers\LangController())->change();
