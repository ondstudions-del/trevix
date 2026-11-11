<?php

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Models\Post;
use Trevix\Models\Story;
use Trevix\Services\Giphy;

/** @var array|null $viewer */
$uploads = Config::get('app.uploads');
$maxBody = (int) Config::get('app.limits.post_body');
$firstName = explode(' ', (string) ($viewer['display_name'] ?? ''))[0];
$postPrompt = $firstName !== '' ? t('¿Qué quieres compartir, {name}?', ['name' => $firstName]) : t('¿Qué quieres compartir?');
?>
<dialog class="modal composer" id="composer" aria-labelledby="composer-title" data-composer>
    <form class="composer__form" method="post" action="<?= e(url('api/posts.php')) ?>" enctype="multipart/form-data" data-composer-form novalidate>
        <?= csrf_field() ?>
        <input type="file" name="media[]" multiple hidden data-composer-files>

        <header class="modal__header">
            <h2 class="modal__title" id="composer-title"><?= e(t('Crear publicación')) ?></h2>
            <div class="segmented" role="radiogroup" aria-label="<?= e(t('Formato de la publicación')) ?>">
                <label class="segmented__option">
                    <input type="radio" name="format" value="post" checked data-composer-format-input>
                    <span><?= icon('image') ?> <?= e(t('Publicación')) ?></span>
                </label>
                <label class="segmented__option">
                    <input type="radio" name="format" value="thread" data-composer-format-input>
                    <span><?= icon('messages-square') ?> <?= e(t('Hilo')) ?></span>
                </label>
            </div>
            <button type="button" class="icon-btn" data-close-dialog aria-label="<?= e(t('Cerrar')) ?>">
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
                    <?= icon('users-round') ?> <?= e(t('Publicando en')) ?> <strong data-composer-community-name></strong>
                </p>
                <label class="sr-only" for="composer-text"><?= e(t('Contenido de la publicación')) ?></label>
                <textarea id="composer-text" name="body" rows="4" maxlength="<?= $maxBody ?>" data-autosize data-composer-text
                    data-placeholder-post="<?= e($postPrompt) ?>"
                    data-placeholder-thread="<?= e(t('Inicia una conversación. Usa #hashtags y @menciones.')) ?>"
                    placeholder="<?= e($postPrompt) ?>"></textarea>
                <ul class="mention-suggest" data-mention-list role="listbox" aria-label="<?= e(t('Sugerencias de menciones')) ?>" hidden></ul>
                <ul class="composer__media" data-composer-media hidden aria-label="<?= e(t('Archivos adjuntos')) ?>"></ul>
                <?php \Trevix\Core\View::partial('song-field', ['mode' => 'clip']); ?>
                <?php \Trevix\Core\View::partial('gif-field'); ?>

                <fieldset class="composer__backgrounds" data-composer-backgrounds hidden>
                    <legend class="composer__legend"><?= icon('palette') ?> <?= e(t('Fondo del hilo')) ?></legend>
                    <label class="bg-swatch bg-swatch--none" data-tooltip="<?= e(t('Sin fondo')) ?>">
                        <input class="sr-only" type="radio" name="background" value="" checked>
                        <span class="sr-only"><?= e(t('Sin fondo')) ?></span>
                    </label>
                    <?php foreach (Story::BACKGROUNDS as $key => $label): ?>
                        <label class="bg-swatch story-bg--<?= e($key) ?>" data-tooltip="<?= e(t($label)) ?>">
                            <input class="sr-only" type="radio" name="background" value="<?= e($key) ?>">
                            <span class="sr-only"><?= e(t($label)) ?></span>
                        </label>
                    <?php endforeach; ?>
                </fieldset>

                <fieldset class="composer__extra" data-composer-panel="life" hidden disabled>
                    <legend class="sr-only"><?= e(t('Acontecimiento importante')) ?></legend>
                    <?= icon('star') ?>
                    <div class="select-wrap select-wrap--sm">
                        <select name="life_event" class="select" aria-label="<?= e(t('Acontecimiento importante')) ?>" data-composer-life>
                            <option value=""><?= e(t('Elige un acontecimiento')) ?></option>
                            <?php foreach (Post::LIFE_EVENTS as $key => [$label]): ?>
                                <option value="<?= e($key) ?>"><?= e(t($label)) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <button type="button" class="icon-btn icon-btn--sm" data-composer-panel-close aria-label="<?= e(t('Quitar acontecimiento')) ?>"><?= icon('x') ?></button>
                </fieldset>

                <fieldset class="composer__extra" data-composer-panel="location" hidden disabled>
                    <legend class="sr-only"><?= e(t('Ubicación')) ?></legend>
                    <?= icon('map-pin') ?>
                    <input class="input input--sm" type="text" name="location_name" maxlength="120" placeholder="<?= e(t('¿Dónde estás?')) ?>" aria-label="<?= e(t('Lugar')) ?>" data-composer-place>
                    <input type="hidden" name="location_lat" value="" data-composer-lat>
                    <input type="hidden" name="location_lng" value="" data-composer-lng>
                    <button type="button" class="btn btn--ghost btn--sm js-only" data-composer-locate><?= icon('locate') ?> <?= e(t('Usar mi ubicación')) ?></button>
                    <button type="button" class="icon-btn icon-btn--sm" data-composer-panel-close aria-label="<?= e(t('Quitar ubicación')) ?>"><?= icon('x') ?></button>
                </fieldset>

                <fieldset class="composer__event" data-composer-panel="event" hidden disabled>
                    <legend class="composer__legend"><?= icon('calendar') ?> <?= e(t('Evento')) ?>
                        <button type="button" class="icon-btn icon-btn--sm" data-composer-panel-close aria-label="<?= e(t('Quitar evento')) ?>"><?= icon('x') ?></button>
                    </legend>
                    <label class="composer__event-cover">
                        <img alt="" data-composer-event-preview hidden>
                        <span data-composer-event-cover-label><?= icon('image-plus') ?> <?= e(t('Portada (opcional)')) ?></span>
                        <input class="sr-only" type="file" name="event_cover" accept="<?= e(implode(',', $uploads['image']['mimes'])) ?>" data-composer-event-cover>
                    </label>
                    <label class="field">
                        <span class="field__label"><?= e(t('Nombre del evento')) ?></span>
                        <input class="input" type="text" name="event[title]" maxlength="120" required data-composer-event-title>
                    </label>
                    <div class="composer__event-dates">
                        <label class="field">
                            <span class="field__label"><?= e(t('Empieza')) ?></span>
                            <input class="input" type="datetime-local" name="event[starts_at]" required>
                        </label>
                        <label class="field">
                            <span class="field__label"><?= e(t('Termina (opcional)')) ?></span>
                            <input class="input" type="datetime-local" name="event[ends_at]">
                        </label>
                    </div>
                    <label class="field">
                        <span class="field__label"><?= e(t('Lugar')) ?></span>
                        <input class="input" type="text" name="event[place]" maxlength="160" required placeholder="<?= e(t('Dirección, local o «En línea»')) ?>">
                    </label>
                    <label class="field">
                        <span class="field__label"><?= e(t('Descripción (opcional)')) ?></span>
                        <textarea class="input" name="event[description]" rows="3" maxlength="2000"></textarea>
                    </label>
                </fieldset>
                <div class="composer__share" data-composer-share hidden>
                    <input type="hidden" name="shared_post_id" value="" data-composer-share-id disabled>
                    <div class="composer__share-head">
                        <span><?= icon('repeat-2') ?> <?= e(t('Compartiendo a')) ?> <strong data-composer-share-author></strong></span>
                        <button type="button" class="icon-btn icon-btn--sm" data-composer-share-cancel aria-label="<?= e(t('Quitar publicación compartida')) ?>"><?= icon('x') ?></button>
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
                <label class="icon-btn icon-btn--accent" data-tooltip="<?= e(t('Imágenes (JPG, PNG, WEBP, GIF)')) ?>">
                    <?= icon('image-plus') ?>
                    <span class="sr-only"><?= e(t('Agregar imágenes')) ?></span>
                    <input class="sr-only" type="file" multiple accept="<?= e(implode(',', $uploads['image']['mimes'])) ?>" data-composer-pick-input="image">
                </label>
                <label class="icon-btn icon-btn--accent" data-tooltip="<?= e(t('Video (MP4, WEBM, MOV)')) ?>" data-post-only>
                    <?= icon('clapperboard') ?>
                    <span class="sr-only"><?= e(t('Agregar video')) ?></span>
                    <input class="sr-only" type="file" accept="<?= e(implode(',', $uploads['video']['mimes'])) ?>" data-composer-pick-input="video">
                </label>
                <?php if (Auth::check()): ?>
                    <button type="button" class="icon-btn icon-btn--accent js-only" data-song-open data-composer-song-tool data-post-only data-tooltip="<?= e(t('Música de la biblioteca')) ?>">
                        <?= icon('music') ?>
                        <span class="sr-only"><?= e(t('Añadir música')) ?></span>
                    </button>
                    <?php if (Giphy::enabled()): ?>
                        <button type="button" class="icon-btn icon-btn--accent js-only" data-gif-open data-composer-gif-tool data-post-only data-tooltip="<?= e(t('GIF o sticker')) ?>">
                            <?= icon('sticker') ?>
                            <span class="sr-only"><?= e(t('Publicar un GIF')) ?></span>
                        </button>
                    <?php endif; ?>
                    <button type="button" class="icon-btn icon-btn--accent js-only" data-composer-tool="location" data-post-only data-tooltip="<?= e(t('Ubicación')) ?>">
                        <?= icon('map-pin') ?>
                        <span class="sr-only"><?= e(t('Agregar ubicación')) ?></span>
                    </button>
                    <button type="button" class="icon-btn icon-btn--accent js-only" data-composer-tool="life" data-post-only data-tooltip="<?= e(t('Acontecimiento importante')) ?>">
                        <?= icon('star') ?>
                        <span class="sr-only"><?= e(t('Acontecimiento importante')) ?></span>
                    </button>
                    <button type="button" class="icon-btn icon-btn--accent js-only" data-composer-tool="event" data-post-only data-tooltip="<?= e(t('Crear evento')) ?>">
                        <?= icon('calendar') ?>
                        <span class="sr-only"><?= e(t('Crear evento')) ?></span>
                    </button>
                <?php endif; ?>
                <label class="sr-only" for="composer-visibility"><?= e(t('Visibilidad')) ?></label>
                <div class="select-wrap select-wrap--sm">
                    <?= icon('globe') ?>
                    <select id="composer-visibility" name="visibility" class="select">
                        <option value="public"><?= e(t('Público')) ?></option>
                        <option value="followers"><?= e(t('Seguidores')) ?></option>
                        <option value="private"><?= e(t('Solo yo')) ?></option>
                    </select>
                </div>
            </div>
            <div class="composer__submit">
                <span class="char-counter" data-char-counter aria-live="polite"><?= $maxBody ?></span>
                <button type="submit" class="btn btn--primary" data-composer-submit
                    <?= Auth::check() ? '' : 'disabled aria-disabled="true" data-tooltip="' . e(t('Inicia sesión para publicar')) . '"' ?>><?= e(t('Publicar')) ?></button>
            </div>
        </footer>
    </form>
</dialog>

<dialog class="lightbox" id="lightbox" aria-label="<?= e(t('Visor de imágenes')) ?>">
    <button type="button" class="icon-btn lightbox__close" data-close-dialog aria-label="<?= e(t('Cerrar visor')) ?>"><?= icon('x') ?></button>
    <button type="button" class="icon-btn lightbox__nav lightbox__nav--prev" data-lightbox-prev aria-label="<?= e(t('Imagen anterior')) ?>"><?= icon('chevron-left') ?></button>
    <figure class="lightbox__figure">
        <img src="data:," alt="" data-lightbox-img>
        <figcaption class="lightbox__caption" data-lightbox-caption></figcaption>
    </figure>
    <button type="button" class="icon-btn lightbox__nav lightbox__nav--next" data-lightbox-next aria-label="<?= e(t('Imagen siguiente')) ?>"><?= icon('chevron-right') ?></button>
</dialog>

<?php \Trevix\Core\View::partial('confirm-dialog'); ?>

<template id="tpl-media-item">
    <li class="composer__media-item">
        <button type="button" class="composer__media-remove" aria-label="<?= e(t('Quitar archivo')) ?>"><?= icon('x') ?></button>
    </li>
</template>
