<?php
/**
 * Selector de GIF y stickers de GIPHY (assets/js/gifs.js). Busca en api/gifs.php y deja el id elegido
 * en el campo [data-gif-field] del formulario que lo abrió (comentarios y mensajes). La estrella de cada uno lo
 * guarda en «Favoritos» (api/messages.php, action=sticker_favorite).
 */
?>
<dialog class="modal gif-picker" id="gif-picker" aria-labelledby="gif-picker-title" data-gif-favorites="<?= e(url('api/messages.php')) ?>">
    <header class="modal__header">
        <h2 class="modal__title" id="gif-picker-title"><?= e(t('GIF y stickers')) ?></h2>
        <button type="button" class="icon-btn" data-close-dialog aria-label="<?= e(t('Cerrar')) ?>"><?= icon('x') ?></button>
    </header>
    <div class="modal__body gif-picker__body">
        <div class="segmented gif-picker__kinds" role="radiogroup" aria-label="<?= e(t('Tipo')) ?>">
            <label class="segmented__option">
                <input type="radio" name="gif_picker_kind" value="gif" checked data-gif-kind>
                <span>GIF</span>
            </label>
            <label class="segmented__option">
                <input type="radio" name="gif_picker_kind" value="sticker" data-gif-kind>
                <span>Stickers</span>
            </label>
            <label class="segmented__option">
                <input type="radio" name="gif_picker_kind" value="favorites" data-gif-kind>
                <span><?= icon('star') ?> <?= e(t('Favoritos')) ?></span>
            </label>
        </div>
        <label class="sr-only" for="gif-picker-q"><?= e(t('Buscar en GIPHY')) ?></label>
        <div class="input-wrap">
            <?= icon('search') ?>
            <input class="input" id="gif-picker-q" type="search" maxlength="50" autocomplete="off" placeholder="<?= e(t('Buscar en GIPHY')) ?>" data-gif-q>
        </div>
        <div class="gif-picker__grid" data-gif-results aria-live="polite"></div>
        <p class="music-picker__empty" data-gif-empty hidden></p>
        <button type="button" class="btn btn--secondary btn--sm gif-picker__more" data-gif-more hidden><?= e(t('Ver más')) ?></button>
    </div>
    <footer class="gif-picker__footer">
        <span class="gif-picker__powered"><?= e(t('Con la tecnología de')) ?> <strong>GIPHY</strong></span>
    </footer>
</dialog>
