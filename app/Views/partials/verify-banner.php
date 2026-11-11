<?php /** @var array $viewer */ ?>
<div class="alert alert--warning" role="status">
    <?= icon('mail') ?>
    <p>
        <?= t('Confirma tu correo {email} para poder recuperar tu cuenta.', ['email' => '<strong>' . e($viewer['email']) . '</strong>']) ?>
        <a href="<?= e(url('settings.php', ['section' => 'account'])) ?>"><?= e(t('Reenviar enlace o cambiar correo')) ?></a>
    </p>
</div>
