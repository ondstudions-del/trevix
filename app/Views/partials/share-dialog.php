<?php
/*
 * Compartir fuera de TREVIX. Lo abre cualquier botón [data-share-out="URL"] (con data-share-title opcional).
 * X, WhatsApp, Facebook, Telegram y correo reciben el enlace por su URL oficial para compartir. TikTok no admite
 * enlaces externos desde la web: se copia el enlace y se abre TikTok para pegarlo en un mensaje o en la biografía.
 */
?>
<dialog class="modal share-dialog" id="share-dialog" aria-labelledby="share-dialog-title">
    <header class="modal__header">
        <div>
            <h2 class="modal__title" id="share-dialog-title"><?= e(t('Compartir')) ?></h2>
            <p class="share-dialog__target" data-share-target></p>
        </div>
        <button type="button" class="icon-btn" data-close-dialog aria-label="<?= e(t('Cerrar')) ?>"><?= icon('x') ?></button>
    </header>
    <div class="modal__body">
        <div class="share-dialog__grid">
            <a class="share-net share-net--x" data-share-net="x" href="#" target="_blank" rel="noopener noreferrer">
                <span class="share-net__badge"><svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M18.9 1.15h3.68l-8.04 9.19L24 22.85h-7.41l-5.8-7.58-6.64 7.58H.47l8.6-9.83L0 1.15h7.59l5.24 6.93Zm-1.29 19.5h2.04L6.49 3.24H4.3Z"/></svg></span>
                <span class="share-net__label">X</span>
            </a>
            <a class="share-net share-net--whatsapp" data-share-net="whatsapp" href="#" target="_blank" rel="noopener noreferrer">
                <span class="share-net__badge"><?= icon('message-circle') ?></span>
                <span class="share-net__label">WhatsApp</span>
            </a>
            <button type="button" class="share-net share-net--tiktok" data-share-net="tiktok">
                <span class="share-net__badge"><?= icon('music') ?></span>
                <span class="share-net__label">TikTok</span>
            </button>
            <a class="share-net share-net--facebook" data-share-net="facebook" href="#" target="_blank" rel="noopener noreferrer">
                <span class="share-net__badge share-net__badge--letter">f</span>
                <span class="share-net__label">Facebook</span>
            </a>
            <a class="share-net share-net--telegram" data-share-net="telegram" href="#" target="_blank" rel="noopener noreferrer">
                <span class="share-net__badge"><?= icon('send') ?></span>
                <span class="share-net__label">Telegram</span>
            </a>
            <a class="share-net share-net--mail" data-share-net="mail" href="#">
                <span class="share-net__badge"><?= icon('mail') ?></span>
                <span class="share-net__label"><?= e(t('Correo')) ?></span>
            </a>
            <button type="button" class="share-net share-net--copy" data-share-net="copy">
                <span class="share-net__badge"><?= icon('link') ?></span>
                <span class="share-net__label"><?= e(t('Copiar enlace')) ?></span>
            </button>
            <button type="button" class="share-net share-net--more" data-share-net="native" hidden>
                <span class="share-net__badge"><?= icon('share-2') ?></span>
                <span class="share-net__label"><?= e(t('Más opciones')) ?></span>
            </button>
        </div>
        <p class="share-dialog__hint" data-share-hint hidden></p>
    </div>
</dialog>
