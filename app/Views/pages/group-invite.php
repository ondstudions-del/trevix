<?php

use Trevix\Core\Auth;

/**
 * Invitación a un grupo de mensajes (g.php?c=CÓDIGO).
 *
 * @var string $code
 * @var array  $group
 * @var int    $members
 * @var string $state  none | requested | member
 */
$public = ($group['visibility'] ?? 'private') === 'public';
$face = ['display_name' => $group['title'], 'username' => 'g' . $group['id'], 'avatar_path' => $group['avatar_path'] ?? null];
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('messages.php')) ?>" aria-label="<?= e(t('Volver')) ?>"><?= icon('arrow-left') ?></a>
        <h1 class="page-header__title page-header__title--visible"><?= e(t('Invitación a un grupo')) ?></h1>
    </div>
</header>

<section class="card group-invite">
    <?php if (!empty($group['cover_path'])): ?>
        <img class="group-invite__cover" src="<?= e(url($group['cover_path'])) ?>" alt="" decoding="async">
    <?php else: ?>
        <div class="group-invite__cover group-invite__cover--empty" aria-hidden="true"></div>
    <?php endif; ?>
    <div class="group-invite__body">
        <?= avatar($face, 'xl', 'group-invite__avatar') ?>
        <h2 class="group-invite__title"><?= e($group['title']) ?></h2>
        <p class="group-invite__meta">
            <?= icon($public ? 'users' : 'lock') ?>
            <?= e($public ? t('Grupo público') : t('Grupo privado')) ?> · <?= e(compact_number($members)) ?> <?= plural($members, 'participante', 'participantes') ?>
        </p>
        <?php if (!empty($group['description'])): ?>
            <p class="group-invite__description"><?= nl2br(e($group['description'])) ?></p>
        <?php endif; ?>
        <?php if (!empty($group['e2ee'])): ?>
            <p class="group-invite__note"><?= icon('lock') ?> <?= e(t('Los mensajes de este grupo están cifrados de extremo a extremo: se leen en la app TREVIX.')) ?></p>
        <?php endif; ?>

        <div class="group-invite__actions">
            <?php if (!Auth::check()): ?>
                <a class="btn btn--primary" href="<?= e(url('login.php')) ?>"><?= icon('log-in') ?> <?= e(t('Inicia sesión para unirte')) ?></a>
            <?php elseif ($state === 'member'): ?>
                <a class="btn btn--primary" href="<?= e(url('messages.php', ['c' => $group['id']])) ?>"><?= icon('message-circle') ?> <?= e(t('Abrir el grupo')) ?></a>
            <?php elseif ($state === 'requested'): ?>
                <p class="group-invite__note"><?= icon('clock') ?> <?= e(t('Ya pediste unirte. Un administrador debe aceptarte.')) ?></p>
            <?php else: ?>
                <form method="post" action="<?= e(url('g.php', ['c' => $code])) ?>">
                    <?= csrf_field() ?>
                    <button type="submit" class="btn btn--primary"><?= icon('user-plus') ?> <?= e($public ? t('Unirme al grupo') : t('Pedir unirme')) ?></button>
                </form>
            <?php endif; ?>
            <a class="btn btn--ghost" href="<?= e('trevix://open/g.php?c=' . rawurlencode($code)) ?>"
               data-android-href="<?= e('intent://open/g.php?c=' . rawurlencode($code) . '#Intent;scheme=trevix;package=com.ondsc.trevix;S.browser_fallback_url='
                   . rawurlencode(absolute_url('g.php?c=' . rawurlencode($code))) . ';end') ?>"><?= icon('smartphone') ?> <?= e(t('Abrir en la app')) ?></a>
        </div>
    </div>
</section>
