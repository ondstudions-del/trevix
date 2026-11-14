<?php
/*
 * Enviar una publicación o un reel por mensaje dentro de TREVIX. Lo abren los botones [data-send-post="ID"]
 * (data-send-label opcional). share.js carga los chats recientes y las personas que sigues desde
 * api/messages.php?action=share_targets y envía action=send con shared_post a cada destino elegido.
 */
?>
<dialog class="modal send-post-dialog" id="send-post-dialog" aria-labelledby="send-post-title">
    <form class="send-post-dialog__form" data-send-post-form>
        <header class="modal__header">
            <div>
                <h2 class="modal__title" id="send-post-title"><?= e(t('Enviar por mensaje')) ?></h2>
                <p class="share-dialog__target" data-send-post-target></p>
            </div>
            <button type="button" class="icon-btn" data-close-dialog aria-label="<?= e(t('Cerrar')) ?>"><?= icon('x') ?></button>
        </header>
        <div class="modal__body">
            <label class="field">
                <span class="sr-only"><?= e(t('Buscar chats o personas')) ?></span>
                <input class="input" type="search" maxlength="80" autocomplete="off" placeholder="<?= e(t('Buscar chats o personas')) ?>" data-send-post-search>
            </label>
            <ul class="send-post-dialog__list" role="list" data-send-post-list aria-live="polite"></ul>
            <p class="send-post-dialog__empty" data-send-post-empty hidden></p>
            <label class="field">
                <span class="sr-only"><?= e(t('Mensaje (opcional)')) ?></span>
                <input class="input" type="text" maxlength="500" placeholder="<?= e(t('Escribe un mensaje (opcional)')) ?>" data-send-post-body>
            </label>
            <p class="report-dialog__error" role="alert" data-send-post-error hidden></p>
        </div>
        <footer class="modal__footer">
            <button type="button" class="btn btn--ghost" data-close-dialog><?= e(t('Cancelar')) ?></button>
            <button type="submit" class="btn btn--primary" data-send-post-submit disabled><?= icon('send') ?> <span data-send-post-count><?= e(t('Enviar')) ?></span></button>
        </footer>
    </form>
</dialog>
