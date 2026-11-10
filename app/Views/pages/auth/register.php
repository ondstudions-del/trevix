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
        <h1>Crea tu cuenta</h1>
        <p>Únete a TREVIX y empieza a conectar en minutos.</p>
    </header>

    <?php if ($closed): ?>
        <div class="alert alert--info" role="status">
            <?= icon($maintenance ? 'wrench' : 'lock') ?>
            <p><?= $maintenance
                ? '<strong>TREVIX está en mantenimiento.</strong> El registro volverá a estar disponible en breve.'
                : '<strong>El registro está cerrado por ahora.</strong> Si ya tienes una cuenta, puedes iniciar sesión.' ?></p>
        </div>
    <?php else: ?>
    <?php if (isset($errors['form'])): ?>
        <div class="alert alert--error" role="alert">
            <?= icon('triangle-alert') ?>
            <p><?= e($errors['form']) ?></p>
        </div>
    <?php endif; ?>

    <form class="form" method="post" action="<?= e(url('register.php')) ?>" novalidate data-validate>
        <?= csrf_field() ?>

        <div class="form__grid">
            <div class="field">
                <label class="field__label" for="display_name">Nombre</label>
                <div class="input-wrap">
                    <?= icon('user') ?>
                    <input class="input" id="display_name" name="display_name" type="text" autocomplete="name" required minlength="2" maxlength="60"
                        data-rule="name" placeholder="Tu nombre" value="<?= e($old['display_name'] ?? '') ?>"<?= invalid_attrs($errors, 'display_name', 'display_name') ?>>
                </div>
                <?= field_error($errors, 'display_name', 'display_name') ?>
            </div>

            <div class="field">
                <label class="field__label" for="username">Nombre de usuario</label>
                <div class="input-wrap input-wrap--prefix">
                    <span class="input-wrap__prefix">@</span>
                    <input class="input" id="username" name="username" type="text" autocomplete="username" required minlength="3" maxlength="30"
                        pattern="[a-z0-9_.]{3,30}" data-rule="username" data-username-input placeholder="usuario" spellcheck="false" autocapitalize="none"
                        value="<?= e($old['username'] ?? '') ?>"<?= invalid_attrs($errors, 'username', 'username') ?>>
                </div>
                <p class="field__hint">3 a 30 caracteres: letras minúsculas, números, punto o guion bajo.</p>
                <?= field_error($errors, 'username', 'username') ?>
            </div>
        </div>

        <div class="form__grid">
            <div class="field">
                <label class="field__label" for="email">Correo electrónico</label>
                <div class="input-wrap">
                    <?= icon('mail') ?>
                    <input class="input" id="email" name="email" type="email" autocomplete="email" required maxlength="190"
                        data-rule="email" placeholder="tu@correo.com" value="<?= e($old['email'] ?? '') ?>"<?= invalid_attrs($errors, 'email', 'email') ?>>
                </div>
                <?= field_error($errors, 'email', 'email') ?>
            </div>

            <div class="field">
                <label class="field__label" for="birth_date">Fecha de nacimiento</label>
                <div class="input-wrap">
                    <?= icon('cake') ?>
                    <input class="input" id="birth_date" name="birth_date" type="date" required max="<?= e(date('Y-m-d')) ?>" data-rule="birthdate"
                        value="<?= e($old['birth_date'] ?? '') ?>"<?= invalid_attrs($errors, 'birth_date', 'birth_date') ?>>
                </div>
                <?= field_error($errors, 'birth_date', 'birth_date') ?>
            </div>
        </div>

        <div class="field">
            <label class="field__label" for="new-password">Contraseña</label>
            <div class="input-wrap">
                <?= icon('lock') ?>
                <input class="input" id="new-password" name="password" type="password" autocomplete="new-password" required
                    minlength="<?= $passwordMin ?>" maxlength="128" data-rule="password" data-strength-meter="#password-strength"
                    placeholder="Mínimo <?= $passwordMin ?> caracteres"<?= invalid_attrs($errors, 'password', 'new-password') ?>>
                <button type="button" class="input-wrap__action" data-toggle-password aria-label="Mostrar contraseña" aria-pressed="false">
                    <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
                </button>
            </div>
            <div class="strength" id="password-strength" data-level="0">
                <div class="strength__bars" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
                <span class="strength__label" aria-live="polite">Escribe una contraseña</span>
            </div>
            <ul class="requirements" data-requirements-for="new-password">
                <li data-req="length"><?= icon('check') ?> Al menos <?= $passwordMin ?> caracteres</li>
                <li data-req="case"><?= icon('check') ?> Mayúsculas y minúsculas</li>
                <li data-req="number"><?= icon('check') ?> Al menos un número</li>
                <li data-req="symbol"><?= icon('check') ?> Al menos un símbolo</li>
            </ul>
            <?= field_error($errors, 'password', 'new-password') ?>
        </div>

        <div class="field">
            <label class="field__label" for="password_confirmation">Confirmar contraseña</label>
            <div class="input-wrap">
                <?= icon('lock-keyhole') ?>
                <input class="input" id="password_confirmation" name="password_confirmation" type="password" autocomplete="new-password" required
                    maxlength="128" data-rule="confirm" data-confirm="#new-password" placeholder="Repite la contraseña"<?= invalid_attrs($errors, 'password_confirmation', 'password_confirmation') ?>>
            </div>
            <?= field_error($errors, 'password_confirmation', 'password_confirmation') ?>
        </div>

        <div class="field">
            <label class="checkbox">
                <input type="checkbox" name="terms" value="1" required data-rule="terms" id="terms"<?= invalid_attrs($errors, 'terms', 'terms') ?>>
                <span class="checkbox__box"><?= icon('check') ?></span>
                <span>Acepto los <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>" target="_blank" rel="noopener">Términos y condiciones</a>
                    y la <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>" target="_blank" rel="noopener">Política de privacidad</a>.</span>
            </label>
            <?= field_error($errors, 'terms', 'terms') ?>
        </div>

        <button class="btn btn--primary btn--lg btn--block" type="submit">Crear cuenta</button>
    </form>
    <?php endif; ?>

    <p class="auth-card__switch">¿Ya tienes cuenta? <a href="<?= e(url('login.php')) ?>">Inicia sesión</a></p>
</section>
