<?php

use Trevix\Core\View;

/**
 * @var string     $feed
 * @var array      $feeds
 * @var array      $list    ['posts' => [...], 'nextUrl' => ?string]
 * @var string     $endText
 * @var array      $stories
 * @var array|null $viewer
 * @var bool       $isPreview
 */
$emptyMessages = [
    'foryou'    => ['sparkles', 'Tu feed está listo para empezar', 'Crea la primera publicación o explora TREVIX para descubrir contenido.'],
    'following' => ['users', 'Aún no sigues a nadie', 'Cuando sigas a otras personas, sus publicaciones aparecerán en esta pestaña.'],
    'friends'   => ['heart', 'Sin publicaciones de amigos', 'Tus amigos son las personas que te siguen y a las que sigues.'],
    'trending'  => ['trending-up', 'Nada en tendencia por ahora', 'Las publicaciones más populares del momento aparecerán aquí.'],
];
?>
<header class="page-header page-header--sticky">
    <h1 class="page-header__title"><?= e(t('Inicio')) ?></h1>
    <nav class="tabs" aria-label="<?= e(t('Tipo de feed')) ?>">
        <?php foreach ($feeds as $key => $label): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $feed === $key]) ?>" href="<?= e(url('feed.php', ['feed' => $key === 'foryou' ? null : $key])) ?>"
                <?= $feed === $key ? 'aria-current="page"' : '' ?>><?= e(t($label)) ?></a>
        <?php endforeach; ?>
    </nav>
</header>

<?php if ($stories || $viewer): ?>
    <?php View::partial('stories-bar', ['stories' => $stories, 'viewer' => $viewer]); ?>
<?php endif; ?>

<?php View::partial('composer-inline', ['viewer' => $viewer]); ?>

<?php if (!$isPreview && $viewer !== null): ?>
    <div class="feed-pull" data-feed-pull aria-hidden="true"><?= icon('refresh-cw') ?></div>
    <button type="button" class="feed-new-pill" data-feed-new hidden><?= icon('arrow-up') ?> <span data-feed-new-label></span></button>
<?php endif; ?>
<section class="feed" aria-label="<?= e(t('Publicaciones · {feed}', ['feed' => t($feeds[$feed])])) ?>"
    <?= in_array($feed, ['foryou', 'following'], true) ? 'data-feed-live="post thread"' : '' ?>
    <?= !$isPreview && $viewer !== null ? 'data-feed-refresh="' . e(url('feed.php', ['feed' => $feed === 'foryou' ? null : $feed])) . '"' . ($feed === 'trending' ? ' data-feed-no-count' : '') : '' ?>>
    <?php if ($list['posts'] === []): ?>
        <?php [$emptyIcon, $emptyTitle, $emptyText] = $emptyMessages[$feed]; ?>
        <?php View::partial('empty-state', [
            'icon' => $emptyIcon, 'heading' => $emptyTitle, 'text' => $emptyText,
            'actionHref' => url('explore.php'), 'actionLabel' => 'Explorar TREVIX',
        ]); ?>
        <?php if (!empty($list['nextUrl'])): ?>
            <?php View::partial('post-list', $list + ['viewer' => $viewer, 'endText' => $endText]); ?>
        <?php endif; ?>
    <?php else: ?>
        <?php View::partial('post-list', $list + ['viewer' => $viewer, 'endText' => $endText]); ?>
    <?php endif; ?>
</section>
<?php if (!$isPreview && $viewer !== null): ?><script src="<?= e(asset('js/feed-refresh.js')) ?>" defer></script><?php endif; ?>
