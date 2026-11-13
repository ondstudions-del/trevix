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
                <?= !empty($author['is_verified']) ? icon('badge-check', 'verified', t('Cuenta verificada')) : '' ?>
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
                <?php
                $reaction = $comment['viewer_reaction'] ?? null;
                foreach (['like' => ['thumbs-up', 'likes_count', t('Me gusta')], 'dislike' => ['thumbs-down', 'dislikes_count', t('No me gusta')]] as $value => [$reactIcon, $countKey, $reactLabel]):
                    $on = $reaction === $value;
                ?>
                    <form method="post" action="<?= e(url('api/comments.php')) ?>" class="comment__react-form" data-comment-react>
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="react">
                        <input type="hidden" name="comment_id" value="<?= $commentId ?>">
                        <input type="hidden" name="value" value="<?= $on ? 'none' : $value ?>" data-react-value="<?= $value ?>">
                        <button type="submit" class="<?= cx('comment__action comment__react', ['is-active' => $on]) ?>" aria-pressed="<?= $on ? 'true' : 'false' ?>"
                            aria-label="<?= e($reactLabel) ?>" data-tooltip="<?= e($reactLabel) ?>">
                            <?= icon($reactIcon) ?><span data-react-count="<?= $value ?>"><?= (int) ($comment[$countKey] ?? 0) ?: '' ?></span>
                        </button>
                    </form>
                <?php endforeach; ?>
                <details class="comment__reply-box">
                    <summary class="comment__action"><?= e(t('Responder')) ?></summary>
                    <form class="comment-form comment-form--reply" method="post" action="<?= e(url('api/comments.php')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="post_id" value="<?= (int) $post['id'] ?>">
                        <input type="hidden" name="parent_id" value="<?= $commentId ?>">
                        <input type="hidden" name="page" value="<?= (int) $page ?>">
                        <label class="sr-only" for="reply-<?= $commentId ?>"><?= e(t('Responder a @{username}', ['username' => $author['username']])) ?></label>
                        <textarea class="comment-form__input" id="reply-<?= $commentId ?>" name="body" rows="1" maxlength="<?= $maxComment ?>" required
                            data-autosize data-mention-input placeholder="<?= e(t('Responde a @{username}', ['username' => $author['username']])) ?>"><?= $isReply ? '@' . e($author['username']) . ' ' : '' ?></textarea>
                        <?php View::partial('gif-field'); ?>
                        <?php if ($gifs): ?>
                            <button type="button" class="icon-btn icon-btn--sm js-only" data-gif-open aria-label="<?= e(t('Añadir GIF o sticker')) ?>" data-tooltip="<?= e(t('GIF y stickers')) ?>"><?= icon('sticker') ?></button>
                        <?php endif; ?>
                        <button type="submit" class="btn btn--primary btn--sm"><?= e(t('Responder')) ?></button>
                    </form>
                </details>
                <?php if ($canDelete): ?>
                    <form method="post" action="<?= e(url('api/comments.php')) ?>" data-confirm="<?= e($isReply ? t('¿Eliminar este comentario?') : t('¿Eliminar este comentario y sus respuestas?')) ?>" data-confirm-label="<?= e(t('Eliminar')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="action" value="delete">
                        <input type="hidden" name="comment_id" value="<?= $commentId ?>">
                        <button type="submit" class="comment__action comment__action--danger"><?= e(t('Eliminar')) ?></button>
                    </form>
                <?php endif; ?>
                <?php if ((int) $comment['user_id'] !== (int) ($viewer['id'] ?? 0)): ?>
                    <a class="comment__action" href="<?= e(url('report.php', ['type' => 'comment', 'id' => $commentId])) ?>"
                        data-report="comment" data-report-id="<?= $commentId ?>" data-report-label="<?= e(t('el comentario de @{username}', ['username' => $author['username']])) ?>"><?= e(t('Reportar')) ?></a>
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
