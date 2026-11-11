<?php

use Trevix\Core\View;

/**
 * Lista paginada de publicaciones. También se devuelve sola (?partial=1) para "Cargar más".
 *
 * @var array       $posts
 * @var string|null $nextUrl
 * @var array|null  $viewer
 * @var string|null $endText Mensaje al llegar al final (null = sin mensaje).
 */
$endText ??= null;
?>
<?php foreach ($posts as $post): ?>
    <?php View::partial('post-card', ['post' => $post, 'viewer' => $viewer]); ?>
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
