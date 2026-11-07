<?php

use Trevix\Core\Auth;
use Trevix\Core\Config;

/** @var array|null $viewer */
$uploads = Config::get('app.uploads');
$maxBody = (int) Config::get('app.limits.post_body');
$firstName = explode(' ', (string) ($viewer['display_name'] ?? ''))[0];
?>
<dialog class="modal composer" id="composer" aria-labelledby="composer-title" data-composer>
    <form class="composer__form" method="post" action="<?= e(url('api/posts.php')) ?>" enctype="multipart/form-data" data-composer-form novalidate>
        <?= csrf_field() ?>
        <input type="file" name="media[]" multiple hidden data-composer-files>

        <header class="modal__header">
            <h2 class="modal__title" id="composer-title">Crear publicación</h2>
            <div class="segmented" role="radiogroup" aria-label="Formato de la publicación">
                <label class="segmented__option">
                    <input type="radio" name="format" value="post" checked data-composer-format-input>
                    <span><?= icon('image') ?> Publicación</span>
                </label>
                <label class="segmented__option">
                    <input type="radio" name="format" value="thread" data-composer-format-input>
                    <span><?= icon('messages-square') ?> Hilo</span>
                </label>
            </div>
            <button type="button" class="icon-btn" data-close-dialog aria-label="Cerrar">
                <?= icon('x') ?>
            </button>
        </header>

        <div class="modal__body composer__body">
            <?= $viewer ? avatar($viewer, 'md') : '' ?>
            <div class="composer__main">
                <?php if ($viewer): ?>
                    <p class="composer__author"><?= e($viewer['display_name']) ?> <span>@<?= e($viewer['username']) ?></span></p>
                <?php endif; ?>
                <p class="composer__community" data-composer-community hidden>
                    <input type="hidden" name="community_id" value="" data-composer-community-id disabled>
                    <?= icon('users-round') ?> Publicando en <strong data-composer-community-name></strong>
                </p>
                <label class="sr-only" for="composer-text">Contenido de la publicación</label>
                <textarea id="composer-text" name="body" rows="4" maxlength="<?= $maxBody ?>" data-autosize data-composer-text
                    data-placeholder-post="¿Qué quieres compartir<?= $firstName !== '' ? ', ' . e($firstName) : '' ?>?"
                    data-placeholder-thread="Inicia una conversación. Usa #hashtags y @menciones."
                    placeholder="¿Qué quieres compartir<?= $firstName !== '' ? ', ' . e($firstName) : '' ?>?"></textarea>
                <ul class="composer__media" data-composer-media hidden aria-label="Archivos adjuntos"></ul>
                <?php \Trevix\Core\View::partial('song-field', ['mode' => 'clip']); ?>
                <div class="composer__share" data-composer-share hidden>
                    <input type="hidden" name="shared_post_id" value="" data-composer-share-id disabled>
                    <div class="composer__share-head">
                        <span><?= icon('repeat-2') ?> Compartiendo a <strong data-composer-share-author></strong></span>
                        <button type="button" class="icon-btn icon-btn--sm" data-composer-share-cancel aria-label="Quitar publicación compartida"><?= icon('x') ?></button>
                    </div>
                    <p class="composer__share-text" data-composer-share-text></p>
                </div>
                <div class="composer__progress" data-composer-progress hidden>
                    <div class="composer__progress-bar" data-composer-progress-bar></div>
                </div>
                <p class="composer__error" data-composer-error role="alert" hidden></p>
            </div>
        </div>

        <footer class="modal__footer composer__footer">
            <div class="composer__tools">
                <label class="icon-btn icon-btn--accent" data-tooltip="Imágenes (JPG, PNG, WEBP, GIF)">
                    <?= icon('image-plus') ?>
                    <span class="sr-only">Agregar imágenes</span>
                    <input class="sr-only" type="file" multiple accept="<?= e(implode(',', $uploads['image']['mimes'])) ?>" data-composer-pick-input="image">
                </label>
                <label class="icon-btn icon-btn--accent" data-tooltip="Video (MP4, WEBM, MOV)">
                    <?= icon('clapperboard') ?>
                    <span class="sr-only">Agregar video</span>
                    <input class="sr-only" type="file" accept="<?= e(implode(',', $uploads['video']['mimes'])) ?>" data-composer-pick-input="video">
                </label>
                <?php if (Auth::check()): ?>
                    <button type="button" class="icon-btn icon-btn--accent js-only" data-song-open data-composer-song-tool data-tooltip="Música de la biblioteca">
                        <?= icon('music') ?>
                        <span class="sr-only">Añadir música</span>
                    </button>
                <?php endif; ?>
                <label class="sr-only" for="composer-visibility">Visibilidad</label>
                <div class="select-wrap select-wrap--sm">
                    <?= icon('globe') ?>
                    <select id="composer-visibility" name="visibility" class="select">
                        <option value="public">Público</option>
                        <option value="followers">Seguidores</option>
                        <option value="private">Solo yo</option>
                    </select>
                </div>
            </div>
            <div class="composer__submit">
                <span class="char-counter" data-char-counter aria-live="polite"><?= $maxBody ?></span>
                <button type="submit" class="btn btn--primary" data-composer-submit
                    <?= Auth::check() ? '' : 'disabled aria-disabled="true" data-tooltip="Inicia sesión para publicar"' ?>>Publicar</button>
            </div>
        </footer>
    </form>
</dialog>

<dialog class="lightbox" id="lightbox" aria-label="Visor de imágenes">
    <button type="button" class="icon-btn lightbox__close" data-close-dialog aria-label="Cerrar visor"><?= icon('x') ?></button>
    <button type="button" class="icon-btn lightbox__nav lightbox__nav--prev" data-lightbox-prev aria-label="Imagen anterior"><?= icon('chevron-left') ?></button>
    <figure class="lightbox__figure">
        <img src="data:," alt="" data-lightbox-img>
        <figcaption class="lightbox__caption" data-lightbox-caption></figcaption>
    </figure>
    <button type="button" class="icon-btn lightbox__nav lightbox__nav--next" data-lightbox-next aria-label="Imagen siguiente"><?= icon('chevron-right') ?></button>
</dialog>

<?php \Trevix\Core\View::partial('confirm-dialog'); ?>

<template id="tpl-media-item">
    <li class="composer__media-item">
        <button type="button" class="composer__media-remove" aria-label="Quitar archivo"><?= icon('x') ?></button>
    </li>
</template>
