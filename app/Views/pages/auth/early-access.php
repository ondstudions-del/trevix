<?php
/**
 * Solicitar acceso anticipado a la app de Android.
 *
 * @var bool                  $sent
 * @var array<string, string> $errors
 * @var array<string, string> $old
 */
?>
<section class="auth-card">
    <header class="auth-card__head">
        <span class="auth-card__icon"><?= icon('smartphone') ?></span>
        <h1><?= e(t('Acceso anticipado para Android')) ?></h1>
        <p><?= e(t('Prueba la app de TREVIX antes del lanzamiento oficial. Déjanos tu nombre y el correo de tu cuenta de Google: el equipo te añadirá a la lista de verificadores y te enviará el enlace para instalarla.')) ?></p>
    </header>

    <?php if ($sent): ?>
        <div class="alert alert--success" role="status">
            <?= icon('circle-check') ?>
            <p><?= e(t('Recibimos tu solicitud. Cuando el equipo te añada a la lista de verificadores te escribiremos a ese correo con el enlace y los pasos para instalar la app.')) ?></p>
        </div>
        <p class="auth-card__switch"><a href="<?= e(url()) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver al inicio')) ?></a></p>
    <?php else: ?>
        <?php if (isset($errors['form'])): ?>
            <div class="alert alert--error" role="alert">
                <?= icon('triangle-alert') ?>
                <p><?= e(t($errors['form'])) ?></p>
            </div>
        <?php endif; ?>

        <form class="form" method="post" action="<?= e(url('early-access.php')) ?>" novalidate data-validate>
            <?= csrf_field() ?>
            <div class="field">
                <label class="field__label" for="full_name"><?= e(t('Nombre')) ?></label>
                <div class="input-wrap">
                    <?= icon('user') ?>
                    <input class="input" id="full_name" name="full_name" type="text" autocomplete="name" required minlength="2" maxlength="120"
                        data-rule="required" value="<?= e($old['full_name'] ?? '') ?>"<?= invalid_attrs($errors, 'full_name', 'full_name') ?>>
                </div>
                <?= field_error($errors, 'full_name', 'full_name') ?>
            </div>
            <div class="field">
                <label class="field__label" for="email"><?= e(t('Correo de Google')) ?></label>
                <div class="input-wrap">
                    <?= icon('mail') ?>
                    <input class="input" id="email" name="email" type="email" autocomplete="email" required maxlength="190"
                        data-rule="required|email" value="<?= e($old['email'] ?? '') ?>" spellcheck="false" autocapitalize="none"<?= invalid_attrs($errors, 'email', 'email') ?>>
                </div>
                <p class="field__hint"><?= e(t('Usa el mismo correo con el que entras en Google Play.')) ?></p>
                <?= field_error($errors, 'email', 'email') ?>
            </div>
            <button class="btn btn--primary btn--lg btn--block" type="submit"><?= icon('send') ?> <?= e(t('Pedir acceso anticipado')) ?></button>
        </form>

        <p class="auth-card__switch"><a href="<?= e(url()) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver al inicio')) ?></a></p>
    <?php endif; ?>
</section>
