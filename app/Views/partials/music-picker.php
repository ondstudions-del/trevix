<?php
/**
 * Selector de canciones (assets/js/music.js): catálogo único con las canciones de TREVIX y las pistas de Audius
 * y Free To Use. Busca en api/music.php y, para publicaciones e historias, deja elegir el fragmento que sonará.
 */
?>
<dialog class="modal music-picker" id="music-picker" aria-labelledby="music-picker-title" data-music-picker>
    <header class="modal__header">
        <h2 class="modal__title" id="music-picker-title" data-picker-title><?= e(t('Añadir música')) ?></h2>
        <button type="button" class="icon-btn" data-close-dialog aria-label="<?= e(t('Cerrar')) ?>"><?= icon('x') ?></button>
    </header>

    <div class="modal__body music-picker__body">
        <section class="music-picker__step" data-picker-step="search">
            <label class="sr-only" for="music-picker-q"><?= e(t('Buscar canciones')) ?></label>
            <div class="input-wrap">
                <?= icon('search') ?>
                <input class="input" id="music-picker-q" type="search" maxlength="80" autocomplete="off"
                    placeholder="<?= e(t('Busca por canción o artista')) ?>" data-picker-q>
            </div>
            <div class="segmented segmented--sm music-picker__sort" role="radiogroup" aria-label="<?= e(t('Orden')) ?>" data-picker-sorts>
                <label class="segmented__option">
                    <input type="radio" name="music_picker_sort" value="popular" checked data-picker-sort>
                    <span><?= e(t('Más usadas')) ?></span>
                </label>
                <label class="segmented__option">
                    <input type="radio" name="music_picker_sort" value="recent" data-picker-sort>
                    <span><?= e(t('Recientes')) ?></span>
                </label>
            </div>
            <ul class="music-picker__list" data-picker-results aria-live="polite"></ul>
            <p class="music-picker__empty" data-picker-empty hidden></p>
            <button type="button" class="btn btn--secondary btn--sm music-picker__more" data-picker-more hidden><?= e(t('Ver más canciones')) ?></button>
            <p class="music-picker__credit" data-picker-credit hidden></p>
        </section>

        <section class="music-picker__step" data-picker-step="clip" hidden>
            <div class="music-picker__selected" data-picker-selected></div>
            <div class="field">
                <label class="field__label" for="music-picker-start"><?= t('Elige el fragmento de {n} segundos', ['n' => '<span data-picker-length>30</span>']) ?></label>
                <input class="range" id="music-picker-start" type="range" min="0" max="0" step="1" value="0" data-picker-start>
                <p class="field__hint"><?= t('Suena desde {from} hasta {to}.', ['from' => '<strong data-picker-from>0:00</strong>', 'to' => '<strong data-picker-to>0:30</strong>']) ?></p>
            </div>
            <button type="button" class="btn btn--secondary btn--sm" data-picker-preview>
                <span class="music-picker__icon-play"><?= icon('play') ?></span><span class="music-picker__icon-pause"><?= icon('pause') ?></span>
                <span data-picker-preview-label><?= e(t('Escuchar fragmento')) ?></span>
            </button>
        </section>
    </div>

    <footer class="modal__footer music-picker__footer" data-picker-footer hidden>
        <button type="button" class="btn btn--ghost" data-picker-back><?= e(t('Elegir otra')) ?></button>
        <button type="button" class="btn btn--primary" data-picker-confirm><?= e(t('Usar este fragmento')) ?></button>
    </footer>
    <audio preload="none" data-picker-audio></audio>
</dialog>
