<?php

use Trevix\Core\View;

/**
 * Lista paginada de publicaciones. También se devuelve sola (?partial=1) para "Cargar más".
 *
 * @var array       $posts
 * @var string|null $nextUrl
 * @var array|null  $viewer
 * @var string|null $endText   Mensaje al llegar al final (null = sin mensaje).
 * @var bool        $suggested Primera página de «Sugerencias para ti» (el feed siguió tras terminarse la pestaña).
 * @var array|null  $ad        Anuncio de OND-ADS para esta página (AdService::deliver), va tras la 3.ª publicación.
 */
$endText ??= null;
$suggested ??= false;
$ad ??= null;
$adAfter = min(3, count($posts));
?>
<?php if ($suggested && $posts !== []): ?>
    <div class="feed-divider">
        <span class="feed-divider__icon"><?= icon('sparkles') ?></span>
        <p><strong><?= e(t('Sugerencias para ti')) ?></strong> <?= e(t('Ya viste todo lo de esta pestaña. Seguimos con más publicaciones de TREVIX.')) ?></p>
    </div>
<?php endif; ?>
<?php foreach ($posts as $i => $post): ?>
    <?php View::partial('post-card', ['post' => $post, 'viewer' => $viewer]); ?>
    <?php if ($ad !== null && $i + 1 === $adAfter): ?>
        <?php View::partial('ad-card', ['ad' => $ad, 'viewer' => $viewer]); ?>
    <?php endif; ?>
<?php endforeach; ?>
<?php if (!empty($nextUrl)): ?>
    <div class="load-more" data-load-more>
        <a class="btn btn--secondary" href="<?= e($nextUrl) ?>"><?= e(t('Cargar más publicaciones')) ?></a>
    </div>
<?php elseif ($endText !== null && $posts !== []): ?>
    <div class="feed-end">
        <span class="feed-end__icon"><?= icon('circle-check') ?></span>
        <p><strong><?= e(t('Estás al día')) ?></strong> <?= e(t($endText)) ?></p>
    </div>
<?php endif; ?>
