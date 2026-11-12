<?php

use Trevix\Core\View;
use Trevix\Models\Ad;

/**
 * Tarjeta «Patrocinado» de OND-ADS en el feed. Los toques pasan por ads.php?go=ID, que los cuenta y lleva al destino.
 *
 * @var array      $ad     AdService::deliver(): campaign, post, community, group, sponsor
 * @var array|null $viewer
 */
$campaign = $ad['campaign'];
$adId = (int) $campaign['id'];
$go = url('ads.php', ['go' => $adId]);
$sponsor = $ad['sponsor'];

if ($campaign['kind'] === 'post' && $ad['post'] !== null) {
    View::partial('post-card', ['post' => $ad['post'], 'viewer' => $viewer, 'sponsoredId' => $adId]);
    return;
}
$external = $campaign['kind'] === 'custom';
$host = $external ? (string) preg_replace('/^www\./i', '', (string) parse_url((string) $campaign['link_url'], PHP_URL_HOST)) : '';
?>
<article class="post ad-card" data-ad-id="<?= $adId ?>" aria-label="<?= e(t('Anuncio de {name}', ['name' => $sponsor['display_name']])) ?>">
    <p class="post__context post__context--sponsored"><?= icon('megaphone') ?> <?= e(t('Patrocinado')) ?></p>
    <header class="post__header">
        <a class="post__avatar" href="<?= e(profile_url($sponsor)) ?>" tabindex="-1" aria-hidden="true"><?= avatar($sponsor, 'md') ?></a>
        <div class="post__meta">
            <div class="post__byline">
                <a class="post__author" href="<?= e(profile_url($sponsor)) ?>"><?= e($sponsor['display_name']) ?></a>
                <?= !empty($sponsor['is_verified']) ? icon('badge-check', 'verified', t('Cuenta verificada')) : '' ?>
                <span class="post__handle">@<?= e($sponsor['username']) ?></span>
            </div>
        </div>
    </header>

    <?php if ($campaign['kind'] === 'community' && $ad['community'] !== null): ?>
        <?php $c = $ad['community']; ?>
        <a class="ad-card__media ad-card__media--cover" href="<?= e($go) ?>">
            <img src="<?= e(community_cover($c)) ?>" alt="" loading="lazy">
        </a>
        <div class="ad-card__body">
            <div class="ad-card__title-row">
                <?= community_icon($c) ?>
                <div>
                    <p class="ad-card__title"><?= e($c['name']) ?></p>
                    <p class="ad-card__meta"><?= e(t('Comunidad')) ?> · <?= e(tn((int) $c['members_count'], '{n} miembro', '{n} miembros', ['n' => compact_number((int) $c['members_count'])])) ?></p>
                </div>
            </div>
            <?php if (!empty($c['description'])): ?><p class="ad-card__text"><?= e(mb_strimwidth((string) $c['description'], 0, 180, '…')) ?></p><?php endif; ?>
        </div>
        <footer class="ad-card__footer">
            <a class="btn btn--primary btn--sm" href="<?= e($go) ?>"><?= icon('users-round') ?> <?= e(t('Ver comunidad')) ?></a>
        </footer>

    <?php elseif ($campaign['kind'] === 'group' && $ad['group'] !== null): ?>
        <?php $g = $ad['group']; ?>
        <div class="ad-card__body">
            <div class="ad-card__title-row">
                <?= avatar(['avatar_path' => $g['avatar_path'], 'username' => $g['title'], 'display_name' => $g['title']], 'lg') ?>
                <div>
                    <p class="ad-card__title"><?= e($g['title']) ?></p>
                    <p class="ad-card__meta"><?= e(t('Grupo público')) ?> · <?= e(tn((int) $g['members_count'], '{n} miembro', '{n} miembros', ['n' => compact_number((int) $g['members_count'])])) ?></p>
                </div>
            </div>
            <?php if (!empty($g['description'])): ?><p class="ad-card__text"><?= e(mb_strimwidth((string) $g['description'], 0, 180, '…')) ?></p><?php endif; ?>
        </div>
        <footer class="ad-card__footer">
            <a class="btn btn--primary btn--sm" href="<?= e($go) ?>"><?= icon('users') ?> <?= e(!empty($g['is_member']) ? t('Abrir grupo') : t('Unirme al grupo')) ?></a>
        </footer>

    <?php else: ?>
        <div class="ad-card__body">
            <p class="ad-card__title"><?= e($campaign['title']) ?></p>
            <?php if (!empty($campaign['body'])): ?><p class="ad-card__text"><?= nl2br(e($campaign['body'])) ?></p><?php endif; ?>
        </div>
        <?php if (!empty($campaign['image_path'])): ?>
            <a class="ad-card__media" href="<?= e($go) ?>" target="_blank" rel="noopener sponsored">
                <img src="<?= e(url($campaign['image_path'])) ?>" alt="" loading="lazy">
            </a>
        <?php endif; ?>
        <footer class="ad-card__footer">
            <span class="ad-card__domain"><?= icon('external-link') ?> <?= e($host) ?></span>
            <a class="btn btn--primary btn--sm" href="<?= e($go) ?>" target="_blank" rel="noopener sponsored"><?= e(t(Ad::CTAS[$campaign['cta']] ?? 'Más información')) ?></a>
        </footer>
    <?php endif; ?>
</article>
