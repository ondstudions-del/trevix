<?php
/**
 * @var string      $title
 * @var string|null $description
 * @var string[]    $styles
 */
$styles = $styles ?? [];
?>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title><?= e($title ?? 'TREVIX') ?></title>
<meta name="description" content="<?= e($description ?? 'TREVIX — Conecta. Comparte. Descubre. La red social que une fotos, historias, hilos y comunidades.') ?>">
<meta name="theme-color" content="#09090B">
<meta name="color-scheme" content="dark">
<meta property="og:site_name" content="TREVIX">
<meta property="og:title" content="<?= e($title ?? 'TREVIX') ?>">
<link rel="icon" href="<?= e(asset('img/favicon.svg')) ?>" type="image/svg+xml">
<link rel="preload" href="<?= e(url('assets/fonts/inter-latin-wght.woff2')) ?>" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="<?= e(asset('css/tokens.css')) ?>">
<link rel="stylesheet" href="<?= e(asset('css/base.css')) ?>">
<link rel="stylesheet" href="<?= e(asset('css/components.css')) ?>">
<?php foreach ($styles as $style): ?>
<link rel="stylesheet" href="<?= e(asset('css/' . $style . '.css')) ?>">
<?php endforeach; ?>
<script src="<?= e(asset('js/prefs.js')) ?>"></script>
<script src="<?= e(asset('js/core.js')) ?>" defer></script>
<script type="application/json" id="trevix-config"><?= client_config() ?></script>
