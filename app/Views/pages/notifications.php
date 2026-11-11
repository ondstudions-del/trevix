<?php

use Trevix\Core\Auth;
use Trevix\Core\View;

/**
 * @var string      $filter
 * @var array       $filters
 * @var array       $groups
 * @var string|null $nextUrl
 * @var int         $unread
 */
$typeIcons = [
    'like'            => 'heart',
    'comment'         => 'message-circle',
    'reply'           => 'message-circle',
    'mention'         => 'at-sign',
    'share'           => 'repeat-2',
    'follow'          => 'user-plus',
    'follow_accepted' => 'user-check',
    'follow_request'  => 'user-round-plus',
    'community_request'  => 'users',
    'community_accepted' => 'users',
    'song_approved'   => 'music',
    'song_rejected'   => 'music',
    'song_removed'    => 'music',
    'warning'         => 'triangle-alert',
    'verification_approved' => 'badge-check',
    'verification_rejected' => 'badge-check',
    'appeal_accepted' => 'circle-check',
    'appeal_rejected' => 'scale',
    'subscription'    => 'crown',
    'topup_approved'  => 'wallet',
    'topup_rejected'  => 'wallet',
    'withdrawal_paid' => 'banknote',
    'withdrawal_rejected' => 'banknote',
    'wallet_adjusted' => 'wallet',
    'collaborator_enabled' => 'crown',
    'gift'            => 'gift',
    'new_post'        => 'bell-ring',
    'new_note'        => 'file-text',
    'new_story'       => 'circle-dashed',
];
?>
<header class="page-header page-header--sticky">
    <div class="page-header__row page-header__row--between">
        <h1 class="page-header__title page-header__title--visible"><?= e(t('Notificaciones')) ?></h1>
        <?php if (!Auth::check()): ?>
            <button type="button" class="btn btn--ghost btn--sm" disabled data-tooltip="<?= e(t('Inicia sesión para gestionar tus notificaciones')) ?>"><?= icon('check-check') ?> <?= e(t('Marcar todo como leído')) ?></button>
        <?php elseif ($unread > 0): ?>
            <form method="post" action="<?= e(url('api/notifications.php')) ?>" data-read-all>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="read_all">
                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('check-check') ?> <?= e(t('Marcar todo como leído')) ?></button>
            </form>
        <?php endif; ?>
    </div>
    <nav class="tabs" aria-label="<?= e(t('Filtrar notificaciones')) ?>">
        <?php foreach ($filters as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $filter === $key]) ?>" href="<?= e(url('notifications.php', ['filter' => $key === 'all' ? null : $key])) ?>"
                <?= $filter === $key ? 'aria-current="page"' : '' ?>><?= e(t($label)) ?></a>
        <?php endforeach; ?>
    </nav>
</header>

<?php if ($groups === []): ?>
    <?php View::partial('empty-state', $filter === 'requests' ? [
        'icon' => 'user-round-plus', 'heading' => 'No tienes solicitudes pendientes',
        'text' => 'Si tu cuenta es privada, aquí aparecerán las personas que quieran seguirte.',
    ] : [
        'icon' => 'bell-off', 'heading' => 'No hay notificaciones',
        'text' => 'Cuando alguien te siga, reaccione o te mencione, lo verás aquí.',
    ]); ?>
<?php endif; ?>

<?php foreach ($groups as $label => $items): ?>
    <section class="notif-group" aria-label="<?= e(t($label)) ?>">
        <h2 class="notif-group__title"><?= e(t($label)) ?></h2>
        <ul class="notif-list">
            <?php foreach ($items as $n): ?>
                <?php
                $actor = $n['actor'] ?? ['username' => '', 'display_name' => 'TREVIX', 'avatar_path' => null];
                $actorUrl = ($n['actor'] ?? null) !== null ? profile_url($actor) : ($n['url'] ?? url('notifications.php'));
                ?>
                <li class="<?= cx('notif', ['is-unread' => !$n['read']]) ?>" data-notif>
                    <?php if (!empty($n['url'])): ?>
                        <a class="notif__open" href="<?= e($n['url']) ?>" aria-label="<?= e(t('Abrir: {text}', ['text' => $actor['display_name'] . ' ' . $n['text']])) ?>"></a>
                    <?php endif; ?>
                    <a class="notif__avatar" href="<?= e($actorUrl) ?>" tabindex="-1" aria-hidden="true">
                        <?= avatar($actor, 'md') ?>
                        <span class="notif__type notif__type--<?= e($n['type']) ?>"><?= icon($typeIcons[$n['type']] ?? 'bell') ?></span>
                    </a>
                    <div class="notif__body">
                        <p class="notif__text">
                            <a href="<?= e($actorUrl) ?>"><?= e($actor['display_name']) ?></a>
                            <?= e($n['text']) ?>
                            <span class="notif__time"><?= time_tag($n['created_at']) ?></span>
                        </p>
                        <?php if (!empty($n['excerpt'])): ?>
                            <p class="notif__excerpt"><?= e($n['excerpt']) ?></p>
                        <?php endif; ?>
                        <?php if ($n['type'] === 'follow_request'): ?>
                            <div class="notif__actions" data-request-actions>
                                <?php if (Auth::check()): ?>
                                    <?php foreach (['accept' => [t('Aceptar'), 'btn--primary'], 'reject' => [t('Rechazar'), 'btn--secondary']] as $action => [$label, $class]): ?>
                                        <form method="post" action="<?= e(url('api/follows.php')) ?>" data-request-form>
                                            <?= csrf_field() ?>
                                            <input type="hidden" name="action" value="<?= $action ?>">
                                            <input type="hidden" name="user_id" value="<?= (int) $actor['id'] ?>">
                                            <button type="submit" class="<?= cx('btn', 'btn--sm', $class) ?>"><?= e($label) ?></button>
                                        </form>
                                    <?php endforeach; ?>
                                <?php else: ?>
                                    <button type="button" class="btn btn--primary btn--sm" disabled data-tooltip="<?= e(t('Inicia sesión para responder')) ?>"><?= e(t('Aceptar')) ?></button>
                                    <button type="button" class="btn btn--secondary btn--sm" disabled data-tooltip="<?= e(t('Inicia sesión para responder')) ?>"><?= e(t('Rechazar')) ?></button>
                                <?php endif; ?>
                            </div>
                        <?php endif; ?>
                    </div>
                    <?php if (!empty($n['thumb'])): ?>
                        <img class="notif__thumb" src="<?= e(url($n['thumb'])) ?>" alt="" loading="lazy">
                    <?php elseif ($n['type'] === 'follow'): ?>
                        <?php View::partial('follow-button', ['user' => $actor, 'size' => 'sm', 'idle' => 'btn--light', 'compact' => true]); ?>
                    <?php endif; ?>
                    <?php if (!$n['read']): ?>
                        <span class="notif__dot" aria-label="<?= e(t('Sin leer')) ?>"></span>
                    <?php endif; ?>
                </li>
            <?php endforeach; ?>
        </ul>
    </section>
<?php endforeach; ?>

<?php if (!empty($nextUrl)): ?>
    <div class="load-more">
        <a class="btn btn--secondary" href="<?= e($nextUrl) ?>"><?= e($filter === 'requests' ? t('Ver más solicitudes') : t('Ver notificaciones anteriores')) ?></a>
    </div>
<?php endif; ?>
