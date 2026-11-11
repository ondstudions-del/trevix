<?php

use Trevix\Services\AppealService;

/**
 * Apelar una suspensión o un baneo: la cuenta no puede iniciar sesión, así que se identifica con su usuario y contraseña.
 *
 * @var bool                  $sent
 * @var array<string, string> $errors
 * @var array<string, string> $old
 */
?>
<section class="auth-card">
    <header class="auth-card__head">
        <span class="auth-card__icon"><?= icon('scale') ?></span>
        <h1><?= e(t('Apelar una suspensión')) ?></h1>
        <p><?= e(t('Si crees que suspendieron o banearon tu cuenta por error, cuéntanos qué pasó. El equipo de TREVIX revisará tu caso y te responderá por correo.')) ?></p>
    </header>

    <?php if ($sent): ?>
        <div class="alert alert--success" role="status">
            <?= icon('circle-check') ?>
            <p><?= e(t('Recibimos tu apelación. Te escribiremos al correo de tu cuenta cuando el equipo la revise.')) ?></p>
        </div>
        <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver a iniciar sesión')) ?></a></p>
    <?php else: ?>
        <?php if (isset($errors['form'])): ?>
            <div class="alert alert--error" role="alert">
                <?= icon('triangle-alert') ?>
                <p><?= e(t($errors['form'])) ?></p>
            </div>
        <?php endif; ?>

        <form class="form" method="post" action="<?= e(url('appeal.php')) ?>" novalidate data-validate>
            <?= csrf_field() ?>
            <div class="field">
                <label class="field__label" for="identifier"><?= e(t('Correo o nombre de usuario')) ?></label>
                <div class="input-wrap">
                    <?= icon('at-sign') ?>
                    <input class="input" id="identifier" name="identifier" type="text" autocomplete="username" required maxlength="190"
                        data-rule="required" value="<?= e($old['identifier'] ?? '') ?>" spellcheck="false" autocapitalize="none"<?= invalid_attrs($errors, 'identifier', 'identifier') ?>>
                </div>
            </div>
            <div class="field">
                <label class="field__label" for="password"><?= e(t('Contraseña')) ?></label>
                <div class="input-wrap">
                    <?= icon('lock') ?>
                    <input class="input" id="password" name="password" type="password" autocomplete="current-password" required maxlength="200" data-rule="required">
                    <button type="button" class="input-wrap__action" data-toggle-password aria-label="<?= e(t('Mostrar contraseña')) ?>" aria-pressed="false">
                        <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
                    </button>
                </div>
                <p class="field__hint"><?= e(t('Solo la usamos para confirmar que la cuenta es tuya; no inicia sesión.')) ?></p>
            </div>
            <div class="field">
                <label class="field__label" for="appeal-message"><?= e(t('¿Por qué debería revisarse?')) ?></label>
                <textarea class="input textarea" id="appeal-message" name="message" rows="5" required data-rule="required"
                    minlength="<?= AppealService::MESSAGE_MIN ?>" maxlength="<?= AppealService::MESSAGE_MAX ?>"
                    placeholder="<?= e(t('Explica con detalle lo que pasó (mínimo {n} caracteres).', ['n' => AppealService::MESSAGE_MIN])) ?>"<?= invalid_attrs($errors, 'message', 'appeal-message') ?>><?= e($old['message'] ?? '') ?></textarea>
                <?= field_error($errors, 'message', 'appeal-message') ?>
            </div>
            <button class="btn btn--primary btn--lg btn--block" type="submit"><?= icon('send') ?> <?= e(t('Enviar apelación')) ?></button>
        </form>

        <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver a iniciar sesión')) ?></a></p>
    <?php endif; ?>
</section>
