<?php
/**
 * @var bool                  $closed       registro cerrado desde el panel (o mantenimiento)
 * @var bool                  $maintenance
 * @var int                   $passwordMin
 * @var array<string, string> $errors
 * @var array<string, string> $old
 */
?>
<section class="auth-card auth-card--wide">
    <header class="auth-card__head">
        <h1><?= e(t('Crea tu cuenta')) ?></h1>
        <p><?= e(t('Únete a TREVIX y empieza a conectar en minutos.')) ?></p>
    </header>

    <?php if ($closed): ?>
        <div class="alert alert--info" role="status">
            <?= icon($maintenance ? 'wrench' : 'lock') ?>
            <p><?= $maintenance
                ? '<strong>' . e(t('TREVIX está en mantenimiento.')) . '</strong> ' . e(t('El registro volverá a estar disponible en breve.'))
                : '<strong>' . e(t('El registro está cerrado por ahora.')) . '</strong> ' . e(t('Si ya tienes una cuenta, puedes iniciar sesión.')) ?></p>
        </div>
    <?php else: ?>
    <?php if (isset($errors['form'])): ?>
        <div class="alert alert--error" role="alert">
            <?= icon('triangle-alert') ?>
            <p><?= e(t($errors['form'])) ?></p>
        </div>
    <?php endif; ?>

    <form class="form" method="post" action="<?= e(url('register.php')) ?>" novalidate data-validate>
        <?= csrf_field() ?>

        <div class="form__grid">
            <div class="field">
                <label class="field__label" for="display_name"><?= e(t('Nombre')) ?></label>
                <div class="input-wrap">
                    <?= icon('user') ?>
                    <input class="input" id="display_name" name="display_name" type="text" autocomplete="name" required minlength="2" maxlength="60"
                        data-rule="name" placeholder="<?= e(t('Tu nombre')) ?>" value="<?= e($old['display_name'] ?? '') ?>"<?= invalid_attrs($errors, 'display_name', 'display_name') ?>>
                </div>
                <?= field_error($errors, 'display_name', 'display_name') ?>
            </div>

            <div class="field">
                <label class="field__label" for="username"><?= e(t('Nombre de usuario')) ?></label>
                <div class="input-wrap input-wrap--prefix">
                    <span class="input-wrap__prefix">@</span>
                    <input class="input" id="username" name="username" type="text" autocomplete="username" required minlength="3" maxlength="30"
                        pattern="[a-z0-9_.]{3,30}" data-rule="username" data-username-input placeholder="<?= e(t('usuario')) ?>" spellcheck="false" autocapitalize="none"
                        value="<?= e($old['username'] ?? '') ?>"<?= invalid_attrs($errors, 'username', 'username') ?>>
                </div>
                <p class="field__hint"><?= e(t('3 a 30 caracteres: letras minúsculas, números, punto o guion bajo.')) ?></p>
                <?= field_error($errors, 'username', 'username') ?>
            </div>
        </div>

        <div class="form__grid">
            <div class="field">
                <label class="field__label" for="email"><?= e(t('Correo electrónico')) ?></label>
                <div class="input-wrap">
                    <?= icon('mail') ?>
                    <input class="input" id="email" name="email" type="email" autocomplete="email" required maxlength="190"
                        data-rule="email" placeholder="<?= e(t('tu@correo.com')) ?>" value="<?= e($old['email'] ?? '') ?>"<?= invalid_attrs($errors, 'email', 'email') ?>>
                </div>
                <?= field_error($errors, 'email', 'email') ?>
            </div>

            <div class="field">
                <label class="field__label" for="birth_date"><?= e(t('Fecha de nacimiento')) ?></label>
                <div class="input-wrap">
                    <?= icon('cake') ?>
                    <input class="input" id="birth_date" name="birth_date" type="date" required max="<?= e(date('Y-m-d')) ?>" data-rule="birthdate"
                        value="<?= e($old['birth_date'] ?? '') ?>"<?= invalid_attrs($errors, 'birth_date', 'birth_date') ?>>
                </div>
                <?= field_error($errors, 'birth_date', 'birth_date') ?>
            </div>
        </div>

        <div class="field">
            <label class="field__label" for="new-password"><?= e(t('Contraseña')) ?></label>
            <div class="input-wrap">
                <?= icon('lock') ?>
                <input class="input" id="new-password" name="password" type="password" autocomplete="new-password" required
                    minlength="<?= $passwordMin ?>" maxlength="128" data-rule="password" data-strength-meter="#password-strength"
                    placeholder="<?= e(t('Mínimo {n} caracteres', ['n' => $passwordMin])) ?>"<?= invalid_attrs($errors, 'password', 'new-password') ?>>
                <button type="button" class="input-wrap__action" data-toggle-password aria-label="<?= e(t('Mostrar contraseña')) ?>" aria-pressed="false">
                    <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
                </button>
            </div>
            <div class="strength" id="password-strength" data-level="0">
                <div class="strength__bars" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
                <span class="strength__label" aria-live="polite"><?= e(t('Escribe una contraseña')) ?></span>
            </div>
            <ul class="requirements" data-requirements-for="new-password">
                <li data-req="length"><?= icon('check') ?> <?= e(t('Al menos {n} caracteres', ['n' => $passwordMin])) ?></li>
                <li data-req="case"><?= icon('check') ?> <?= e(t('Mayúsculas y minúsculas')) ?></li>
                <li data-req="number"><?= icon('check') ?> <?= e(t('Al menos un número')) ?></li>
                <li data-req="symbol"><?= icon('check') ?> <?= e(t('Al menos un símbolo')) ?></li>
            </ul>
            <?= field_error($errors, 'password', 'new-password') ?>
        </div>

        <div class="field">
            <label class="field__label" for="password_confirmation"><?= e(t('Confirmar contraseña')) ?></label>
            <div class="input-wrap">
                <?= icon('lock-keyhole') ?>
                <input class="input" id="password_confirmation" name="password_confirmation" type="password" autocomplete="new-password" required
                    maxlength="128" data-rule="confirm" data-confirm="#new-password" placeholder="<?= e(t('Repite la contraseña')) ?>"<?= invalid_attrs($errors, 'password_confirmation', 'password_confirmation') ?>>
            </div>
            <?= field_error($errors, 'password_confirmation', 'password_confirmation') ?>
        </div>

        <div class="field">
            <label class="checkbox">
                <input type="checkbox" name="terms" value="1" required data-rule="terms" id="terms"<?= invalid_attrs($errors, 'terms', 'terms') ?>>
                <span class="checkbox__box"><?= icon('check') ?></span>
                <span><?= e(t('Acepto los')) ?> <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>" target="_blank" rel="noopener"><?= e(t('Términos y condiciones')) ?></a>
                    <?= e(t('y la')) ?> <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>" target="_blank" rel="noopener"><?= e(t('Política de privacidad')) ?></a>.</span>
            </label>
            <?= field_error($errors, 'terms', 'terms') ?>
        </div>

        <button class="btn btn--primary btn--lg btn--block" type="submit"><?= e(t('Crear cuenta')) ?></button>
    </form>
    <?php endif; ?>

    <p class="auth-card__switch"><?= e(t('¿Ya tienes cuenta?')) ?> <a href="<?= e(url('login.php')) ?>"><?= e(t('Inicia sesión')) ?></a></p>
</section>
