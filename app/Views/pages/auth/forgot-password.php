<?php
/**
 * @var array<string, string> $errors
 * @var array<string, string> $old
 */
?>
<section class="auth-card">
    <header class="auth-card__head">
        <span class="auth-card__icon"><?= icon('key-round') ?></span>
        <h1>Recupera tu contraseña</h1>
        <p>Escribe el correo de tu cuenta y te enviaremos un enlace seguro para crear una nueva contraseña.</p>
    </header>

    <?php if (isset($errors['form'])): ?>
        <div class="alert alert--error" role="alert">
            <?= icon('triangle-alert') ?>
            <p><?= e($errors['form']) ?></p>
        </div>
    <?php endif; ?>

    <form class="form" method="post" action="<?= e(url('forgot-password.php')) ?>" novalidate data-validate>
        <?= csrf_field() ?>
        <div class="field">
            <label class="field__label" for="email">Correo electrónico</label>
            <div class="input-wrap">
                <?= icon('mail') ?>
                <input class="input" id="email" name="email" type="email" autocomplete="email" required maxlength="190"
                    data-rule="email" placeholder="tu@correo.com" value="<?= e($old['email'] ?? '') ?>"
                    spellcheck="false" autocapitalize="none"<?= invalid_attrs($errors, 'email', 'email') ?>>
            </div>
            <?= field_error($errors, 'email', 'email') ?>
        </div>
        <button class="btn btn--primary btn--lg btn--block" type="submit">Enviar enlace</button>
    </form>

    <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= icon('arrow-left') ?> Volver a iniciar sesión</a></p>
</section>
