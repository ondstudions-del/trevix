<?php
/**
 * Campo para confirmar una acción delicada con la contraseña actual.
 *
 * @var string $name
 * @var string $id
 * @var array  $errors
 * @var string $label
 */
$label = $label ?? 'Confirma con tu contraseña';
?>
<div class="field">
    <label class="field__label" for="<?= e($id) ?>"><?= e($label) ?></label>
    <div class="input-wrap">
        <?= icon('lock') ?>
        <input class="input" id="<?= e($id) ?>" name="<?= e($name) ?>" type="password" autocomplete="current-password" required maxlength="200"
            data-rule="required"<?= invalid_attrs($errors, $name, $id) ?>>
        <button type="button" class="input-wrap__action" data-toggle-password aria-label="Mostrar contraseña" aria-pressed="false">
            <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
        </button>
    </div>
    <?= field_error($errors, $name, $id) ?>
</div>
