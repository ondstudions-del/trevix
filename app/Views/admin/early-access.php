<?php

use Trevix\Core\View;
use Trevix\Models\AndroidEarlyAccess;
use Trevix\Services\EarlyAccessService;

/**
 * Acceso anticipado Android: ajustes (URL + instrucciones) y cola de solicitudes.
 *
 * @var string $status
 * @var array  $counts
 * @var array  $requests
 * @var array  $settings
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 * @var bool $isPreview
 */
$action = url('admin/early-access.php');
$emptyTexts = [
    'pending'  => t('No hay solicitudes de acceso anticipado por revisar.'),
    'accepted' => t('Todavía no se aceptó ninguna solicitud.'),
    'rejected' => t('No hay solicitudes rechazadas.'),
];
?>
<form class="panel admin-settings" method="post" action="<?= e($action) ?>">
    <?= csrf_field() ?>
    <input type="hidden" name="action" value="save_settings">
    <header class="panel__head">
        <h2><?= icon('smartphone') ?> <?= e(t('Enlace e instrucciones')) ?></h2>
    </header>
    <fieldset class="admin-settings__body"<?= !empty($isPreview) ? ' disabled' : '' ?>>
        <legend class="sr-only"><?= e(t('Configuración del correo de testers')) ?></legend>
        <p class="content-row__muted">
            <?= e(t('Flujo: copia el correo de cada solicitud, añádelo en Google Play Console › Pruebas › Lista de verificadores, y luego pulsa «Ya es verificador» para enviarle el correo con el enlace.')) ?>
        </p>
        <div class="field admin-setting admin-setting--stack">
            <label class="admin-setting__title" for="android-tester-url"><?= e(t('URL de testers')) ?></label>
            <p class="admin-setting__text"><?= e(t('Enlace de la pista de prueba cerrada o de la lista de verificadores (debe empezar por https://).')) ?></p>
            <input class="input" id="android-tester-url" name="android_tester_url" type="url" maxlength="<?= EarlyAccessService::URL_MAX ?>"
                value="<?= e($settings['android_tester_url']) ?>" placeholder="https://play.google.com/apps/testing/…">
        </div>
        <div class="field admin-setting admin-setting--stack">
            <label class="admin-setting__title" for="android-tester-instructions"><?= e(t('Instrucciones del correo')) ?></label>
            <p class="admin-setting__text"><?= e(t('Una línea por paso. Se envían al aceptar (o reenviar) una solicitud.')) ?></p>
            <textarea class="input textarea" id="android-tester-instructions" name="android_tester_instructions" rows="7" maxlength="<?= EarlyAccessService::INSTRUCTIONS_MAX ?>"><?= e($settings['android_tester_instructions']) ?></textarea>
        </div>
    </fieldset>
    <footer class="admin-settings__footer">
        <button type="submit" class="btn btn--primary"<?= !empty($isPreview) ? ' disabled' : '' ?>><?= icon('check') ?> <?= e(t('Guardar ajustes')) ?></button>
        <a class="btn btn--ghost" href="<?= e(url('early-access.php')) ?>" target="_blank" rel="noopener"><?= icon('external-link') ?> <?= e(t('Ver página pública')) ?></a>
    </footer>
</form>

<nav class="admin-tabs" aria-label="<?= e(t('Estado de las solicitudes')) ?>">
    <?php foreach (AndroidEarlyAccess::STATUSES as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/early-access.php', ['status' => $key === 'pending' ? null : $key])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e($key === 'pending' ? t('Por revisar') : t($label . 's')) ?>
            <?php if (($counts[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $counts[$key] ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<section class="panel" aria-labelledby="early-access-queue">
    <header class="panel__head">
        <h2 id="early-access-queue"><?= icon('smartphone') ?> <?= e($status === 'pending' ? t('Por revisar') : t((AndroidEarlyAccess::STATUSES[$status] ?? $status) . 's')) ?></h2>
    </header>
    <?php if ($requests === []): ?>
        <div class="panel__empty">
            <?= icon('smartphone') ?>
            <p><?= e($emptyTexts[$status] ?? t('No hay solicitudes en esta lista.')) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($requests as $r): ?>
                <?php $rid = (int) $r['id']; ?>
                <li class="content-row" id="acceso-<?= $rid ?>">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <strong><?= e($r['full_name']) ?></strong>
                            <span class="chip"><?= e(t(AndroidEarlyAccess::STATUSES[$r['status']] ?? $r['status'])) ?></span>
                        </p>
                        <p class="content-row__text">
                            <a href="mailto:<?= e($r['email']) ?>"><?= e($r['email']) ?></a>
                            <button type="button" class="btn btn--ghost btn--sm" data-copy-text="<?= e($r['email']) ?>" aria-label="<?= e(t('Copiar correo')) ?>">
                                <?= icon('copy') ?> <?= e(t('Copiar')) ?>
                            </button>
                        </p>
                        <p class="content-row__muted">
                            <?= e(t('Solicitud')) ?> <?= time_tag((string) $r['created_at']) ?>
                            <?php if ($r['reviewed_at'] !== null): ?>
                                · <?= e(t('Revisada')) ?> <?= time_tag((string) $r['reviewed_at']) ?><?= $r['reviewer_username'] !== null ? ' ' . e(t('por @{username}', ['username' => $r['reviewer_username']])) : '' ?>
                            <?php endif; ?>
                            <?php if (!empty($r['resolution_note'])): ?> · «<?= e($r['resolution_note']) ?>»<?php endif; ?>
                        </p>
                    </div>
                    <div class="content-row__actions">
                        <?php if ($r['status'] === 'pending'): ?>
                            <details class="admin-menu">
                                <summary class="btn btn--primary btn--sm"><?= icon('circle-check') ?> <?= e(t('Ya es verificador')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Confirmas que ya añadiste este correo en Play Console? Se enviará el correo con el enlace de testers.')) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $rid ?>">
                                        <input type="hidden" name="action" value="accept">
                                        <label class="field">
                                            <span class="field__label"><?= e(t('Nota interna (opcional)')) ?></span>
                                            <textarea class="input textarea" name="note" rows="2" maxlength="500"></textarea>
                                        </label>
                                        <button type="submit" class="btn btn--primary btn--sm"><?= e(t('Aceptar y enviar correo')) ?></button>
                                    </form>
                                </div>
                            </details>
                            <details class="admin-menu">
                                <summary class="btn btn--ghost btn--sm"><?= icon('x') ?> <?= e(t('Rechazar')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Rechazar esta solicitud? No se enviará correo.')) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $rid ?>">
                                        <input type="hidden" name="action" value="reject">
                                        <label class="field">
                                            <span class="field__label"><?= e(t('Motivo (opcional)')) ?></span>
                                            <textarea class="input textarea" name="note" rows="2" maxlength="500"></textarea>
                                        </label>
                                        <button type="submit" class="btn btn--danger btn--sm"><?= e(t('Rechazar solicitud')) ?></button>
                                    </form>
                                </div>
                            </details>
                        <?php elseif ($r['status'] === 'accepted'): ?>
                            <form method="post" action="<?= e($action) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="id" value="<?= $rid ?>">
                                <input type="hidden" name="action" value="resend">
                                <button type="submit" class="btn btn--secondary btn--sm"><?= icon('mail') ?> <?= e(t('Reenviar correo')) ?></button>
                            </form>
                        <?php endif; ?>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>
<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
