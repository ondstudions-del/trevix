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
$pendingAppeals = $pendingAppeals ?? 0;
$openTickets = $openTickets ?? 0;
$pendingVerifications = $pendingVerifications ?? 0;
$pendingWallet = $pendingWallet ?? 0;
$pendingAds = $pendingAds ?? 0;
$pendingEarlyAccess = $pendingEarlyAccess ?? 0;
$pendingOauthApps = $pendingOauthApps ?? 0;
$pageTitle = isset($sections[$section]['label'])
    ? t('{section} · Administración · TREVIX', ['section' => t($sections[$section]['label'])])
    : t($title ?? 'Administración · TREVIX');

$navGroups = [
    'overview' => ['label' => 'Resumen', 'keys' => ['dashboard']],
    'moderation' => ['label' => 'Moderación', 'keys' => ['reports', 'content', 'music', 'oauth_apps', 'appeals', 'support']],
    'accounts' => ['label' => 'Cuentas', 'keys' => ['users', 'verification']],
    'economy' => ['label' => 'Economía', 'keys' => ['wallet', 'gifts', 'ads']],
    'platform' => ['label' => 'Plataforma', 'keys' => ['push', 'livekit', 'early_access', 'communities', 'settings', 'audit']],
];

$badgeFor = static function (string $key) use (
    $openReports,
    $pendingSongs,
    $pendingAppeals,
    $openTickets,
    $pendingVerifications,
    $pendingWallet,
    $pendingAds,
    $pendingEarlyAccess,
    $pendingOauthApps
): array {
    return match ($key) {
        'reports' => [$openReports, t('{n} pendientes', ['n' => $openReports])],
        'music' => [$pendingSongs, t('{n} canciones por revisar', ['n' => $pendingSongs])],
        'oauth_apps' => [$pendingOauthApps, t('{n} apps por revisar', ['n' => $pendingOauthApps])],
        'appeals' => [$pendingAppeals ?? 0, t('{n} apelaciones pendientes', ['n' => $pendingAppeals ?? 0])],
        'support' => [$openTickets ?? 0, t('{n} solicitudes de soporte abiertas', ['n' => $openTickets ?? 0])],
        'verification' => [$pendingVerifications ?? 0, t('{n} solicitudes de verificado', ['n' => $pendingVerifications ?? 0])],
        'wallet' => [$pendingWallet ?? 0, t('{n} recargas, retiros o solicitudes de colaborador por revisar', ['n' => $pendingWallet ?? 0])],
        'ads' => [$pendingAds ?? 0, t('{n} anuncios por revisar', ['n' => $pendingAds ?? 0])],
        'early_access' => [$pendingEarlyAccess, t('{n} accesos anticipados pendientes', ['n' => $pendingEarlyAccess])],
        default => [0, ''],
    };
};
?>
<!doctype html>
<html lang="<?= e(locale()) ?>">
<head>
    <?php View::partial('head', ['title' => $pageTitle, 'styles' => ['admin']]); ?>
    <meta name="robots" content="noindex, nofollow">
</head>
<body class="admin-body">
    <a class="skip-link" href="#main"><?= e(t('Saltar al contenido')) ?></a>
    <div class="admin" data-admin>
        <div class="admin__backdrop" data-admin-close hidden></div>
        <aside class="admin__sidebar" id="admin-sidebar" aria-label="<?= e(t('Navegación de administración')) ?>">
            <div class="admin__sidebar-top">
                <a class="admin__brand" href="<?= e(url('admin/')) ?>">
                    <?php View::partial('logo', ['size' => 30, 'wordmark' => true]); ?>
                    <span class="admin__tag"><?= e(t('Admin')) ?></span>
                </a>
                <button type="button" class="admin__icon-btn admin__sidebar-close" data-admin-close aria-label="<?= e(t('Cerrar menú')) ?>">
                    <?= icon('x') ?>
                </button>
            </div>
            <label class="admin__nav-search">
                <span class="sr-only"><?= e(t('Buscar sección')) ?></span>
                <?= icon('search') ?>
                <input type="search" data-admin-nav-filter placeholder="<?= e(t('Buscar sección…')) ?>" autocomplete="off">
            </label>
            <nav class="admin__nav" data-admin-nav>
                <?php foreach ($navGroups as $group): ?>
                    <?php
                    $items = [];
                    foreach ($group['keys'] as $key) {
                        if (isset($sections[$key])) {
                            $items[$key] = $sections[$key];
                        }
                    }
                    if ($items === []) {
                        continue;
                    }
                    ?>
                    <div class="admin__group" data-admin-group>
                        <p class="admin__group-label"><?= e(t($group['label'])) ?></p>
                        <?php foreach ($items as $key => $item): ?>
                            <?php [$count, $badgeLabel] = $badgeFor($key); ?>
                            <a class="<?= cx('admin__link', ['is-active' => $section === $key]) ?>"
                                href="<?= e(url($item['path'])) ?>"
                                data-admin-link
                                data-label="<?= e(mb_strtolower(t($item['label']))) ?>"
                                <?= $section === $key ? 'aria-current="page"' : '' ?>>
                                <?= icon($item['icon']) ?>
                                <span><?= e(t($item['label'])) ?></span>
                                <?php if ($count > 0): ?>
                                    <span class="admin__badge" aria-label="<?= e($badgeLabel) ?>"><?= $count > 99 ? '99+' : $count ?></span>
                                <?php endif; ?>
                            </a>
                        <?php endforeach; ?>
                    </div>
                <?php endforeach; ?>
            </nav>
            <a class="admin__back" href="<?= e(url('feed.php')) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver a TREVIX')) ?></a>
        </aside>

        <div class="admin__main">
            <header class="admin__topbar">
                <div class="admin__topbar-start">
                    <button type="button" class="admin__icon-btn admin__menu-btn" data-admin-open aria-controls="admin-sidebar" aria-expanded="false" aria-label="<?= e(t('Abrir menú')) ?>">
                        <?= icon('menu') ?>
                    </button>
                    <div>
                        <p class="admin__eyebrow"><?= e(t('Panel de administración')) ?></p>
                        <h1 class="admin__title"><?= e(t($heading ?? $sections[$section]['label'] ?? 'Dashboard')) ?></h1>
                    </div>
                </div>
                <?php if ($viewer): ?>
                    <div class="admin__user">
                        <span class="chip chip--brand"><?= e(t(User::ROLE_LABELS[$viewer['role'] ?? 'user'] ?? 'Usuario')) ?></span>
                        <?= avatar($viewer, 'sm') ?>
                    </div>
                <?php endif; ?>
            </header>
            <main id="main" class="admin__content" tabindex="-1">
                <?php if ($isPreview): ?>
                    <div class="alert alert--info" role="status">
                        <?= icon('info') ?>
                        <p><strong><?= e(t('Vista previa.')) ?></strong> <?= e(t('En producción este panel solo es accesible para moderadores y administradores autenticados; la verificación de rol ocurre en el servidor.')) ?></p>
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
