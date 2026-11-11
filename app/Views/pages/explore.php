<?php

use Trevix\Core\View;

/**
 * @var string      $query
 * @var string      $tag
 * @var string      $filter
 * @var array       $filters
 * @var array       $people     resultados de búsqueda o, sin búsqueda, sugerencias con 'reason'
 * @var string|null $peopleNext
 * @var array       $trends
 * @var array       $communities
 * @var array       $media
 * @var array       $postList   ['posts' => [...], 'nextUrl' => ?string] publicaciones que coinciden con la búsqueda
 * @var array       $tagList    ['posts' => [...], 'nextUrl' => ?string] publicaciones con la etiqueta elegida
 * @var array       $featuredList ['posts' => [...], 'nextUrl' => ?string] destacadas por la administración
 * @var array|null  $tagInfo
 * @var array|null  $viewer
 * @var bool        $isPreview
 */
$show = static fn (string $section) => $filter === 'all' || $filter === $section;
$searchTerm = $tag !== '' ? '#' . $tag : $query;
$hasResults = $people || $trends || $communities || $media || $tagList['posts'] || $postList['posts'] || $featuredList['posts'];
$peopleTitle = $searchTerm === '' && !$isPreview ? t('Personas para seguir') : t('Personas');
?>
<header class="page-header">
    <h1 class="page-header__title page-header__title--visible"><?= e(t('Explorar')) ?></h1>
    <form class="search-field search-field--lg" action="<?= e(url('explore.php')) ?>" method="get" role="search">
        <?= icon('search') ?>
        <label class="sr-only" for="explore-q"><?= e(t('Buscar personas, publicaciones, hashtags o comunidades')) ?></label>
        <input id="explore-q" type="search" name="q" value="<?= e($query) ?>" placeholder="<?= e(t('Buscar personas, publicaciones, hashtags o comunidades')) ?>" maxlength="80" autocomplete="off">
        <?php if ($filter !== 'all' && $filter !== 'featured'): ?><input type="hidden" name="type" value="<?= e($filter) ?>"><?php endif; ?>
    </form>
    <nav class="chips" aria-label="<?= e(t('Filtrar resultados')) ?>">
        <?php foreach ($filters as $key => $label): ?>
            <a class="<?= cx('chip', ['is-active' => $filter === $key]) ?>"
                href="<?= e(url('explore.php', $key === 'featured' ? ['type' => $key] : ['q' => $query, 'tag' => $tag, 'type' => $key === 'all' ? null : $key])) ?>"
                <?= $filter === $key ? 'aria-current="page"' : '' ?>><?= e(t($label)) ?></a>
        <?php endforeach; ?>
    </nav>
    <?php if ($searchTerm !== ''): ?>
        <p class="explore__summary">
            <?= t('Resultados para {term}', ['term' => '<strong>' . e($searchTerm) . '</strong>']) ?>
            <a class="link-sm" href="<?= e(url('explore.php')) ?>"><?= e(t('Limpiar búsqueda')) ?></a>
        </p>
    <?php endif; ?>
</header>

<?php if (!$hasResults): ?>
    <?php View::partial('empty-state', [
        'icon' => 'search',
        'heading' => $searchTerm !== '' ? 'Sin resultados' : 'Nada que explorar todavía',
        'text' => $searchTerm !== '' ? 'Prueba con otra palabra o revisa la ortografía.' : 'El contenido popular aparecerá aquí cuando la comunidad empiece a publicar.',
    ]); ?>
<?php endif; ?>

<?php if ($featuredList['posts']): ?>
    <section class="explore-section explore-section--posts" aria-labelledby="ex-featured">
        <h2 class="section-title" id="ex-featured"><?= icon('star') ?> <?= e(t('Destacados')) ?></h2>
        <div class="feed">
            <?php View::partial('post-list', $featuredList + ['viewer' => $viewer, 'endText' => $filter === 'featured' ? 'Ya viste todas las publicaciones destacadas.' : null]); ?>
        </div>
        <?php if ($filter === 'all'): ?>
            <a class="link-sm explore-section__more" href="<?= e(url('explore.php', ['type' => 'featured'])) ?>"><?= e(t('Ver todas las destacadas')) ?></a>
        <?php endif; ?>
    </section>
<?php endif; ?>

<?php if ($tagList['posts']): ?>
    <section class="explore-section explore-section--posts" aria-labelledby="ex-tag-posts">
        <h2 class="section-title" id="ex-tag-posts">
            <?= icon('hash') ?> <?= e(t('Publicaciones con #{tag}', ['tag' => $tagInfo['tag'] ?? $tag])) ?>
            <?php if ($tagInfo): ?>
                <span class="section-title__meta"><?= e(t('{n} en total', ['n' => compact_number((int) $tagInfo['posts_count'])])) ?></span>
            <?php endif; ?>
        </h2>
        <div class="feed">
            <?php View::partial('post-list', $tagList + ['viewer' => $viewer, 'endText' => t('No hay más publicaciones con #{tag}.', ['tag' => $tag])]); ?>
        </div>
    </section>
<?php endif; ?>

<?php if ($people && $show('people')): ?>
    <section class="explore-section" aria-labelledby="ex-people">
        <h2 class="section-title" id="ex-people"><?= icon('users') ?> <?= e($peopleTitle) ?></h2>
        <ul class="people-grid">
            <?php foreach (array_slice($people, 0, $filter === 'people' ? 50 : 6) as $user): ?>
                <li class="person-card">
                    <a class="person-card__link" href="<?= e(profile_url($user)) ?>">
                        <?= avatar($user, 'lg') ?>
                        <span class="person-card__name">
                            <?= e($user['display_name']) ?>
                            <?= $user['is_verified'] ? icon('badge-check', 'verified', t('Cuenta verificada')) : '' ?>
                            <?= $user['is_private'] ? icon('lock', 'muted-icon', t('Cuenta privada')) : '' ?>
                        </span>
                        <span class="person-card__handle">@<?= e($user['username']) ?></span>
                        <?php if (!empty($user['reason'])): ?>
                            <span class="person-card__reason"><?= e($user['reason']) ?></span>
                        <?php elseif (!empty(relation_of($user)['follows_you'])): ?>
                            <span class="person-card__reason"><?= e(t('Te sigue')) ?></span>
                        <?php endif; ?>
                        <?php if ((string) ($user['bio'] ?? '') !== ''): ?>
                            <span class="person-card__bio"><?= e($user['bio']) ?></span>
                        <?php endif; ?>
                    </a>
                    <?php View::partial('follow-button', ['user' => $user, 'size' => 'sm', 'idle' => 'btn--light', 'compact' => true, 'block' => true]); ?>
                </li>
            <?php endforeach; ?>
        </ul>
        <?php if ($peopleNext): ?>
            <div class="load-more">
                <a class="btn btn--secondary" href="<?= e($peopleNext) ?>"><?= e($filter === 'people' ? t('Ver más personas') : t('Ver todas las personas')) ?></a>
            </div>
        <?php endif; ?>
    </section>
<?php endif; ?>

<?php if ($postList['posts'] && $show('posts')): ?>
    <section class="explore-section explore-section--posts" aria-labelledby="ex-posts">
        <h2 class="section-title" id="ex-posts"><?= icon('file-text') ?> <?= e(t('Publicaciones')) ?></h2>
        <div class="feed">
            <?php View::partial('post-list', $postList + ['viewer' => $viewer, 'endText' => 'No hay más publicaciones que coincidan.']); ?>
        </div>
    </section>
<?php endif; ?>

<?php if ($trends && $show('tags')): ?>
    <section class="explore-section" aria-labelledby="ex-trends">
        <h2 class="section-title" id="ex-trends"><?= icon('trending-up') ?> <?= e($searchTerm === '' ? t('Tendencias') : t('Hashtags')) ?></h2>
        <div class="trend-grid">
            <?php foreach ($trends as $i => $trend): ?>
                <a class="trend-card" href="<?= e(url('explore.php', ['tag' => $trend['tag']])) ?>">
                    <span class="trend-card__rank">#<?= $i + 1 ?></span>
                    <span class="trend-card__category"><?= e($trend['category']) ?></span>
                    <span class="trend-card__tag">#<?= e($trend['tag']) ?></span>
                    <span class="trend-card__count"><?= e(tn((int) $trend['posts_count'], '{n} publicación', '{n} publicaciones', ['n' => compact_number($trend['posts_count'])])) ?></span>
                </a>
            <?php endforeach; ?>
        </div>
    </section>
<?php endif; ?>

<?php if ($media && $show('all')): ?>
    <section class="explore-section" aria-labelledby="ex-media">
        <h2 class="section-title" id="ex-media"><?= icon('sparkles') ?> <?= e(t('Descubre')) ?></h2>
        <div class="media-grid" data-lightbox-group>
            <?php $index = 0; ?>
            <?php foreach ($media as $post): ?>
                <?php foreach ($post['media'] as $item): ?>
                    <?php if ($item['type'] !== 'image') { continue; } ?>
                    <button type="button" class="media-tile" data-lightbox-index="<?= $index++ ?>" aria-label="<?= e(t('Ver imagen de {name}', ['name' => $post['user']['display_name']])) ?>">
                        <img src="<?= e(url($item['src'])) ?>" alt="<?= e($item['alt'] ?? '') ?>" loading="lazy" decoding="async">
                        <span class="media-tile__overlay">
                            <span><?= icon('heart') ?> <?= e(compact_number($post['likes_count'])) ?></span>
                            <span><?= icon('message-circle') ?> <?= e(compact_number($post['comments_count'])) ?></span>
                        </span>
                    </button>
                <?php endforeach; ?>
            <?php endforeach; ?>
        </div>
    </section>
<?php endif; ?>

<?php if ($communities && $show('communities')): ?>
    <section class="explore-section" aria-labelledby="ex-communities">
        <h2 class="section-title" id="ex-communities"><?= icon('users-round') ?> <?= e(t('Comunidades')) ?></h2>
        <ul class="user-list user-list--cards">
            <?php foreach ($communities as $community): ?>
                <li class="user-row card">
                    <a class="user-row__link" href="<?= e(community_url($community)) ?>">
                        <?= community_icon($community) ?>
                        <span class="user-row__text">
                            <span class="user-row__name">
                                <?= e($community['name']) ?>
                                <?= $community['visibility'] === 'private' ? icon('lock', 'muted-icon', t('Comunidad privada')) : '' ?>
                            </span>
                            <span class="user-row__meta"><?= e(t($community['category'])) ?> · <?= e(compact_number($community['members_count'])) ?> <?= plural((int) $community['members_count'], 'miembro', 'miembros') ?></span>
                        </span>
                    </a>
                </li>
            <?php endforeach; ?>
        </ul>
        <?php if ($filter === 'all'): ?>
            <a class="link-sm explore-section__more" href="<?= e(url('explore.php', ['q' => $query, 'type' => 'communities'])) ?>"><?= e(t('Ver más comunidades')) ?></a>
        <?php endif; ?>
    </section>
<?php endif; ?>
