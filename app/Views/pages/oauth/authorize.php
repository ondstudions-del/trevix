<?php
/**
 * Consentimiento OAuth: la app solo recibe foto, usuario, nombre y acceso a la plataforma.
 *
 * @var array  $app
 * @var string $clientId
 * @var string $redirectUri
 * @var string $state
 * @var array  $user
 */
?>
<section class="auth-card">
    <header class="auth-card__head">
        <h1><?= e(t('Iniciar sesión con TREVIX')) ?></h1>
        <p><?= e(t('Esta app quiere usar tu cuenta de TREVIX.')) ?></p>
    </header>

    <div style="display:flex;gap:1rem;align-items:center;margin-bottom:1.25rem">
        <?php if (!empty($app['icon_url'])): ?>
            <img src="<?= e($app['icon_url']) ?>" alt="" width="56" height="56" style="border-radius:12px;object-fit:cover">
        <?php else: ?>
            <div style="width:56px;height:56px;border-radius:12px;background:rgba(255,255,255,.08);display:grid;place-items:center"><?= icon('app-window') ?></div>
        <?php endif; ?>
        <div>
            <strong><?= e($app['name'] ?? '') ?></strong>
            <p class="muted" style="margin:.25rem 0 0"><?= e($app['description'] ?? '') ?></p>
        </div>
    </div>

    <div class="alert alert--info" role="status">
        <?= icon('shield-check') ?>
        <p><?= e(t('TREVIX solo compartirá: foto de perfil, nombre de usuario, nombre visible y acceso a la plataforma. Nunca la contraseña ni datos cifrados.')) ?></p>
    </div>

    <p class="muted" style="margin:1rem 0">
        <?= e(t('Conectado como')) ?>
        <strong>@<?= e($user['username'] ?? '') ?></strong>
        (<?= e($user['display_name'] ?? '') ?>)
    </p>

    <form class="form" method="post" action="<?= e(url('oauth/authorize.php', [
        'client_id' => $clientId,
        'redirect_uri' => $redirectUri,
        'state' => $state !== '' ? $state : null,
    ])) ?>">
        <?= csrf_field() ?>
        <button class="btn btn--primary btn--lg btn--block" type="submit" name="action" value="allow"><?= e(t('Permitir')) ?></button>
        <button class="btn btn--glass btn--block" type="submit" name="action" value="deny" style="margin-top:.75rem"><?= e(t('Cancelar')) ?></button>
    </form>
</section>
