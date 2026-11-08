<?php

use Trevix\Services\Giphy;

/**
 * Campo para adjuntar un GIF o sticker de GIPHY a un comentario o mensaje (assets/js/gifs.js).
 * Envía gif_id y gif_kind; el servidor vuelve a comprobar el GIF en GIPHY antes de guardarlo.
 * Sin clave de GIPHY configurada no se muestra.
 */
if (!Giphy::enabled()) {
    return;
}
?>
<div class="gif-field" data-gif-field>
    <input type="hidden" name="gif_id" value="" data-gif-id>
    <input type="hidden" name="gif_kind" value="gif" data-gif-kind-input>
    <div class="gif-field__selected" data-gif-selected hidden>
        <img alt="" data-gif-preview>
        <button type="button" class="gif-field__remove" data-gif-remove aria-label="Quitar GIF"><?= icon('x') ?></button>
    </div>
</div>
