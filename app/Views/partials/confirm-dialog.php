<dialog class="modal modal--sm confirm-dialog" id="confirm-dialog" aria-labelledby="confirm-dialog-text">
    <form method="dialog" class="confirm-dialog__form">
        <div class="modal__body">
            <span class="confirm-dialog__icon"><?= icon('triangle-alert') ?></span>
            <p class="confirm-dialog__text" id="confirm-dialog-text" data-confirm-text></p>
        </div>
        <footer class="modal__footer confirm-dialog__actions">
            <button type="submit" class="btn btn--ghost" value="cancel"><?= e(t('Cancelar')) ?></button>
            <button type="submit" class="btn btn--danger" value="ok" data-confirm-ok><?= e(t('Confirmar')) ?></button>
        </footer>
    </form>
</dialog>
