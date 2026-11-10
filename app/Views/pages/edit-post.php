<?php

use Trevix\Core\Config;
use Trevix\Core\View;

/**
 * Edición de una publicación propia: texto, visibilidad y música. Los archivos adjuntos no se modifican.
 *
 * @var array $post
 * @var array $visibilities
 * @var array $errors
 * @var array $old
 */
$maxBody = (int) Config::get('app.limits.post_body');
$body = (string) ($old['body'] ?? $post['body']);
$visibility = (string) ($old['visibility'] ?? $post['visibility']);
$postUrl = url('post.php', ['id' => $post['id']]);
$isRepost = $post['shared'] !== null || $post['shared_missing'];
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e($postUrl) ?>" aria-label="Volver a la publicación"><?= icon('arrow-left') ?></a>
        <div>
            <h1 class="page-header__title page-header__title--visible">Editar publicación</h1>
            <p class="page-header__subtitle">Se marcará como “editado”. Los archivos adjuntos no se pueden cambiar.</p>
        </div>
    </div>
</header>

<form class="form edit-post" method="post" action="<?= e(url('edit-post.php', ['id' => $post['id']])) ?>" novalidate>
    <?= csrf_field() ?>
    <div class="card form-card">
        <div class="field">
            <label class="field__label" for="ep-body"><?= $post['format'] === 'thread' ? 'Texto del hilo' : ($isRepost ? 'Comentario al compartir' : 'Texto') ?></label>
            <textarea class="input textarea" id="ep-body" name="body" rows="5" maxlength="<?= $maxBody ?>" data-autosize
                data-char-count="#ep-body-count"<?= invalid_attrs($errors, 'body', 'ep-body') ?>><?= e($body) ?></textarea>
            <?= field_error($errors, 'body', 'ep-body') ?>
            <p class="field__hint"><span id="ep-body-count"></span> · Usa #hashtags y @menciones.</p>
        </div>

        <?php if ($post['community'] !== null): ?>
            <p class="field__hint">
                <?= icon('users-round') ?> Publicada en <a href="<?= e(community_url($post['community'])) ?>"><?= e($post['community']['name']) ?></a>:
                la ven quienes pueden ver la comunidad.
            </p>
        <?php else: ?>
            <div class="field">
                <label class="field__label" for="ep-visibility">Visibilidad</label>
                <div class="select-wrap">
                    <?= icon('globe') ?>
                    <select class="select" id="ep-visibility" name="visibility"<?= invalid_attrs($errors, 'visibility', 'ep-visibility') ?>>
                        <?php foreach ($visibilities as $key => $label): ?>
                            <option value="<?= e($key) ?>" <?= $key === $visibility ? 'selected' : '' ?>><?= e($label) ?></option>
                        <?php endforeach; ?>
                    </select>
                </div>
                <?= field_error($errors, 'visibility', 'ep-visibility') ?>
                <p class="field__hint">Solo las publicaciones públicas se pueden compartir.</p>
            </div>
        <?php endif; ?>

        <?php if ($post['media'] !== []): ?>
            <div class="field">
                <p class="field__label">Archivos adjuntos</p>
                <div class="edit-post__media">
                    <?php foreach ($post['media'] as $item): ?>
                        <?php if ($item['type'] === 'video'): ?>
                            <video src="<?= e(url($item['src'])) ?>" preload="metadata" muted playsinline></video>
                        <?php else: ?>
                            <img src="<?= e(url($item['src'])) ?>" alt="<?= e($item['alt']) ?>" loading="lazy">
                        <?php endif; ?>
                    <?php endforeach; ?>
                </div>
            </div>
        <?php endif; ?>

        <?php if (!$isRepost && ($post['format'] !== 'thread' || !empty($post['song']))): ?>
            <div class="field">
                <p class="field__label"><?= icon('music') ?> Música</p>
                <?php View::partial('song-field', ['mode' => 'clip', 'song' => $post['song'] ?? null, 'withAdd' => true]); ?>
                <?= field_error($errors, 'song_id', 'ep-song') ?>
                <p class="field__hint">Añade, cambia o quita la canción y elige el fragmento de hasta <?= (int) Config::get('app.limits.song_clip_seconds') ?> segundos que sonará.</p>
            </div>
        <?php endif; ?>

        <?php if ($post['shared'] !== null): ?>
            <?php View::partial('post-embed', ['post' => $post['shared']]); ?>
        <?php endif; ?>
    </div>

    <div class="form__actions">
        <a class="btn btn--ghost" href="<?= e($postUrl) ?>">Cancelar</a>
        <button type="submit" class="btn btn--primary">Guardar cambios</button>
    </div>
</form>
