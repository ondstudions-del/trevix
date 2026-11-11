<?php

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\View;
use Trevix\Services\Giphy;

/**
 * Publicación individual con comentarios paginados (del más antiguo al más reciente).
 *
 * @var array      $post
 * @var array      $comments
 * @var int        $page
 * @var bool       $hasMore
 * @var bool       $canModerate
 * @var array|null $viewer
 */
$postId = (int) $post['id'];
$maxComment = (int) Config::get('app.limits.comment_body');
$commentCount = (int) $post['comments_count'];
?>
<header class="page-header page-header--sticky">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('feed.php')) ?>" aria-label="<?= e(t('Volver al inicio')) ?>"><?= icon('arrow-left') ?></a>
        <h1 class="page-header__title page-header__title--visible"><?= e(t('Publicación')) ?></h1>
    </div>
</header>

<div class="feed feed--single">
    <?php View::partial('post-card', ['post' => $post, 'viewer' => $viewer]); ?>
</div>

<section class="comments" id="comentarios" aria-labelledby="comments-title">
    <h2 class="comments__title" id="comments-title">
        <?= e(t('Comentarios')) ?> <span class="comments__count"><?= e(compact_number($commentCount)) ?></span>
    </h2>

    <?php if (Auth::check()): ?>
        <form class="comment-form" method="post" action="<?= e(url('api/comments.php')) ?>">
            <?= csrf_field() ?>
            <input type="hidden" name="post_id" value="<?= $postId ?>">
            <?= avatar($viewer, 'sm') ?>
            <div class="comment-form__main">
                <label class="sr-only" for="comment-body"><?= e(t('Escribe un comentario')) ?></label>
                <textarea class="comment-form__input" id="comment-body" name="body" rows="2" maxlength="<?= $maxComment ?>" required
                    data-autosize data-char-count="#comment-count" placeholder="<?= e(t('Escribe un comentario…')) ?>"></textarea>
                <?php View::partial('gif-field'); ?>
                <div class="comment-form__footer">
                    <span class="comment-form__count" id="comment-count">0 / <?= $maxComment ?></span>
                    <?php if (Giphy::enabled()): ?>
                        <button type="button" class="btn btn--ghost btn--sm js-only" data-gif-open aria-label="<?= e(t('Añadir GIF o sticker')) ?>"><?= icon('sticker') ?> GIF</button>
                    <?php endif; ?>
                    <button type="submit" class="btn btn--primary btn--sm"><?= icon('send') ?> <?= e(t('Comentar')) ?></button>
                </div>
            </div>
        </form>
    <?php else: ?>
        <p class="comments__login"><a href="<?= e(url('login.php')) ?>"><?= e(t('Inicia sesión')) ?></a> <?= e(t('para comentar.')) ?></p>
    <?php endif; ?>

    <?php if ($page > 1): ?>
        <a class="comments__more" href="<?= e(url('post.php', ['id' => $postId, 'page' => $page - 1 > 1 ? $page - 1 : null])) ?>#comentarios">
            <?= e(t('Ver comentarios anteriores')) ?>
        </a>
    <?php endif; ?>

    <?php if ($comments === []): ?>
        <p class="comments__empty"><?= e($page > 1 ? t('No hay más comentarios.') : t('Todavía no hay comentarios. ¡Escribe el primero!')) ?></p>
    <?php else: ?>
        <div class="comments__list">
            <?php foreach ($comments as $comment): ?>
                <?php View::partial('comment', [
                    'comment' => $comment, 'post' => $post, 'viewer' => $viewer, 'canModerate' => $canModerate, 'page' => $page,
                ]); ?>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>

    <?php if ($hasMore): ?>
        <a class="comments__more" href="<?= e(url('post.php', ['id' => $postId, 'page' => $page + 1])) ?>#comentarios"><?= e(t('Ver más comentarios')) ?></a>
    <?php endif; ?>
</section>
