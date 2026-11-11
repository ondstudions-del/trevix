<?php
/**
 * Aceptar o rechazar una apelación pendiente (ficha del usuario y sección Apelaciones).
 *
 * @var array $appeal Appeal::find() / forUser() / adminList()
 */
$aid = (int) $appeal['id'];
$action = url('admin/appeals.php');
$acceptText = $appeal['type'] === 'suspension'
    ? 'Se levantará la suspensión y la persona podrá volver a entrar.'
    : 'Se retirará la advertencia.';
?>
<div class="content-row__actions">
    <details class="admin-menu">
        <summary class="btn btn--primary btn--sm"><?= icon('circle-check') ?> <?= e(t('Aceptar')) ?></summary>
        <div class="admin-menu__panel">
            <form method="post" action="<?= e($action) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="id" value="<?= $aid ?>">
                <input type="hidden" name="action" value="accept">
                <p class="content-row__muted"><?= e(t($acceptText)) ?></p>
                <label class="field__label" for="appeal-accept-<?= $aid ?>"><?= e(t('Nota para la persona')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                <input class="input" id="appeal-accept-<?= $aid ?>" name="note" maxlength="255">
                <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('circle-check') ?> <?= e(t('Aceptar apelación')) ?></button>
            </form>
        </div>
    </details>
    <details class="admin-menu">
        <summary class="btn btn--ghost btn--sm"><?= icon('circle-x') ?> <?= e(t('Rechazar')) ?></summary>
        <div class="admin-menu__panel">
            <form method="post" action="<?= e($action) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="id" value="<?= $aid ?>">
                <input type="hidden" name="action" value="reject">
                <label class="field__label" for="appeal-reject-<?= $aid ?>"><?= e(t('Motivo (lo verá la persona)')) ?></label>
                <input class="input" id="appeal-reject-<?= $aid ?>" name="note" required minlength="5" maxlength="255">
                <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('circle-x') ?> <?= e(t('Rechazar apelación')) ?></button>
            </form>
        </div>
    </details>
</div>
