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
        <a class="icon-btn" href="<?= e($target['url']) ?>" aria-label="<?= e(t('Volver')) ?>"><?= icon('arrow-left') ?></a>
        <div>
            <h1 class="page-header__title page-header__title--visible"><?= e(t('Reportar')) ?></h1>
            <p class="page-header__subtitle"><?= e(t('Vas a reportar {target}. Nadie más sabrá que fuiste tú.', ['target' => $target['label']])) ?></p>
        </div>
    </div>
</header>

<form class="form report-form" method="post" action="<?= e(url('api/reports.php')) ?>">
    <?= csrf_field() ?>
    <input type="hidden" name="type" value="<?= e($type) ?>">
    <input type="hidden" name="id" value="<?= $id ?>">
    <div class="card form-card">
        <?php View::partial('report-fields', ['prefix' => 'rp', 'errors' => $errors, 'old' => $old]); ?>
        <p class="field__hint"><?= icon('shield') ?> <?= e(t('El equipo de moderación revisa cada reporte. Si hay un peligro inmediato, contacta con los servicios de emergencia.')) ?></p>
    </div>
    <div class="form__actions">
        <a class="btn btn--ghost" href="<?= e($target['url']) ?>"><?= e(t('Cancelar')) ?></a>
        <button type="submit" class="btn btn--danger"><?= icon('flag') ?> <?= e(t('Enviar reporte')) ?></button>
    </div>
</form>
