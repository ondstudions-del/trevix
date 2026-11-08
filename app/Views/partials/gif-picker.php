<?php
/**
 * Selector de GIF y stickers de GIPHY (assets/js/gifs.js). Busca en api/gifs.php y deja el id elegido
 * en el campo [data-gif-field] del formulario que lo abrió (comentarios y mensajes).
 */
?>
<dialog class="modal gif-picker" id="gif-picker" aria-labelledby="gif-picker-title">
    <header class="modal__header">
        <h2 class="modal__title" id="gif-picker-title">GIF y stickers</h2>
        <button type="button" class="icon-btn" data-close-dialog aria-label="Cerrar"><?= icon('x') ?></button>
    </header>
    <div class="modal__body gif-picker__body">
        <div class="segmented gif-picker__kinds" role="radiogroup" aria-label="Tipo">
            <label class="segmented__option">
                <input type="radio" name="gif_picker_kind" value="gif" checked data-gif-kind>
                <span>GIF</span>
            </label>
            <label class="segmented__option">
                <input type="radio" name="gif_picker_kind" value="sticker" data-gif-kind>
                <span>Stickers</span>
            </label>
        </div>
        <label class="sr-only" for="gif-picker-q">Buscar en GIPHY</label>
        <div class="input-wrap">
            <?= icon('search') ?>
            <input class="input" id="gif-picker-q" type="search" maxlength="50" autocomplete="off" placeholder="Buscar en GIPHY" data-gif-q>
        </div>
        <div class="gif-picker__grid" data-gif-results aria-live="polite"></div>
        <p class="music-picker__empty" data-gif-empty hidden></p>
        <button type="button" class="btn btn--secondary btn--sm gif-picker__more" data-gif-more hidden>Ver más</button>
    </div>
    <footer class="gif-picker__footer">
        <span class="gif-picker__powered">Con la tecnología de <strong>GIPHY</strong></span>
    </footer>
</dialog>
