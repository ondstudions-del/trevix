<?php

use Trevix\Core\View;
use Trevix\Models\DeviceLink;

/**
 * @var string     $mode host|guest
 * @var array|null $challenge
 * @var array|null $claimed
 * @var array|null $status
 * @var array      $errors
 * @var array      $old
 */
$isHost = ($mode ?? '') === 'host';
$codeValue = '';
$expiresAt = '';
$seed = 0;
$guestName = '';
$phase = 'host-scan';

if ($isHost) {
    if (is_array($claimed ?? null) || (is_array($status ?? null) && ($status['status'] ?? '') === 'claimed')) {
        $phase = 'host-claimed';
        $codeValue = (string) (($claimed['code'] ?? null) ?: ($status['code'] ?? ''));
        $guestName = (string) (($claimed['guest_device_name'] ?? null) ?: ($status['guest_device_name'] ?? ''));
        $expiresAt = (string) (($claimed['expires_at'] ?? null) ?: ($status['expires_at'] ?? ''));
    }
} else {
    $codeValue = (string) ($challenge['code'] ?? '');
    $expiresAt = (string) ($challenge['expires_at'] ?? ($status['expires_at'] ?? ''));
    $seed = (int) ($challenge['seed'] ?? DeviceLink::seedFor($codeValue));
    $st = (string) ($status['status'] ?? 'pending');
    $phase = $st === 'claimed' ? 'guest-waiting' : 'guest-show';
    if ($codeValue === '') {
        $phase = 'guest-blocked';
    }
}

View::share('scripts', [
    asset('js/vendor/qrcodegen.js'),
    asset('js/vendor/jsQR.js'),
    asset('js/vincriptar-qr.js'),
    asset('js/device-link.js'),
]);

$boot = [
    'mode'       => $isHost ? 'host' : 'guest',
    'phase'      => $phase,
    'code'       => $codeValue,
    'seed'       => $seed,
    'payload'    => $codeValue !== '' ? DeviceLink::payloadFor($codeValue) : '',
    'expires_at' => $expiresAt,
    'guest_name' => $guestName,
    'ttl'        => DeviceLink::TTL_SECONDS,
    'poll_ms'    => 3000,
    'status_url' => $codeValue !== '' ? url('api/v1/auth/vincriptar/' . rawurlencode($codeValue) . '/status') : '',
    'complete_url' => url('link.php'),
    'i18n'       => [
        'copy'    => t('Toca para copiar'),
        'copied'  => t('Código copiado.'),
        'expires' => t('Caduca en {n} s'),
        'expired' => t('Caducado'),
        'scan'    => t('Apunta al código QR'),
        'manual'  => t('Introducir código'),
        'confirm' => t('Confirmar'),
        'vincriptar' => t('VINCRIPTAR'),
    ],
];
?>
<section class="auth-card auth-card--wide link-stage" id="device-link-root" data-phase="<?= e($phase) ?>">
    <script type="application/json" id="device-link-boot"><?= json_encode($boot, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS) ?></script>

    <header class="link-stage__head">
        <div class="link-stage__badge">
            <?php if ($phase === 'host-claimed' || $phase === 'guest-waiting'): ?>
                <span class="link-chip link-chip--pulse" data-link-badge><?= e(t('Confirmar')) ?></span>
            <?php else: ?>
                <span class="link-chip" data-link-badge><?= e(t('VINCRIPTAR')) ?></span>
            <?php endif; ?>
        </div>
        <h1><?= e(t('VINCRIPTAR')) ?></h1>
        <p><?= e(t($isHost
            ? 'Escanea el código QR o escribe el código de enlace del otro dispositivo.'
            : 'Muestra este QR o el código en el dispositivo donde ya iniciaste sesión (Ajustes → VINCRIPTAR).')) ?></p>
    </header>

    <?php if (isset($errors['form']) || isset($errors['code'])): ?>
        <div class="alert alert--error" role="alert">
            <?= icon('triangle-alert') ?>
            <p><?= e(t($errors['form'] ?? $errors['code'])) ?></p>
        </div>
    <?php endif; ?>

    <?php if ($phase === 'guest-show' || $phase === 'guest-waiting'): ?>
        <div class="link-qr" data-vincriptar-host>
            <div class="link-qr__frame link-qr__frame--vincode">
                <canvas id="vincriptar-qr-canvas" class="link-qr__canvas" width="280" height="280" aria-label="<?= e(t('VINCRIPTAR')) ?>"></canvas>
            </div>
            <button type="button" class="link-code" data-copy-code data-code="<?= e($codeValue) ?>" title="<?= e(t('Toca para copiar')) ?>">
                <span class="link-code__value"><?= e(strlen($codeValue) === 8 ? substr($codeValue, 0, 4) . '-' . substr($codeValue, 4) : $codeValue) ?></span>
                <span class="link-code__hint"><?= e(t('Toca para copiar')) ?></span>
            </button>
            <div class="link-ttl" data-link-ttl>
                <div class="link-ttl__track"><span class="link-ttl__bar" data-link-ttl-bar></span></div>
                <p class="link-ttl__label" data-link-ttl-label><?= e(t('Caduca en {n} s', ['n' => DeviceLink::TTL_SECONDS])) ?></p>
            </div>
            <div class="link-claim glass-panel" role="status" data-link-claim-panel <?= $phase !== 'guest-waiting' ? 'hidden' : '' ?>>
                <div class="link-claim__icon link-claim__icon--spin"><?= icon('refresh-cw') ?></div>
                <div>
                    <strong><?= e(t('Esperando confirmación…')) ?></strong>
                    <p><?= e(t('Confirma la vinculación en el otro dispositivo.')) ?></p>
                </div>
            </div>
            <p class="link-wait" data-link-wait-scan <?= $phase !== 'guest-show' ? 'hidden' : '' ?>><?= e(t('Esperando a que escaneen tu código…')) ?></p>
            <form method="post" action="<?= e(url('link.php')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="refresh">
                <button class="btn btn--glass btn--block" type="submit"><?= e(t('Generar otro VINCODE')) ?></button>
            </form>
        </div>
        <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= e(t('Volver al inicio de sesión')) ?></a></p>

    <?php elseif ($phase === 'guest-blocked'): ?>
        <div class="alert alert--error" role="alert">
            <p><?= e(t('Espera un momento antes de generar otro VINCODE.')) ?></p>
        </div>
        <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= e(t('Volver al inicio de sesión')) ?></a></p>

    <?php elseif ($phase === 'host-claimed'): ?>
        <div class="link-claim glass-panel" role="status">
            <div class="link-claim__icon"><?= icon('smartphone') ?></div>
            <div>
                <strong><?= e(t('Confirma la vinculación')) ?></strong>
                <p><?= e(t('«{device}» quiere entrar. ¿Lo apruebas?', [
                    'device' => $guestName !== '' ? $guestName : t('Dispositivo'),
                ])) ?></p>
            </div>
        </div>
        <div class="link-actions">
            <form method="post" action="<?= e(url('link.php')) ?>" class="link-actions__grow">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="approve">
                <button class="btn btn--primary btn--lg btn--block" type="submit"><?= e(t('Autorizar')) ?></button>
            </form>
            <form method="post" action="<?= e(url('link.php')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="reject">
                <button class="btn btn--secondary btn--lg" type="submit"><?= e(t('Rechazar')) ?></button>
            </form>
        </div>
        <p class="auth-card__switch"><a href="<?= e(url('settings.php', ['section' => 'security'])) ?>"><?= e(t('Volver a seguridad')) ?></a></p>

    <?php else: /* host-scan */ ?>
        <div class="link-host-scan">
            <div class="link-scan" data-vincriptar-scanner>
                <video id="vincriptar-video" class="link-scan__video" playsinline muted></video>
                <canvas id="vincriptar-scan-canvas" class="link-scan__canvas" hidden></canvas>
                <div class="link-scan__frame" aria-hidden="true"></div>
                <p class="link-scan__hint" data-scan-hint><?= e(t('Apunta al código QR')) ?></p>
            </div>
            <form class="form" method="post" action="<?= e(url('link.php')) ?>" novalidate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="scan">
                <div class="field">
                    <label class="field__label" for="code"><?= e(t('Introducir código')) ?></label>
                    <div class="input-wrap input-wrap--code">
                        <?= icon('key-round') ?>
                        <input class="input input--code" id="code" name="code" type="text" required maxlength="12"
                            autocomplete="one-time-code" spellcheck="false" autocapitalize="characters"
                            placeholder="<?= e(t('ABCD1234')) ?>"
                            value="<?= e((string) ($old['code'] ?? '')) ?>"
                            <?= invalid_attrs($errors, 'code', 'code') ?>>
                    </div>
                    <?= field_error($errors, 'code', 'code') ?>
                </div>
                <button class="btn btn--primary btn--lg btn--block" type="submit"><?= e(t('Continuar')) ?></button>
            </form>
        </div>
        <p class="auth-card__switch"><a href="<?= e(url('settings.php', ['section' => 'security'])) ?>"><?= e(t('Volver a seguridad')) ?></a></p>
    <?php endif; ?>
</section>
