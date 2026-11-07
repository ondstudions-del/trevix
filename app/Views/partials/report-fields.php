<?php

use Trevix\Core\Config;
use Trevix\Models\Report;

/**
 * Motivo y detalles de un reporte (página report.php y diálogo).
 *
 * @var string $prefix  prefijo de los id para no repetirlos en la misma página
 * @var array  $errors
 * @var array  $old
 */
$errors = $errors ?? [];
$old = $old ?? [];
$maxDetails = (int) Config::get('app.limits.report_details', 1000);
?>
<fieldset class="report-reasons"<?= isset($errors['reason']) ? ' aria-invalid="true" aria-describedby="error-' . e($prefix) . '-reason"' : '' ?>>
    <legend class="field__label">¿Qué ocurre?</legend>
    <?php foreach (Report::REASONS as $key => $label): ?>
        <label class="report-reason">
            <input type="radio" name="reason" value="<?= e($key) ?>" required<?= ($old['reason'] ?? '') === $key ? ' checked' : '' ?>>
            <span><?= e($label) ?></span>
        </label>
    <?php endforeach; ?>
    <?= field_error($errors, 'reason', $prefix . '-reason') ?>
</fieldset>
<div class="field">
    <label class="field__label" for="<?= e($prefix) ?>-details">Detalles <span class="field__hint">(opcional, obligatorio si eliges «Otro motivo»)</span></label>
    <textarea class="input textarea" id="<?= e($prefix) ?>-details" name="details" rows="3" maxlength="<?= $maxDetails ?>"
        placeholder="Añade contexto que ayude al equipo de moderación."<?= invalid_attrs($errors, 'details', $prefix . '-details') ?>><?= e((string) ($old['details'] ?? '')) ?></textarea>
    <?= field_error($errors, 'details', $prefix . '-details') ?>
</div>
