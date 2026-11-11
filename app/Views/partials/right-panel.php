<?php

use Trevix\Core\View;

/** @var array $aside */
$trends = $aside['trends'] ?? [];
$suggestions = $aside['suggestions'] ?? [];
$communities = $aside['communities'] ?? [];
?>
<aside class="aside" aria-label="<?= e(t('Descubre')) ?>">
    <div class="aside__inner">
        <form class="search-field" action="<?= e(url('explore.php')) ?>" method="get" role="search">
            <?= icon('search') ?>
            <label class="sr-only" for="aside-search"><?= e(t('Buscar en TREVIX')) ?></label>
            <input id="aside-search" type="search" name="q" placeholder="<?= e(t('Buscar en TREVIX')) ?>" maxlength="80" autocomplete="off">
        </form>

        <section class="card aside-card" aria-labelledby="aside-trends">
            <header class="aside-card__head">
                <h2 id="aside-trends"><?= icon('trending-up') ?> <?= e(t('Tendencias')) ?></h2>
            </header>
            <?php if ($trends): ?>
                <ol class="trend-list">
                    <?php foreach (array_slice($trends, 0, 5) as $i => $trend): ?>
                        <li>
                            <a class="trend" href="<?= e(url('explore.php', ['tag' => $trend['tag']])) ?>">
                                <span class="trend__rank"><?= $i + 1 ?></span>
                                <span class="trend__text">
                                    <span class="trend__category"><?= e(t((string) $trend['category'])) ?></span>
                                    <span class="trend__tag">#<?= e($trend['tag']) ?></span>
                                    <span class="trend__count"><?= e(tn((int) $trend['posts_count'], '{n} publicación', '{n} publicaciones', ['n' => compact_number($trend['posts_count'])])) ?></span>
                                </span>
                            </a>
                        </li>
                    <?php endforeach; ?>
                </ol>
                <a class="aside-card__more" href="<?= e(url('explore.php', ['type' => 'tags'])) ?>"><?= e(t('Ver todas las tendencias')) ?></a>
            <?php else: ?>
                <p class="aside-card__empty"><?= e(t('Las tendencias aparecerán cuando haya actividad en la plataforma.')) ?></p>
            <?php endif; ?>
        </section>

        <section class="card aside-card" aria-labelledby="aside-suggestions">
            <header class="aside-card__head">
                <h2 id="aside-suggestions"><?= icon('user-plus') ?> <?= e(t('Sugerencias para ti')) ?></h2>
            </header>
            <?php if ($suggestions): ?>
                <ul class="user-list">
                    <?php foreach ($suggestions as $user): ?>
                        <li class="user-row">
                            <a class="user-row__link" href="<?= e(profile_url($user)) ?>">
                                <?= avatar($user, 'md') ?>
                                <span class="user-row__text">
                                    <span class="user-row__name">
                                        <?= e($user['display_name']) ?>
                                        <?= $user['is_verified'] ? icon('badge-check', 'verified', t('Cuenta verificada')) : '' ?>
                                    </span>
                                    <span class="user-row__meta"><?= e(isset($user['reason']) ? t((string) $user['reason']) : '@' . $user['username']) ?></span>
                                </span>
                            </a>
                            <?php View::partial('follow-button', ['user' => $user, 'size' => 'sm', 'idle' => 'btn--light', 'compact' => true]); ?>
                        </li>
                    <?php endforeach; ?>
                </ul>
                <a class="aside-card__more" href="<?= e(url('explore.php', ['type' => 'people'])) ?>"><?= e(t('Ver más personas')) ?></a>
            <?php else: ?>
                <p class="aside-card__empty"><?= e(t('Te recomendaremos personas según tus intereses y conexiones.')) ?></p>
            <?php endif; ?>
        </section>

        <?php if ($communities): ?>
            <section class="card aside-card" aria-labelledby="aside-communities">
                <header class="aside-card__head">
                    <h2 id="aside-communities"><?= icon('users-round') ?> <?= e(t('Comunidades')) ?></h2>
                </header>
                <ul class="user-list">
                    <?php foreach ($communities as $community): ?>
                        <li class="user-row">
                            <a class="user-row__link" href="<?= e(community_url($community)) ?>">
                                <?= community_icon($community) ?>
                                <span class="user-row__text">
                                    <span class="user-row__name"><?= e($community['name']) ?></span>
                                    <span class="user-row__meta"><?= e(compact_number($community['members_count'])) ?> <?= plural((int) $community['members_count'], 'miembro', 'miembros') ?></span>
                                </span>
                            </a>
                        </li>
                    <?php endforeach; ?>
                </ul>
                <a class="aside-card__more" href="<?= e(url('communities.php')) ?>"><?= e(t('Explorar comunidades')) ?></a>
            </section>
        <?php endif; ?>

        <footer class="aside-footer">
            <nav aria-label="<?= e(t('Enlaces legales')) ?>">
                <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>"><?= e(t('Términos')) ?></a>
                <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>"><?= e(t('Privacidad')) ?></a>
                <a href="<?= e(url('legal.php', ['doc' => 'cookies'])) ?>"><?= e(t('Cookies')) ?></a>
            </nav>
            <p>© <?= date('Y') ?> TREVIX</p>
            <?php \Trevix\Core\View::partial('lang-switch'); ?>
        </footer>
    </div>
</aside>
