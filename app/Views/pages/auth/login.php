<?php

use Trevix\Core\Config;

/**
 * @var array<string, string> $errors
 * @var array<string, string> $old
 */
?>
<section class="auth-card">
    <header class="auth-card__head">
        <h1>Bienvenido de nuevo</h1>
        <p>Inicia sesión para continuar en TREVIX.</p>
    </header>

    <?php if (isset($errors['form'])): ?>
        <div class="alert alert--error" role="alert">
            <?= icon('triangle-alert') ?>
            <p><?= e($errors['form']) ?></p>
        </div>
    <?php endif; ?>

    <form class="form" method="post" action="<?= e(url('login.php')) ?>" novalidate data-validate>
        <?= csrf_field() ?>

        <div class="field">
            <label class="field__label" for="identifier">Correo o nombre de usuario</label>
            <div class="input-wrap">
                <?= icon('at-sign') ?>
                <input class="input" id="identifier" name="identifier" type="text" autocomplete="username" required maxlength="190"
                    data-rule="required" placeholder="tu@correo.com o usuario" value="<?= e($old['identifier'] ?? '') ?>"
                    spellcheck="false" autocapitalize="none"<?= invalid_attrs($errors, 'identifier', 'identifier') ?>>
            </div>
            <?= field_error($errors, 'identifier', 'identifier') ?>
        </div>

        <div class="field">
            <div class="field__row">
                <label class="field__label" for="password">Contraseña</label>
                <a class="link-sm" href="<?= e(url('forgot-password.php')) ?>">¿Olvidaste tu contraseña?</a>
            </div>
            <div class="input-wrap">
                <?= icon('lock') ?>
                <input class="input" id="password" name="password" type="password" autocomplete="current-password" required maxlength="200"
                    data-rule="required" placeholder="Tu contraseña">
                <button type="button" class="input-wrap__action" data-toggle-password aria-label="Mostrar contraseña" aria-pressed="false">
                    <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
                </button>
            </div>
            <?= field_error($errors, 'password', 'password') ?>
        </div>

        <button class="btn btn--primary btn--lg btn--block" type="submit">Iniciar sesión</button>
    </form>

    <p class="auth-card__switch">¿No tienes cuenta? <a href="<?= e(url('register.php')) ?>">Crea una gratis</a></p>

    <?php if (Config::previewEnabled()): ?>
        <div class="divider"><span>o</span></div>
        <a class="btn btn--glass btn--block" href="<?= e(url('feed.php')) ?>"><?= icon('compass') ?> Recorrer la vista previa</a>
    <?php endif; ?>
</section>
