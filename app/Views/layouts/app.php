<?php

use Trevix\Core\View;

/**
 * Shell de la aplicación: sidebar (escritorio), feed central, panel derecho y navegación inferior (móvil).
 *
 * @var string     $content
 * @var array|null $viewer
 * @var bool       $isPreview
 */
$layoutWide = $layoutWide ?? false;
$aside = $aside ?? [];
$showAside = !$layoutWide && $aside !== [];
?>
<!doctype html>
<html lang="<?= e(locale()) ?>">
<head>
    <?php View::partial('head', ['title' => $title ?? 'TREVIX', 'styles' => ['layout', 'pages', 'music']]); ?>
</head>
<body class="app-body">
    <a class="skip-link" href="#main"><?= e(t('Saltar al contenido')) ?></a>

    <div class="<?= cx('app-shell', ['app-shell--wide' => $layoutWide, 'app-shell--no-aside' => !$showAside && !$layoutWide]) ?>">
        <?php View::partial('sidebar', ['viewer' => $viewer, 'activeNav' => $activeNav ?? '']); ?>
        <?php View::partial('mobile-header', ['viewer' => $viewer]); ?>

        <main id="main" class="app-main" tabindex="-1">
            <?php if ($isPreview): ?>
                <?php View::partial('preview-banner'); ?>
            <?php endif; ?>
            <?php View::partial('app-open'); ?>
            <?php View::partial('site-notices', ['viewer' => $viewer, 'isPreview' => $isPreview]); ?>
            <?php View::partial('flash'); ?>
            <?php if (!$isPreview && $viewer !== null && empty($viewer['email_verified_at']) && !in_array($activeNav ?? '', ['settings', 'messages'], true)): ?>
                <?php View::partial('verify-banner', ['viewer' => $viewer]); ?>
            <?php endif; ?>
            <?= $content ?>
        </main>

        <?php if ($showAside): ?>
            <?php View::partial('right-panel', ['aside' => $aside]); ?>
        <?php endif; ?>
    </div>

    <?php View::partial('mobile-nav', ['viewer' => $viewer, 'activeNav' => $activeNav ?? '']); ?>
    <?php View::partial('composer', ['viewer' => $viewer]); ?>
    <?php View::partial('share-dialog'); ?>
    <?php if (\Trevix\Core\Auth::check()): ?>
        <?php View::partial('report-dialog'); ?>
        <?php View::partial('music-picker'); ?>
        <?php if (\Trevix\Services\Giphy::enabled()): ?>
            <?php View::partial('gif-picker'); ?>
        <?php endif; ?>
    <?php endif; ?>

    <div class="toast-region" id="toast-region" role="status" aria-live="polite"></div>

    <script src="<?= e(asset('js/app.js')) ?>" defer></script>
    <script src="<?= e(asset('js/composer.js')) ?>" defer></script>
    <script src="<?= e(asset('js/posts.js')) ?>" defer></script>
    <script src="<?= e(asset('js/follows.js')) ?>" defer></script>
    <script src="<?= e(asset('js/music.js')) ?>" defer></script>
    <script src="<?= e(asset('js/share.js')) ?>" defer></script>
    <?php if (\Trevix\Core\Auth::check()): ?>
        <script src="<?= e(asset('js/live.js')) ?>" defer></script>
        <script src="<?= e(asset('js/report.js')) ?>" defer></script>
        <script src="<?= e(asset('js/mentions.js')) ?>" defer></script>
        <?php if (\Trevix\Services\Giphy::enabled()): ?>
            <script src="<?= e(asset('js/gifs.js')) ?>" defer></script>
        <?php endif; ?>
    <?php endif; ?>
</body>
</html>
