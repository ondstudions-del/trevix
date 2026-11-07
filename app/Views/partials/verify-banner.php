<?php /** @var array $viewer */ ?>
<div class="alert alert--warning" role="status">
    <?= icon('mail') ?>
    <p>
        Confirma tu correo <strong><?= e($viewer['email']) ?></strong> para poder recuperar tu cuenta.
        <a href="<?= e(url('settings.php', ['section' => 'account'])) ?>">Reenviar enlace o cambiar correo</a>
    </p>
</div>
