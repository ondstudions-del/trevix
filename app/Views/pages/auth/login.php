<?php

use Trevix\Core\Config;

/**
 * @var array<string, string> $errors
 * @var array<string, string> $old
 */
?>
<section class="auth-card">
    <header class="auth-card__head">
        <h1><?= e(t('Bienvenido de nuevo')) ?></h1>
        <p><?= e(t('Inicia sesión para continuar en TREVIX.')) ?></p>
    </header>

    <?php if (isset($errors['form'])): ?>
        <div class="alert alert--error" role="alert">
            <?= icon('triangle-alert') ?>
            <p>
                <?= e(t($errors['form'])) ?>
                <?php if (isset($errors['suspended'])): ?>
                    <a href="<?= e(url('appeal.php')) ?>"><?= e(t('Apelar la suspensión')) ?></a>
                <?php endif; ?>
            </p>
        </div>
    <?php endif; ?>

    <form class="form" method="post" action="<?= e(url('login.php')) ?>" novalidate data-validate>
        <?= csrf_field() ?>

        <div class="field">
            <label class="field__label" for="identifier"><?= e(t('Correo o nombre de usuario')) ?></label>
            <div class="input-wrap">
                <?= icon('at-sign') ?>
                <input class="input" id="identifier" name="identifier" type="text" autocomplete="username" required maxlength="190"
                    data-rule="required" placeholder="<?= e(t('tu@correo.com o usuario')) ?>" value="<?= e($old['identifier'] ?? '') ?>"
                    spellcheck="false" autocapitalize="none"<?= invalid_attrs($errors, 'identifier', 'identifier') ?>>
            </div>
            <?= field_error($errors, 'identifier', 'identifier') ?>
        </div>

        <div class="field">
            <div class="field__row">
                <label class="field__label" for="password"><?= e(t('Contraseña')) ?></label>
                <a class="link-sm" href="<?= e(url('forgot-password.php')) ?>"><?= e(t('¿Olvidaste tu contraseña?')) ?></a>
            </div>
            <div class="input-wrap">
                <?= icon('lock') ?>
                <input class="input" id="password" name="password" type="password" autocomplete="current-password" required maxlength="200"
                    data-rule="required" placeholder="<?= e(t('Tu contraseña')) ?>">
                <button type="button" class="input-wrap__action" data-toggle-password aria-label="<?= e(t('Mostrar contraseña')) ?>" aria-pressed="false">
                    <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
                </button>
            </div>
            <?= field_error($errors, 'password', 'password') ?>
        </div>

        <button class="btn btn--primary btn--lg btn--block" type="submit"><?= e(t('Iniciar sesión')) ?></button>
    </form>

    <p class="auth-card__switch"><?= e(t('¿No tienes cuenta?')) ?> <a href="<?= e(url('register.php')) ?>"><?= e(t('Crea una gratis')) ?></a></p>

    <?php if (Config::previewEnabled()): ?>
        <div class="divider"><span><?= e(t('o')) ?></span></div>
        <a class="btn btn--glass btn--block" href="<?= e(url('feed.php')) ?>"><?= icon('compass') ?> <?= e(t('Recorrer la vista previa')) ?></a>
    <?php endif; ?>
</section>
