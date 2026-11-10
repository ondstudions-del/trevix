<?php

use Trevix\Core\View;
use Trevix\Models\User;

/**
 * @var string     $content
 * @var array|null $viewer
 * @var array      $sections
 * @var string     $section
 * @var bool       $isPreview
 * @var int        $openReports
 * @var int        $pendingSongs
 */
$openReports = $openReports ?? 0;
$pendingSongs = $pendingSongs ?? 0;
?>
<!doctype html>
<html lang="es">
<head>
    <?php View::partial('head', ['title' => $title ?? 'Administración · TREVIX', 'styles' => ['admin']]); ?>
    <meta name="robots" content="noindex, nofollow">
</head>
<body class="admin-body">
    <a class="skip-link" href="#main">Saltar al contenido</a>
    <div class="admin">
        <aside class="admin__sidebar" aria-label="Navegación de administración">
            <a class="admin__brand" href="<?= e(url('admin/')) ?>">
                <?php View::partial('logo', ['size' => 34, 'wordmark' => true]); ?>
                <span class="admin__tag">Admin</span>
            </a>
            <nav class="admin__nav">
                <?php foreach ($sections as $key => $item): ?>
                    <a class="<?= cx('admin__link', ['is-active' => $section === $key]) ?>" href="<?= e(url($item['path'])) ?>"
                        <?= $section === $key ? 'aria-current="page"' : '' ?>>
                        <?= icon($item['icon']) ?> <span><?= e($item['label']) ?></span>
                        <?php if ($key === 'reports' && $openReports > 0): ?>
                            <span class="admin__badge" aria-label="<?= $openReports ?> pendientes"><?= $openReports > 99 ? '99+' : $openReports ?></span>
                        <?php elseif ($key === 'music' && $pendingSongs > 0): ?>
                            <span class="admin__badge" aria-label="<?= $pendingSongs ?> canciones por revisar"><?= $pendingSongs > 99 ? '99+' : $pendingSongs ?></span>
                        <?php elseif ($key === 'support' && ($openTickets ?? 0) > 0): ?>
                            <span class="admin__badge" aria-label="<?= $openTickets ?> solicitudes de soporte abiertas"><?= $openTickets > 99 ? '99+' : $openTickets ?></span>
                        <?php elseif ($key === 'verification' && ($pendingVerifications ?? 0) > 0): ?>
                            <span class="admin__badge" aria-label="<?= $pendingVerifications ?> solicitudes de verificado"><?= $pendingVerifications > 99 ? '99+' : $pendingVerifications ?></span>
                        <?php endif; ?>
                    </a>
                <?php endforeach; ?>
            </nav>
            <a class="admin__back" href="<?= e(url('feed.php')) ?>"><?= icon('arrow-left') ?> Volver a TREVIX</a>
        </aside>

        <div class="admin__main">
            <header class="admin__topbar">
                <div>
                    <p class="admin__eyebrow">Panel de administración</p>
                    <h1 class="admin__title"><?= e($heading ?? $sections[$section]['label'] ?? 'Dashboard') ?></h1>
                </div>
                <?php if ($viewer): ?>
                    <div class="admin__user">
                        <span class="chip chip--brand"><?= e(User::ROLE_LABELS[$viewer['role'] ?? 'user'] ?? 'Usuario') ?></span>
                        <?= avatar($viewer, 'sm') ?>
                    </div>
                <?php endif; ?>
            </header>
            <main id="main" class="admin__content" tabindex="-1">
                <?php if ($isPreview): ?>
                    <div class="alert alert--info" role="status">
                        <?= icon('info') ?>
                        <p><strong>Vista previa.</strong> En producción este panel solo es accesible para moderadores y administradores autenticados; la verificación de rol ocurre en el servidor.</p>
                    </div>
                <?php endif; ?>
                <?php View::partial('flash'); ?>
                <?= $content ?>
            </main>
        </div>
    </div>
    <?php View::partial('confirm-dialog'); ?>
    <div class="toast-region" id="toast-region" role="status" aria-live="polite"></div>
    <script src="<?= e(asset('js/admin.js')) ?>" defer></script>
</body>
</html>
