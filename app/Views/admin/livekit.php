<?php

/**
 * @var array $livekit
 * @var array|null $staff
 */
$action = url('admin/livekit.php');
$disabled = $staff === null ? ' disabled' : '';
$lk = $livekit;
$source = $lk['source'] ?? 'none';
?>
<section class="panel">
    <header class="panel__head">
        <h2><?= icon('video') ?> <?= e(t('LiveKit en TREVIX')) ?></h2>
        <span class="chip <?= ($lk['configured'] ?? false) ? 'chip--success' : 'chip--muted' ?>">
            <?= e(($lk['configured'] ?? false) ? t('Conectado') : t('Sin configurar')) ?>
        </span>
    </header>
    <p class="content-row__muted">
        <?= e(t('Credenciales del proyecto en livekit.io o de tu servidor propio. La app solo recibe la URL wss:// y pide tokens firmados en este servidor; el API Secret nunca sale del backend.')) ?>
        <?php if ($source === 'file'): ?>
            <span class="chip chip--brand"><?= e(t('Usando archivo en el servidor')) ?></span>
        <?php endif; ?>
    </p>
    <form class="admin-settings" method="post" action="<?= e($action) ?>">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="save">
        <fieldset class="admin-settings__body"<?= $disabled ?>>
            <legend class="sr-only"><?= e(t('Credenciales LiveKit')) ?></legend>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="livekit-url"><?= e(t('URL WebSocket')) ?></label>
                <input class="input" id="livekit-url" name="livekit_url" required maxlength="200" autocomplete="off"
                    value="<?= e($lk['url'] ?? '') ?>" placeholder="wss://tu-proyecto.livekit.cloud">
            </div>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="livekit-api-key"><?= e(t('API Key')) ?></label>
                <input class="input" id="livekit-api-key" name="livekit_api_key" required maxlength="80" autocomplete="off"
                    value="<?= e($lk['api_key'] ?? '') ?>">
            </div>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="livekit-api-secret"><?= e(t('API Secret')) ?></label>
                <input class="input" id="livekit-api-secret" name="livekit_api_secret" type="password" maxlength="120" autocomplete="new-password"
                    placeholder="<?= e(($lk['has_secret'] ?? false) ? t('Vacío = conservar el actual') : t('Obligatorio la primera vez')) ?>">
            </div>
            <div class="field admin-setting admin-setting--stack">
                <span class="admin-setting__title"><?= e(t('Funciones visibles en la app')) ?></span>
                <label class="check">
                    <input type="checkbox" name="livekit_calls_audio" value="1"<?= ($lk['audio'] ?? true) ? ' checked' : '' ?>>
                    <?= e(t('Llamadas de audio (1:1)')) ?>
                </label>
                <label class="check">
                    <input type="checkbox" name="livekit_calls_video" value="1"<?= ($lk['video'] ?? true) ? ' checked' : '' ?>>
                    <?= e(t('Videollamadas (1:1)')) ?>
                </label>
                <label class="check">
                    <input type="checkbox" name="livekit_live_broadcast" value="1"<?= ($lk['live'] ?? true) ? ' checked' : '' ?>>
                    <?= e(t('Live (emisión pública)')) ?>
                </label>
            </div>
        </fieldset>
        <footer class="admin-settings__footer">
            <button type="submit" class="btn btn--primary"<?= $disabled ?>><?= icon('check') ?> <?= e(t('Guardar LiveKit')) ?></button>
        </footer>
    </form>
</section>

<section class="panel">
    <header class="panel__head">
        <h2><?= icon('info') ?> <?= e(t('Siguiente paso en el servidor')) ?></h2>
    </header>
    <p class="content-row__muted"><?= e(t('Ejecuta la migración 042 (live_sessions) en la base de datos. Documentación: docs/LIVEKIT.md en el repositorio.')) ?></p>
</section>