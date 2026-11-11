<?php

use Trevix\Core\View;
use Trevix\Models\Appeal;

/**
 * Apelaciones de suspensiones y advertencias, con el historial de faltas de cada cuenta.
 *
 * @var string      $status
 * @var array       $counts  Appeal::counts()
 * @var array       $appeals Appeal::adminList() + record (UserRecord::summary) + can_act
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
$emptyTexts = [
    'pending'  => 'No hay apelaciones por revisar.',
    'accepted' => 'Todavía no se aceptó ninguna apelación.',
    'rejected' => 'No hay apelaciones rechazadas.',
];
$tabLabels = ['pending' => 'Por revisar', 'accepted' => 'Aceptadas', 'rejected' => 'Rechazadas'];
?>
<nav class="admin-tabs" aria-label="<?= e(t('Estado de las apelaciones')) ?>">
    <?php foreach (array_keys(Appeal::STATUSES) as $key): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/appeals.php', ['status' => $key === 'pending' ? null : $key])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e(t($tabLabels[$key])) ?>
            <?php if (($counts[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $counts[$key] ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<p class="content-row__muted">
    <?= e(t('Las cuentas suspendidas o baneadas apelan desde la página de inicio de sesión (con su usuario y contraseña); las advertencias se apelan con la sesión iniciada.')) ?>
    <?= e(t('Aceptar levanta la sanción; al rechazar, la persona ve el motivo y puede volver a apelar en 7 días.')) ?>
</p>

<section class="panel">
    <?php if ($appeals === []): ?>
        <div class="panel__empty">
            <?= icon('scale') ?>
            <p><?= e(t($emptyTexts[$status])) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($appeals as $a): ?>
                <?php $rec = $a['record']; ?>
                <li class="content-row" id="apelacion-<?= (int) $a['id'] ?>">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <?= avatar($a, 'xs') ?>
                            <a href="<?= e(url('admin/users.php', ['id' => $a['user_id']]) . '#historial') ?>"><strong><?= e($a['display_name']) ?></strong> (@<?= e($a['username']) ?>)</a>
                            <span class="chip chip--brand"><?= e(t(Appeal::TYPES[$a['type']] ?? $a['type'])) ?></span>
                            <?php if ($a['type'] === 'suspension' && $a['user_status'] === 'suspended'): ?>
                                <span class="chip chip--danger"><?= $a['suspended_until']
                                    ? e(t('Suspendida hasta el {date}', ['date' => full_date((string) $a['suspended_until'], false)]))
                                    : e(t('Baneada')) ?></span>
                            <?php elseif ($a['type'] === 'suspension' && $status === 'pending'): ?>
                                <span class="chip chip--muted"><?= e(t('Ya no está suspendida')) ?></span>
                            <?php endif; ?>
                        </p>
                        <?php if (!empty($a['sanction_reason'])): ?>
                            <p class="content-row__muted"><?= e(t('Sanción')) ?>: «<?= e($a['sanction_reason']) ?>»</p>
                        <?php endif; ?>
                        <p class="content-row__text">«<?= e($a['message']) ?>»</p>
                        <p class="content-row__muted">
                            <?= e(t('Enviada')) ?> <?= time_tag((string) $a['created_at']) ?>
                            · <?= e(tn((int) $rec['strikes'], '{n} falta', '{n} faltas')) ?>
                            · <?= e(tn((int) $rec['reports_received']['total'], '{n} reporte recibido', '{n} reportes recibidos')) ?>
                            · <?= e(tn(array_sum($rec['appeals']), '{n} apelación', '{n} apelaciones')) ?>
                        </p>
                        <?php if ($a['status'] !== 'pending'): ?>
                            <p class="content-row__muted">
                                <?= e(t('Revisada')) ?> <?= time_tag((string) $a['reviewed_at']) ?><?= $a['reviewer_username'] !== null ? ' · @' . e($a['reviewer_username']) : '' ?>
                                <?php if (!empty($a['resolution_note'])): ?> · «<?= e($a['resolution_note']) ?>»<?php endif; ?>
                            </p>
                        <?php endif; ?>
                    </div>
                    <?php if ($a['status'] === 'pending' && $a['can_act']): ?>
                        <?php View::partial('admin-appeal-actions', ['appeal' => $a]); ?>
                    <?php elseif ($a['status'] === 'pending'): ?>
                        <p class="content-row__muted"><?= e(t('Solo un administrador puede resolverla.')) ?></p>
                    <?php endif; ?>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
