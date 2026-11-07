<?php
/**
 * @var bool                  $valid
 * @var string                $token
 * @var int                   $passwordMin
 * @var array<string, string> $errors
 */
?>
<section class="auth-card">
    <?php if (!$valid): ?>
        <header class="auth-card__head">
            <span class="auth-card__icon"><?= icon('triangle-alert') ?></span>
            <h1>Enlace no válido</h1>
            <p>Este enlace para restablecer la contraseña ya se usó o venció. Por seguridad, cada enlace funciona una sola vez durante un tiempo limitado.</p>
        </header>
        <a class="btn btn--primary btn--lg btn--block" href="<?= e(url('forgot-password.php')) ?>">Solicitar un enlace nuevo</a>
    <?php else: ?>
        <header class="auth-card__head">
            <span class="auth-card__icon"><?= icon('key-round') ?></span>
            <h1>Crea una nueva contraseña</h1>
            <p>Al guardarla se cerrarán las sesiones abiertas en todos tus dispositivos.</p>
        </header>

        <form class="form" method="post" action="<?= e(url('reset-password.php')) ?>" novalidate data-validate>
            <?= csrf_field() ?>
            <input type="hidden" name="token" value="<?= e($token) ?>">

            <div class="field">
                <label class="field__label" for="new-password">Nueva contraseña</label>
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

            <button class="btn btn--primary btn--lg btn--block" type="submit">Guardar contraseña</button>
        </form>
    <?php endif; ?>

    <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= icon('arrow-left') ?> Volver a iniciar sesión</a></p>
</section>
