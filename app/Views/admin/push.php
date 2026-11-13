<?php

use Trevix\Controllers\Admin\PushController;
use Trevix\Models\PushCampaign;

/**
 * Avisos push por Firebase Cloud Messaging: teléfonos registrados, envío a una persona o masivo y envíos recientes.
 *
 * @var bool       $configured  hay cuenta de servicio de Firebase en el servidor
 * @var array|null $client      Fcm::clientConfig() (null si faltan los datos de las apps)
 * @var array|null $stats       PushDevice::stats()
 * @var array      $campaigns   PushCampaign::recent()
 * @var array|null $staff
 */
$action = url('admin/push.php');
$disabled = $staff === null || !$configured ? ' disabled' : '';
$cards = [
    ['smartphone', t('Teléfonos Android'), 'android'],
    ['smartphone', t('iPhone'), 'ios'],
    ['users', t('Personas con avisos'), 'users'],
    ['triangle-alert', t('Teléfonos con errores'), 'failing'],
];
$statusLabel = [
    'sending' => [t('Enviando'), 'chip--brand'],
    'done'    => [t('Enviado'), 'chip--success'],
    'failed'  => [t('Falló'), 'chip--danger'],
];
?>
<section class="stat-grid" aria-label="<?= e(t('Resumen de avisos push')) ?>">
    <?php foreach ($cards as [$iconName, $label, $key]): ?>
        <article class="stat-card">
            <span class="stat-card__icon"><?= icon($iconName) ?></span>
            <p class="stat-card__label"><?= e($label) ?></p>
            <p class="stat-card__value"><?= $stats !== null ? e(compact_number($stats[$key])) : '—' ?></p>
            <p class="stat-card__hint"><?= e($stats !== null ? t('Datos en tiempo real') : t('Se calcula al conectar la base de datos')) ?></p>
        </article>
    <?php endforeach; ?>
</section>

<?php if (!$configured || $client === null || $client['android'] === null || $client['ios'] === null): ?>
    <section class="panel">
        <header class="panel__head">
            <h2><?= icon('triangle-alert') ?> <?= e(t('Configuración de Firebase')) ?></h2>
        </header>
        <ul class="content-list">
            <li class="content-row">
                <div class="content-row__body">
                    <p class="content-row__author">
                        <strong><?= e(t('Cuenta de servicio')) ?></strong>
                        <span class="chip <?= $configured ? 'chip--success' : 'chip--muted' ?>"><?= e($configured ? t('Lista') : t('Falta')) ?></span>
                    </p>
                    <p class="content-row__muted"><?= e(t('El JSON de la cuenta de servicio del proyecto de Firebase va solo en el servidor (storage/private/firebase.json) y su ruta en config/local.php, en push.fcm.service_account.')) ?></p>
                </div>
            </li>
            <?php foreach (['android' => 'Android', 'ios' => 'iPhone'] as $platform => $name): ?>
                <li class="content-row">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <strong><?= e(t('App de {platform}', ['platform' => $name])) ?></strong>
                            <span class="chip <?= ($client[$platform] ?? null) !== null ? 'chip--success' : 'chip--muted' ?>"><?= e(($client[$platform] ?? null) !== null ? t('Lista') : t('Falta')) ?></span>
                        </p>
                        <p class="content-row__muted"><?= e(t('Identificador de la app y clave de API de Firebase (push.fcm.{platform}) y el número del proyecto (push.fcm.sender_id) en config/local.php.', ['platform' => $platform])) ?></p>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
        <p class="content-row__muted"><?= e(t('Mientras falte algo, la app sigue avisando con su sistema propio (servicio de Android y revisión periódica en iPhone). Para iPhone también hay que subir la clave de APNs de Apple en la configuración de Cloud Messaging de Firebase.')) ?></p>
    </section>
<?php endif; ?>

<section class="panel">
    <header class="panel__head">
        <h2><?= icon('send') ?> <?= e(t('Enviar un aviso')) ?></h2>
    </header>
    <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Enviar este aviso ahora? No se puede deshacer.')) ?>">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="send">
        <label class="field__label" for="push-audience"><?= e(t('Para')) ?></label>
        <select class="input" id="push-audience" name="audience">
            <?php foreach (PushController::AUDIENCES as $key => $label): ?>
                <option value="<?= e($key) ?>"><?= e(t($label)) ?></option>
            <?php endforeach; ?>
        </select>
        <label class="field__label" for="push-username"><?= e(t('Nombre de usuario (solo para «Una persona»)')) ?></label>
        <input class="input" id="push-username" name="username" maxlength="31" placeholder="@usuario" autocomplete="off">
        <label class="field__label" for="push-title"><?= e(t('Título')) ?></label>
        <input class="input" id="push-title" name="title" required maxlength="80" placeholder="<?= e(t('Novedades en TREVIX')) ?>">
        <label class="field__label" for="push-body"><?= e(t('Texto')) ?></label>
        <textarea class="input" id="push-body" name="body" required maxlength="240" rows="3" placeholder="<?= e(t('Escribe el mensaje que verán en la notificación')) ?>"></textarea>
        <label class="field__label" for="push-link"><?= e(t('Pantalla que abre (opcional)')) ?></label>
        <input class="input" id="push-link" name="link" maxlength="255" placeholder="post.php?id=5" autocomplete="off">
        <p class="content-row__muted"><?= e(t('Una página de TREVIX (post.php?id=5, profile.php?u=nombre, events.php…). Vacío abre la app en el inicio.')) ?></p>
        <button type="submit" class="btn btn--primary btn--block"<?= $disabled ?>><?= icon('send') ?> <?= e(t('Enviar aviso')) ?></button>
    </form>
</section>

<section class="panel">
    <header class="panel__head">
        <h2><?= icon('history') ?> <?= e(t('Envíos recientes')) ?></h2>
    </header>
    <?php if ($campaigns === []): ?>
        <div class="panel__empty">
            <?= icon('bell-ring') ?>
            <p><?= e(t('Todavía no se ha enviado ningún aviso desde el panel.')) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($campaigns as $c): ?>
                <?php [$label, $chip] = $statusLabel[$c['status']] ?? [$c['status'], 'chip--muted']; ?>
                <li class="content-row">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <strong><?= e($c['title']) ?></strong>
                            <span class="chip <?= e($chip) ?>"><?= e($label) ?></span>
                            <span class="chip chip--muted"><?= e($c['audience'] === 'user'
                                ? '@' . ($c['target_username'] ?? '—')
                                : t(PushController::AUDIENCES[$c['audience']] ?? $c['audience'])) ?></span>
                        </p>
                        <p class="content-row__muted"><?= e($c['body']) ?></p>
                        <p class="content-row__muted">
                            <?= e(t('{sent} entregados a Firebase · {failed} fallidos · {total} teléfonos', [
                                'sent' => (int) $c['sent'], 'failed' => (int) $c['failed'], 'total' => (int) $c['total'],
                            ])) ?>
                            · <?= e('@' . ($c['admin_username'] ?? '—')) ?> · <?= e(time_ago((string) $c['created_at'])) ?>
                            <?php if ($c['link'] !== null): ?> · <?= e($c['link']) ?><?php endif; ?>
                        </p>
                        <?php if ($c['error'] !== null): ?><p class="content-row__muted"><?= e($c['error']) ?></p><?php endif; ?>
                    </div>
                    <?php if (PushCampaign::stalled($c)): ?>
                        <div class="content-row__actions">
                            <form method="post" action="<?= e($action) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="resume">
                                <input type="hidden" name="id" value="<?= (int) $c['id'] ?>">
                                <button type="submit" class="btn btn--ghost btn--sm"<?= $disabled ?>><?= icon('refresh-cw') ?> <?= e(t('Continuar')) ?></button>
                            </form>
                        </div>
                    <?php endif; ?>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>
