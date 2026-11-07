<?php

use Trevix\Core\View;

/** @var string $content */
?>
<!doctype html>
<html lang="es">
<head>
    <?php View::partial('head', [
        'title'       => $title ?? 'TREVIX',
        'description' => $description ?? null,
        'styles'      => ['landing'],
    ]); ?>
</head>
<body class="public-body">
    <a class="skip-link" href="#main">Saltar al contenido</a>
    <?= $content ?>
    <div class="toast-region" id="toast-region" role="status" aria-live="polite"></div>
    <script src="<?= e(asset('js/landing.js')) ?>" defer></script>
</body>
</html>
