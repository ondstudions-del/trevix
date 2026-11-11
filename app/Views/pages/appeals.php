<?php

use Trevix\Core\View;
use Trevix\Models\Appeal;
use Trevix\Services\AppealService;

/**
 * Advertencias de la cuenta (con la opción de apelarlas) y el estado de sus apelaciones.
 *
 * @var array $warnings        Warning::forUser()
 * @var array $appeals         Appeal::forUser()
 * @var array $pendingWarnings warning_id => true si ya tiene una apelación pendiente
 * @var array $errors          'warning_<id>' => mensaje
 * @var array $old
 */
$appealStatus = ['pending' => 'chip--warning', 'accepted' => 'chip--success', 'rejected' => 'chip--muted'];
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('settings.php')) ?>" aria-label="<?= e(t('Volver')) ?>"><?= icon('arrow-left') ?></a>
        <h1 class="page-header__title page-header__title--visible"><?= e(t('Advertencias y apelaciones')) ?></h1>
    </div>
</header>

<div class="appeals-page">
    <p class="appeals-page__intro">
        <?= e(t('Aquí ves las advertencias que el equipo de TREVIX dio a tu cuenta. Si crees que alguna es un error, apélala explicando lo que pasó: el equipo la revisará y te avisaremos de la decisión.')) ?>
    </p>

    <section class="card appeals-section" aria-labelledby="warnings-heading">
        <h2 id="warnings-heading"><?= icon('triangle-alert') ?> <?= e(t('Advertencias')) ?></h2>
        <?php if ($warnings === []): ?>
            <?php View::partial('empty-state', ['icon' => 'circle-check', 'heading' => 'Tu cuenta no tiene advertencias', 'text' => 'Sigue respetando las normas de la comunidad.']); ?>
        <?php else: ?>
            <ul class="appeals-list">
                <?php foreach ($warnings as $w): ?>
                    <?php
                    $wid = (int) $w['id'];
                    $error = $errors['warning_' . $wid] ?? null;
                    $open = $error !== null;
                    ?>
                    <li class="appeals-item" id="advertencia-<?= $wid ?>">
                        <p class="appeals-item__text"><?= e($w['reason']) ?></p>
                        <p class="appeals-item__meta">
                            <?= time_tag((string) $w['created_at']) ?>
                            <?php if ($w['revoked']): ?>
                                · <span class="chip chip--muted"><?= e(t('Retirada')) ?></span>
                            <?php elseif (isset($pendingWarnings[$wid])): ?>
                                · <span class="chip chip--warning"><?= e(t('Apelación en revisión')) ?></span>
                            <?php else: ?>
                                · <span class="chip chip--danger"><?= e(t('Vigente')) ?></span>
                            <?php endif; ?>
                        </p>
                        <?php if (!$w['revoked'] && !isset($pendingWarnings[$wid])): ?>
                            <details class="appeals-item__form"<?= $open ? ' open' : '' ?>>
                                <summary class="btn btn--secondary btn--sm"><?= icon('scale') ?> <?= e(t('Apelar')) ?></summary>
                                <form class="form" method="post" action="<?= e(url('appeals.php')) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="warning_id" value="<?= $wid ?>">
                                    <div class="field">
                                        <label class="field__label" for="appeal-<?= $wid ?>"><?= e(t('¿Por qué crees que es un error?')) ?></label>
                                        <textarea class="input textarea" id="appeal-<?= $wid ?>" name="message" rows="4" required
                                            minlength="<?= AppealService::MESSAGE_MIN ?>" maxlength="<?= AppealService::MESSAGE_MAX ?>"
                                            <?= $open ? 'aria-invalid="true" aria-describedby="appeal-' . $wid . '-error"' : '' ?>><?= e($open && (int) ($old['warning_id'] ?? 0) === $wid ? (string) ($old['message'] ?? '') : '') ?></textarea>
                                        <?php if ($open): ?>
                                            <p class="field__error" id="appeal-<?= $wid ?>-error"><?= e(t($error)) ?></p>
                                        <?php endif; ?>
                                    </div>
                                    <button type="submit" class="btn btn--primary btn--sm"><?= icon('send') ?> <?= e(t('Enviar apelación')) ?></button>
                                </form>
                            </details>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
    </section>

    <section class="card appeals-section" aria-labelledby="appeals-heading">
        <h2 id="appeals-heading"><?= icon('scale') ?> <?= e(t('Mis apelaciones')) ?></h2>
        <?php if ($appeals === []): ?>
            <p class="appeals-item__meta"><?= e(t('Todavía no has enviado apelaciones.')) ?></p>
        <?php else: ?>
            <ul class="appeals-list">
                <?php foreach ($appeals as $a): ?>
                    <li class="appeals-item">
                        <p class="appeals-item__meta">
                            <span class="chip chip--brand"><?= e(t(Appeal::TYPES[$a['type']] ?? $a['type'])) ?></span>
                            <span class="chip <?= e($appealStatus[$a['status']] ?? 'chip--muted') ?>"><?= e(t(Appeal::STATUSES[$a['status']] ?? $a['status'])) ?></span>
                            <?= time_tag((string) $a['created_at']) ?>
                        </p>
                        <?php if (!empty($a['sanction_reason'])): ?>
                            <p class="appeals-item__meta"><?= e(t('Sanción')) ?>: «<?= e($a['sanction_reason']) ?>»</p>
                        <?php endif; ?>
                        <p class="appeals-item__text">«<?= e($a['message']) ?>»</p>
                        <?php if ($a['status'] !== 'pending' && !empty($a['resolution_note'])): ?>
                            <p class="appeals-item__meta"><?= e(t('Nota del equipo')) ?>: «<?= e($a['resolution_note']) ?>»</p>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
    </section>
</div>
