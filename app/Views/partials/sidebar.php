<?php

use Trevix\Core\Auth;
use Trevix\Core\View;
use Trevix\Models\User;

/**
 * @var array|null $viewer
 * @var string     $activeNav
 * @var bool       $isPreview
 */
$viewer = $viewer ?? [];
$activeNav = $activeNav ?? '';
$unreadNotifications = (int) ($viewer['unread_notifications'] ?? 0) + (int) ($viewer['pending_requests'] ?? 0);
$unreadMessages = (int) ($viewer['unread_messages'] ?? 0);

$items = [
    'home'          => ['Inicio', 'house', url('feed.php'), 0],
    'explore'       => ['Explorar', 'compass', url('explore.php'), 0],
    'music'         => ['Música', 'music', url('music.php'), 0],
    'communities'   => ['Comunidades', 'users-round', url('communities.php'), 0],
    'events'        => ['Eventos', 'calendar', url('events.php'), 0],
    'messages'      => ['Mensajes', 'send', url('messages.php'), $unreadMessages],
    'notifications' => ['Notificaciones', 'bell', url('notifications.php'), $unreadNotifications],
    'profile'       => ['Perfil', 'circle-user', $viewer ? profile_url($viewer) : url('profile.php'), 0],
    'settings'      => ['Configuración', 'settings', url('settings.php'), 0],
];
if (User::isMusicArtist($viewer)) {
    $items = array_slice($items, 0, 3, true) + ['artist' => ['Artista', 'mic-vocal', url('artist.php'), 0]] + array_slice($items, 3, null, true);
}
$canModerate = $viewer && Auth::hasRole('moderator', $viewer);
?>
<aside class="sidebar" aria-label="Navegación principal">
    <a class="sidebar__brand" href="<?= e(url('feed.php')) ?>" aria-label="TREVIX, ir al inicio">
        <?php View::partial('logo', ['size' => 38, 'wordmark' => true]); ?>
    </a>

    <nav class="sidebar__nav">
        <ul>
            <?php foreach ($items as $key => [$label, $iconName, $href, $badge]): ?>
                <?php $active = $activeNav === $key; ?>
                <li>
                    <a class="<?= cx('nav-link', ['is-active' => $active]) ?>" href="<?= e($href) ?>"
                        <?= $active ? 'aria-current="page"' : '' ?> data-label="<?= e($label) ?>">
                        <span class="nav-link__icon"<?= in_array($key, ['messages', 'notifications'], true) ? ' data-badge="' . $key . '"' : '' ?>>
                            <?= icon($iconName) ?>
                            <?php if ($badge > 0): ?>
                                <span class="badge-count" aria-label="<?= $badge ?> sin leer"><?= $badge > 99 ? '99+' : $badge ?></span>
                            <?php endif; ?>
                        </span>
                        <span class="nav-link__label"><?= e($label) ?></span>
                    </a>
                </li>
            <?php endforeach; ?>
            <?php if ($canModerate): ?>
                <li>
                    <a class="nav-link nav-link--admin" href="<?= e(url('admin/')) ?>" data-label="Administración">
                        <span class="nav-link__icon"><?= icon('shield') ?></span>
                        <span class="nav-link__label">Administración</span>
                    </a>
                </li>
            <?php endif; ?>
        </ul>
    </nav>

    <button type="button" class="btn btn--primary sidebar__create" data-open-composer>
        <?= icon('plus') ?>
        <span class="sidebar__create-label">Crear publicación</span>
    </button>

    <?php if ($viewer): ?>
        <div class="sidebar__account dropdown" data-dropdown>
            <button type="button" class="account-chip" data-dropdown-trigger aria-haspopup="menu" aria-expanded="false">
                <?= avatar($viewer, 'sm') ?>
                <span class="account-chip__text">
                    <span class="account-chip__name"><?= e($viewer['display_name']) ?></span>
                    <span class="account-chip__handle">@<?= e($viewer['username']) ?></span>
                </span>
                <?= icon('ellipsis', 'account-chip__more') ?>
            </button>
            <div class="dropdown__menu dropdown__menu--up" role="menu" hidden>
                <a class="dropdown__item" role="menuitem" href="<?= e(profile_url($viewer)) ?>"><?= icon('user') ?> Ver perfil</a>
                <a class="dropdown__item" role="menuitem" href="<?= e(url('settings.php')) ?>"><?= icon('settings') ?> Configuración</a>
                <div class="dropdown__divider" role="separator"></div>
                <?php if (Auth::check()): ?>
                    <form method="post" action="<?= e(url('logout.php')) ?>">
                        <?= csrf_field() ?>
                        <button type="submit" class="dropdown__item dropdown__item--danger" role="menuitem"><?= icon('log-out') ?> Cerrar sesión</button>
                    </form>
                <?php else: ?>
                    <a class="dropdown__item" role="menuitem" href="<?= e(url('login.php')) ?>"><?= icon('log-in') ?> Iniciar sesión</a>
                <?php endif; ?>
            </div>
        </div>
    <?php endif; ?>
</aside>
