<?php
/**
 * @var string $message
 * @var string $notice  aviso general configurado en el panel
 */
?>
<section class="auth-card auth-card--center">
    <p class="error-code text-gradient">503</p>
    <h1><?= e(t('Estamos en mantenimiento')) ?></h1>
    <p class="auth-card__lead"><?= e(t((string) $message)) ?></p>
    <?php if ($notice !== ''): ?>
        <div class="alert alert--info" role="status"><?= icon('megaphone') ?><p><?= e($notice) ?></p></div>
    <?php endif; ?>
    <div class="auth-card__actions">
        <form method="post" action="<?= e(url('logout.php')) ?>">
            <?= csrf_field() ?>
            <button type="submit" class="btn btn--ghost"><?= icon('log-out') ?> <?= e(t('Cerrar sesión')) ?></button>
        </form>
    </div>
</section>
