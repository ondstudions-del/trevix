<?php
/**
 * @var array|null $viewer
 * @var string     $activeNav
 */
$activeNav = $activeNav ?? '';
$unread = (int) ($viewer['unread_notifications'] ?? 0) + (int) ($viewer['pending_requests'] ?? 0);
$link = static function (string $key, string $label, string $iconName, string $href) use ($activeNav, $unread): string {
    $active = $activeNav === $key;
    $isNotifications = $key === 'notifications';
    $badge = $isNotifications && $unread > 0 ? '<span class="badge-count">' . ($unread > 99 ? '99+' : $unread) . '</span>' : '';
    return '<a class="' . cx('mobile-nav__item', ['is-active' => $active]) . '" href="' . e($href) . '"'
        . ($active ? ' aria-current="page"' : '') . '><span class="mobile-nav__icon"' . ($isNotifications ? ' data-badge="notifications"' : '') . '>'
        . icon($iconName) . $badge . '</span>'
        . '<span class="mobile-nav__label">' . e($label) . '</span></a>';
};
?>
<nav class="mobile-nav" aria-label="<?= e(t('Navegación móvil')) ?>">
    <?= $link('home', t('Inicio'), 'house', url('feed.php')) ?>
    <?= $link('explore', t('Explorar'), 'compass', url('explore.php')) ?>
    <button type="button" class="mobile-nav__create" data-open-composer aria-label="<?= e(t('Crear publicación')) ?>">
        <?= icon('plus') ?>
    </button>
    <?= $link('notifications', t('Avisos'), 'bell', url('notifications.php')) ?>
    <?= $link('profile', t('Perfil'), 'circle-user', $viewer ? profile_url($viewer) : url('profile.php')) ?>
</nav>
