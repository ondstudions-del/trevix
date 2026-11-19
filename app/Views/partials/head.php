<?php
/**
 * @var string      $title
 * @var string|null $description
 * @var string|null $ogImage   URL absoluta de la imagen al compartir el enlace (p. ej. publicación)
 * @var string[]    $styles
 */
$styles = $styles ?? [];
$description = $description ?? t('TREVIX — Conecta. Comparte. Descubre. La red social que une fotos, historias, hilos y comunidades.');
$ogImage = $ogImage ?? null;
?>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title><?= e($title ?? 'TREVIX') ?></title>
<meta name="description" content="<?= e($description) ?>">
<meta name="theme-color" content="#09090B">
<meta name="color-scheme" content="dark">
<meta property="og:site_name" content="TREVIX">
<meta property="og:type" content="<?= $ogImage ? 'article' : 'website' ?>">
<meta property="og:title" content="<?= e($title ?? 'TREVIX') ?>">
<meta property="og:description" content="<?= e($description) ?>">
<?php if (is_string($ogImage) && $ogImage !== ''): ?>
<meta property="og:image" content="<?= e($ogImage) ?>">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:image" content="<?= e($ogImage) ?>">
<?php else: ?>
<meta name="twitter:card" content="summary">
<?php endif; ?>
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
