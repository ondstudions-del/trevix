<?php

use Trevix\Core\View;

/** @var array $community estructura de Community::present() */
$private = $community['visibility'] === 'private';
$role = ($community['membership']['status'] ?? '') === 'active' ? $community['membership']['role'] : null;
$cardUrl = community_url($community);
?>
<article class="community-card">
    <a class="community-card__cover" href="<?= e($cardUrl) ?>" tabindex="-1" aria-hidden="true">
        <img src="<?= e(community_cover($community)) ?>" alt="" loading="lazy">
    </a>
    <div class="community-card__body">
        <?= community_icon($community, 'lg') ?>
        <div class="community-card__badges">
            <span class="chip chip--muted"><?= $private ? icon('lock') . ' ' . e(t('Privada')) : icon('globe') . ' ' . e(t('Pública')) ?></span>
            <?php if ($community['category'] !== ''): ?>
                <span class="chip chip--muted"><?= e(t($community['category'])) ?></span>
            <?php endif; ?>
            <?php if ($role !== null && $role !== 'member'): ?>
                <span class="chip chip--brand"><?= e(t(\Trevix\Models\Community::ROLES[$role])) ?></span>
            <?php endif; ?>
        </div>
        <h2 class="community-card__name"><a href="<?= e($cardUrl) ?>"><?= e($community['name']) ?></a></h2>
        <?php if ($community['description'] !== ''): ?>
            <p class="community-card__desc"><?= e(mb_strimwidth($community['description'], 0, 140, '…')) ?></p>
        <?php else: ?>
            <p class="community-card__desc"></p>
        <?php endif; ?>
        <p class="community-card__meta">
            <span><?= icon('users') ?> <span data-community-members="<?= (int) $community['id'] ?>"><?= e(compact_number($community['members_count'])) ?></span>
                <span data-community-members-label="<?= (int) $community['id'] ?>"><?= plural((int) $community['members_count'], 'miembro', 'miembros') ?></span></span>
            <span><?= icon('file-text') ?> <?= e(compact_number($community['posts_count'])) ?> <?= plural((int) $community['posts_count'], 'publicación', 'publicaciones') ?></span>
        </p>
        <?php View::partial('community-join', ['community' => $community, 'block' => true]); ?>
    </div>
</article>
