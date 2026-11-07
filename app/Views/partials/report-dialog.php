<?php

use Trevix\Core\View;

/* Diálogo para reportar sin salir de la página. Los enlaces [data-report] lo abren; sin JavaScript llevan a report.php. */
?>
<dialog class="modal report-dialog" id="report-dialog" aria-labelledby="report-dialog-title">
    <form class="report-dialog__form" method="post" action="<?= e(url('api/reports.php')) ?>" data-report-form>
        <header class="modal__header">
            <div>
                <h2 class="modal__title" id="report-dialog-title">Reportar</h2>
                <p class="report-dialog__target" data-report-target></p>
            </div>
            <button type="button" class="icon-btn" data-report-close aria-label="Cerrar"><?= icon('x') ?></button>
        </header>
        <div class="modal__body">
            <?= csrf_field() ?>
            <input type="hidden" name="type" value="" data-report-type>
            <input type="hidden" name="id" value="" data-report-id>
            <?php View::partial('report-fields', ['prefix' => 'rd']); ?>
            <p class="report-dialog__error" role="alert" data-report-error hidden></p>
        </div>
        <footer class="modal__footer">
            <button type="button" class="btn btn--ghost" data-report-close>Cancelar</button>
            <button type="submit" class="btn btn--danger"><?= icon('flag') ?> Enviar reporte</button>
        </footer>
    </form>
</dialog>
