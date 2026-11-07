<?php

use Trevix\Core\View;

/** @var string $content */
?>
<!doctype html>
<html lang="es">
<head>
    <?php View::partial('head', ['title' => $title ?? 'TREVIX', 'styles' => ['pages', 'music']]); ?>
</head>
<body class="immersive-body">
    <main id="main" class="immersive" tabindex="-1">
        <?= $content ?>
    </main>
    <div class="toast-region" id="toast-region" role="status" aria-live="polite"></div>
</body>
</html>
