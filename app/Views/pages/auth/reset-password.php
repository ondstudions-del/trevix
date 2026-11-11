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
            <h1><?= e(t('Enlace no válido')) ?></h1>
            <p><?= e(t('Este enlace para restablecer la contraseña ya se usó o venció. Por seguridad, cada enlace funciona una sola vez durante un tiempo limitado.')) ?></p>
        </header>
        <a class="btn btn--primary btn--lg btn--block" href="<?= e(url('forgot-password.php')) ?>"><?= e(t('Solicitar un enlace nuevo')) ?></a>
    <?php else: ?>
        <header class="auth-card__head">
            <span class="auth-card__icon"><?= icon('key-round') ?></span>
            <h1><?= e(t('Crea una nueva contraseña')) ?></h1>
            <p><?= e(t('Al guardarla se cerrarán las sesiones abiertas en todos tus dispositivos.')) ?></p>
        </header>

        <form class="form" method="post" action="<?= e(url('reset-password.php')) ?>" novalidate data-validate>
            <?= csrf_field() ?>
            <input type="hidden" name="token" value="<?= e($token) ?>">

            <div class="field">
                <label class="field__label" for="new-password"><?= e(t('Nueva contraseña')) ?></label>
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

            <button class="btn btn--primary btn--lg btn--block" type="submit"><?= e(t('Guardar contraseña')) ?></button>
        </form>
    <?php endif; ?>

    <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver a iniciar sesión')) ?></a></p>
</section>
