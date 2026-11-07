<?php
declare(strict_types=1);

require __DIR__ . '/app/bootstrap.php';

// Los hilos se muestran mezclados en las pestañas del inicio: la antigua sección Threads lleva allí.
Trevix\Core\Response::redirect(url('feed.php'), 301);
