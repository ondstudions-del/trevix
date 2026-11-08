<?php

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\View;
use Trevix\Services\Giphy;

/**
 * Comentario (o respuesta) en la página de una publicación.
 *
 * @var array      $comment
 * @var array      $post
 * @var array|null $viewer
 * @var bool       $canModerate Autor de la publicación: puede borrar cualquier comentario.
 * @var int        $page
 */
$isReply = !empty($comment['parent_id']);
$author = $comment['user'];
$commentId = (int) $comment['id'];
$canWrite = Auth::check() && $commentId > 0;
$canDelete = $canWrite && ($canModerate || (int) $comment['user_id'] === (int) ($viewer['id'] ?? 0));
$maxComment = (int) Config::get('app.limits.comment_body');
$gifs = Giphy::enabled();
?>
<div class="<?= cx('comment', ['comment--reply' => $isReply]) ?>" <?= $commentId > 0 ? 'id="comentario-' . $commentId . '"' : '' ?>>
    <a class="comment__avatar" href="<?= e(profile_url($author)) ?>" tabindex="-1" aria-hidden="true"><?= avatar($author, $isReply ? 'xs' : 'sm') ?></a>
    <div class="comment__content">
        <div class="comment__bubble">
            <div class="comment__byline">
                <a class="comment__author" href="<?= e(profile_url($author)) ?>"><?= e($author['display_name']) ?></a>
                <?= !empty($author['is_verified']) ? icon('badge-check', 'verified', 'Cuenta verificada') : '' ?>
                <span class="post__handle">@<?= e($author['username']) ?></span>
                <span class="post__dot" aria-hidden="true">·</span>
                <?= time_tag($comment['created_at']) ?>
            </div>
            <?php if ($comment['body'] !== ''): ?>
                <p class="comment__body"><?= format_post_body($comment['body']) ?></p>
            <?php endif; ?>
            <?php if (!empty($comment['gif'])): ?>
                <?php View::partial('gif', ['gif' => $comment['gif']]); ?>
            <?php endif; ?>
        </div>

        <?php if ($canWrite): ?>
            <div class="comment__actions">
                <details class="comment__reply-box">
                    <summary class="comment__action">Responder</summary>
                    <form class="comment-form comment-form--reply" method="post" action="<?= e(url('api/comments.php')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="post_id" value="<?= (int) $post['id'] ?>">
                        <input type="hidden" name="parent_id" value="<?= $commentId ?>">
                        <input type="hidden" name="page" value="<?= (int) $page ?>">
                        <label class="sr-only" for="reply-<?= $commentId ?>">Responder a @<?= e($author['username']) ?></label>
                        <textarea class="comment-form__input" id="reply-<?= $commentId ?>" name="body" rows="1" maxlength="<?= $maxComment ?>" required
                            data-autosize placeholder="Responde a @<?= e($author['username']) ?>"><?= $isReply ? '@' . e($author['username']) . ' ' : '' ?></textarea>
                        <?php View::partial('gif-field'); ?>
                        <?php if ($gifs): ?>
                            <button type="button" class="icon-btn icon-btn--sm js-only" data-gif-open aria-label="Añadir GIF o sticker" data-tooltip="GIF y stickers"><?= icon('sticker') ?></button>
                        <?php endif; ?>
                        <button type="submit" class="btn btn--primary btn--sm">Responder</button>
                    </form>
                </details>
                <?php if ($canDelete): ?>
                    <form method="post" action="<?= e(url('api/comments.php')) ?>" data-confirm="¿Eliminar este comentario<?= $isReply ? '' : ' y sus respuestas' ?>?" data-confirm-label="Eliminar">
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="delete">
                        <input type="hidden" name="comment_id" value="<?= $commentId ?>">
                        <button type="submit" class="comment__action comment__action--danger">Eliminar</button>
                    </form>
                <?php endif; ?>
                <?php if ((int) $comment['user_id'] !== (int) ($viewer['id'] ?? 0)): ?>
                    <a class="comment__action" href="<?= e(url('report.php', ['type' => 'comment', 'id' => $commentId])) ?>"
                        data-report="comment" data-report-id="<?= $commentId ?>" data-report-label="el comentario de @<?= e($author['username']) ?>">Reportar</a>
                <?php endif; ?>
            </div>
        <?php endif; ?>

        <?php if (!empty($comment['replies'])): ?>
            <div class="comment__replies">
                <?php foreach ($comment['replies'] as $reply): ?>
                    <?php View::partial('comment', [
                        'comment' => $reply, 'post' => $post, 'viewer' => $viewer, 'canModerate' => $canModerate, 'page' => $page,
                    ]); ?>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>
</div>
