<?php

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\View;

/**
 * @var array  $backgrounds
 * @var string $exitUrl
 * @var array  $limits
 * @var array|null $song canción elegida desde la biblioteca («Usar en historia»)
 */
$uploads = Config::get('app.uploads');
$accept = implode(',', array_merge($uploads['image']['mimes'], $uploads['video']['mimes']));
$canWrite = Auth::check();
?>
<div class="story-viewer story-viewer--create">
    <a class="story-viewer__brand" href="<?= e(url('feed.php')) ?>" aria-label="TREVIX, volver al inicio">
        <?php View::partial('logo', ['size' => 32, 'wordmark' => true]); ?>
    </a>
    <a class="icon-btn story-viewer__close" href="<?= e($exitUrl) ?>" aria-label="Cancelar"><?= icon('x') ?></a>

    <form class="story-create" method="post" action="<?= e(url('api/stories.php')) ?>" enctype="multipart/form-data" novalidate
        data-story-create data-video-seconds="<?= (int) $limits['videoSeconds'] ?>"
        data-video-bytes="<?= (int) $limits['videoBytes'] ?>" data-image-bytes="<?= (int) $limits['imageBytes'] ?>">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="create">

        <header class="story-create__head">
            <h1>Nueva historia</h1>
            <p>Se verá durante 24 horas. Si tu cuenta es privada, solo la verán tus seguidores.</p>
        </header>
        <?php View::partial('flash'); ?>

        <div class="segmented story-create__tabs" role="radiogroup" aria-label="Tipo de historia">
            <label class="segmented__option">
                <input type="radio" name="type" value="media" checked data-story-type>
                <span><?= icon('image') ?> Foto o video</span>
            </label>
            <label class="segmented__option">
                <input type="radio" name="type" value="text" data-story-type>
                <span><?= icon('type') ?> Texto</span>
            </label>
        </div>

        <div class="story-create__stage">
            <div class="story-create__panel story-create__panel--media">
                <label class="story-create__drop" for="story-file" data-story-drop>
                    <?= icon('image-plus') ?>
                    <strong>Elige una foto o un video</strong>
                    <span>JPG, PNG, WEBP o GIF hasta <?= e(round($limits['imageBytes'] / 1048576)) ?> MB ·
                        MP4, WEBM o MOV hasta <?= e(round($limits['videoBytes'] / 1048576)) ?> MB y <?= (int) $limits['videoSeconds'] ?> s</span>
                </label>
                <input class="story-create__file" id="story-file" type="file" name="media" accept="<?= e($accept) ?>" data-story-file>
                <div class="story-create__preview" data-story-preview hidden></div>
            </div>
            <div class="story-create__panel story-create__panel--text story-bg--violet" data-story-text-panel>
                <label class="sr-only" for="story-text">Texto de la historia</label>
                <textarea id="story-text" name="text" maxlength="<?= (int) $limits['text'] ?>" rows="5" placeholder="Escribe algo…" data-story-text></textarea>
            </div>
        </div>

        <div class="field story-create__options story-create__options--media">
            <label class="field__label" for="story-caption">Descripción <span class="field__hint">(opcional)</span></label>
            <input class="input" id="story-caption" type="text" name="caption" maxlength="<?= (int) $limits['caption'] ?>" placeholder="Agrega una descripción" autocomplete="off">
        </div>
        <fieldset class="field story-create__options story-create__options--text">
            <legend class="field__label">Fondo</legend>
            <div class="story-create__swatches">
                <?php foreach ($backgrounds as $key => $label): ?>
                    <label class="story-create__swatch story-bg--<?= e($key) ?>" data-tooltip="<?= e($label) ?>">
                        <input class="sr-only" type="radio" name="background" value="<?= e($key) ?>" <?= $key === 'violet' ? 'checked' : '' ?> data-story-bg>
                        <span class="sr-only"><?= e($label) ?></span>
                    </label>
                <?php endforeach; ?>
            </div>
        </fieldset>

        <?php if ($canWrite): ?>
            <div class="field story-create__music">
                <p class="field__label"><?= icon('music') ?> Música <span class="field__hint">(opcional)</span></p>
                <?php View::partial('song-field', ['mode' => 'clip', 'song' => $song ?? null, 'withAdd' => true]); ?>
                <p class="field__hint">Con música, una foto o un texto se muestran <?= (int) $limits['songSeconds'] ?> segundos; en un video, la canción reemplaza su sonido.</p>
            </div>
        <?php endif; ?>

        <div class="composer__progress" data-story-progress hidden><div class="composer__progress-bar" data-story-progress-bar></div></div>
        <p class="composer__error" data-story-error role="alert" hidden></p>

        <footer class="story-create__actions">
            <a class="btn btn--ghost" href="<?= e($exitUrl) ?>">Cancelar</a>
            <button type="submit" class="btn btn--primary" data-story-submit
                <?= $canWrite ? '' : 'disabled aria-disabled="true" data-tooltip="Inicia sesión para publicar"' ?>><?= icon('send') ?> Compartir historia</button>
        </footer>
    </form>
</div>
<?php if ($canWrite): ?>
    <?php View::partial('music-picker'); ?>
<?php endif; ?>
<script src="<?= e(asset('js/story-create.js')) ?>" defer></script>
<script src="<?= e(asset('js/music.js')) ?>" defer></script>
