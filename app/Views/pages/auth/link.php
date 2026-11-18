<?php
/**
 * @var string     $mode host|guest
 * @var array|null $challenge
 * @var array|null $status
 * @var string     $code
 * @var array      $errors
 * @var array      $old
 */
$isHost = ($mode ?? '') === 'host';
$codeValue = $isHost ? (string) ($challenge['code'] ?? '') : (string) ($code ?? ($old['code'] ?? ''));
$payload = $isHost ? (string) ($challenge['payload'] ?? ('trevix://link/' . $codeValue)) : '';
$rowStatus = (string) ($status['status'] ?? 'pending');
?>
<section class="auth-card">
    <header class="auth-card__head">
        <h1><?= e(t($isHost ? 'Vincular dispositivo' : 'Vincular')) ?></h1>
        <p><?= e(t($isHost
            ? 'Muestra este código en la app del otro dispositivo (Login → Vincular) o escribe el código allí.'
            : 'Escribe el código que ves en la app o en otro navegador donde ya iniciaste sesión.')) ?></p>
    </header>

    <?php if (isset($errors['form']) || isset($errors['code'])): ?>
        <div class="alert alert--error" role="alert">
            <?= icon('triangle-alert') ?>
            <p><?= e(t($errors['form'] ?? $errors['code'])) ?></p>
        </div>
    <?php endif; ?>

    <?php if ($isHost && $codeValue !== ''): ?>
        <div class="auth-card__qr" style="text-align:center;margin:1rem 0 1.25rem">
            <img src="https://api.qrserver.com/v1/create-qr-code/?size=220x220&amp;data=<?= rawurlencode($payload) ?>"
                 width="220" height="220" alt="<?= e(t('Código QR de vinculación')) ?>"
                 style="border-radius:16px;background:#fff;padding:12px">
            <p style="font-size:1.75rem;letter-spacing:.2em;font-weight:700;margin:.9rem 0 .25rem"><?= e($codeValue) ?></p>
            <p class="setting-row__text"><?= e(t('Caduca en unos minutos.')) ?></p>
        </div>

        <?php if ($rowStatus === 'claimed'): ?>
            <div class="alert alert--info" role="status">
                <p><?= e(t('«{device}» quiere entrar. Confirma para vincularlo.', [
                    'device' => $status['guest_device_name'] ?? t('Dispositivo'),
                ])) ?></p>
            </div>
            <form method="post" action="<?= e(url('link.php')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="approve">
                <button class="btn btn--primary btn--lg btn--block" type="submit"><?= e(t('Vincular')) ?></button>
            </form>
            <form method="post" action="<?= e(url('link.php')) ?>" style="margin-top:.75rem">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="cancel">
                <button class="btn btn--secondary btn--block" type="submit"><?= e(t('Rechazar')) ?></button>
            </form>
        <?php else: ?>
            <p class="auth-card__switch"><?= e(t('Esperando al otro dispositivo…')) ?></p>
            <meta http-equiv="refresh" content="3">
            <form method="post" action="<?= e(url('link.php')) ?>" style="margin-top:1rem">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="start">
                <button class="btn btn--glass btn--block" type="submit"><?= e(t('Generar otro código')) ?></button>
            </form>
        <?php endif; ?>

        <p class="auth-card__switch"><a href="<?= e(url('settings.php', ['section' => 'security'])) ?>"><?= e(t('Volver a seguridad')) ?></a></p>

    <?php elseif (!$isHost && is_array($status) && ($status['status'] ?? '') === 'claimed'): ?>
        <div class="alert alert--info" role="status">
            <p><?= e(t('Confirma la vinculación en el otro dispositivo. Esta página se actualizará sola.')) ?></p>
        </div>
        <p style="text-align:center;font-size:1.5rem;letter-spacing:.2em;font-weight:700"><?= e($codeValue) ?></p>
        <meta http-equiv="refresh" content="3">
        <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= e(t('Volver al inicio de sesión')) ?></a></p>

    <?php else: ?>
        <form class="form" method="post" action="<?= e(url('link.php')) ?>" novalidate data-validate>
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="claim">
            <div class="field">
                <label class="field__label" for="code"><?= e(t('Código')) ?></label>
                <div class="input-wrap">
                    <?= icon('key-round') ?>
                    <input class="input" id="code" name="code" type="text" required maxlength="12" autocomplete="one-time-code"
                        spellcheck="false" autocapitalize="characters"
                        placeholder="<?= e(t('ABCD1234')) ?>" value="<?= e($codeValue) ?>"
                        <?= invalid_attrs($errors, 'code', 'code') ?>>
                </div>
                <?= field_error($errors, 'code', 'code') ?>
            </div>
            <button class="btn btn--primary btn--lg btn--block" type="submit"><?= e(t('Continuar')) ?></button>
        </form>
        <p class="auth-card__switch"><a href="<?= e(url('login.php')) ?>"><?= e(t('Volver al inicio de sesión')) ?></a></p>
    <?php endif; ?>
</section>
