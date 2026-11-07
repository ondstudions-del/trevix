<?php

use Trevix\Core\View;

/**
 * Formulario completo para reportar (funciona sin JavaScript).
 *
 * @var string $type
 * @var int    $id
 * @var array  $target  label, url
 * @var array  $errors
 * @var array  $old
 */
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e($target['url']) ?>" aria-label="Volver"><?= icon('arrow-left') ?></a>
        <div>
            <h1 class="page-header__title page-header__title--visible">Reportar</h1>
            <p class="page-header__subtitle">Vas a reportar <?= e($target['label']) ?>. Nadie más sabrá que fuiste tú.</p>
        </div>
    </div>
</header>

<form class="form report-form" method="post" action="<?= e(url('api/reports.php')) ?>">
    <?= csrf_field() ?>
    <input type="hidden" name="type" value="<?= e($type) ?>">
    <input type="hidden" name="id" value="<?= $id ?>">
    <div class="card form-card">
        <?php View::partial('report-fields', ['prefix' => 'rp', 'errors' => $errors, 'old' => $old]); ?>
        <p class="field__hint"><?= icon('shield') ?> El equipo de moderación revisa cada reporte. Si hay un peligro inmediato, contacta con los servicios de emergencia.</p>
    </div>
    <div class="form__actions">
        <a class="btn btn--ghost" href="<?= e($target['url']) ?>">Cancelar</a>
        <button type="submit" class="btn btn--danger"><?= icon('flag') ?> Enviar reporte</button>
    </div>
</form>
