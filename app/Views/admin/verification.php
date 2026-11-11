<?php

use Trevix\Core\View;
use Trevix\Models\VerificationRequest;

/**
 * Solicitudes de verificado: requisitos con los que se pidió y los de ahora, aprobar o rechazar con motivo.
 *
 * @var string      $status
 * @var array       $counts   VerificationRequest::counts()
 * @var array       $requests VerificationRequest::adminList() + 'now' (requisitos actuales en las pendientes)
 * @var array       $rules    VerificationService::rules()
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
$action = url('admin/verification.php');
$emptyTexts = [
    'pending'   => t('No hay solicitudes de verificado por revisar.'),
    'approved'  => t('Todavía no se aprobó ninguna solicitud.'),
    'rejected'  => t('No hay solicitudes rechazadas.'),
    'cancelled' => t('Nadie canceló su solicitud.'),
];
?>
<nav class="admin-tabs" aria-label="<?= e(t('Estado de las solicitudes')) ?>">
    <?php foreach (VerificationRequest::STATUSES as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/verification.php', ['status' => $key === 'pending' ? null : $key])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e($key === 'pending' ? t('Por revisar') : t($label . 's')) ?>
            <?php if (($counts[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $counts[$key] ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<p class="content-row__muted">
    <?= e(t('Requisitos: {followers} seguidores, promedio de {likes} «Me gusta» en las últimas publicaciones (mínimo {posts}) y ninguna advertencia en los últimos {days} días.', [
        'followers' => number_format($rules['min_followers'], 0, ',', '.'),
        'likes'     => (int) $rules['min_avg_likes'],
        'posts'     => (int) $rules['min_posts'],
        'days'      => (int) $rules['warning_days'],
    ])) ?>
    <?= e(t('Se piden desde la app.')) ?>
</p>

<section class="panel">
    <?php if ($requests === []): ?>
        <div class="panel__empty">
            <?= icon('badge-check') ?>
            <p><?= e($emptyTexts[$status]) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($requests as $r): ?>
                <?php $rid = (int) $r['id']; ?>
                <li class="content-row" id="solicitud-<?= $rid ?>">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <?= avatar($r, 'xs') ?>
                            <a href="<?= e(url('admin/users.php', ['id' => $r['user_id']])) ?>"><strong><?= e($r['display_name']) ?></strong> (@<?= e($r['username']) ?>)</a>
                            <span class="chip chip--brand"><?= e(t(VerificationRequest::CATEGORIES[$r['category']] ?? $r['category'])) ?></span>
                            <?php if ((int) $r['is_verified'] === 1): ?><span class="chip chip--success"><?= e(t('Ya verificada')) ?></span><?php endif; ?>
                            <?php if ($r['user_status'] !== 'active'): ?><span class="chip chip--danger"><?= e(t('Cuenta no activa')) ?></span><?php endif; ?>
                            <?php if ($r['email_verified_at'] === null): ?><span class="chip chip--muted"><?= e(t('Correo sin verificar')) ?></span><?php endif; ?>
                        </p>
                        <p class="content-row__text"><?= e(t('Nombre:')) ?> <strong><?= e($r['full_name']) ?></strong></p>
                        <?php if (!empty($r['note'])): ?>
                            <p class="content-row__text">«<?= e($r['note']) ?>»</p>
                        <?php endif; ?>
                        <p class="content-row__muted">
                            <?= e(t('Al pedirlo: {followers} seguidores · promedio de {likes} «Me gusta» en {posts} publicaciones', [
                                'followers' => compact_number((int) $r['followers_count']),
                                'likes'     => compact_number((int) $r['avg_likes']),
                                'posts'     => (int) $r['posts_counted'],
                            ])) ?>
                            · <?= e(t('enviada')) ?> <?= time_tag((string) $r['created_at']) ?>
                        </p>
                        <?php if ($r['now'] !== null): ?>
                            <ul class="content-row__muted">
                                <?php foreach ($r['now']['checks'] as $check): ?>
                                    <li><?= icon($check['ok'] ? 'circle-check' : 'circle-x') ?> <?= e($check['label']) ?> — <?= e($check['detail']) ?></li>
                                <?php endforeach; ?>
                            </ul>
                        <?php endif; ?>
                        <?php if ($r['reviewed_at'] !== null): ?>
                            <p class="content-row__muted">
                                <?= e(t('Revisada')) ?> <?= time_tag((string) $r['reviewed_at']) ?><?= $r['reviewer_username'] !== null ? ' ' . e(t('por @{username}', ['username' => $r['reviewer_username']])) : '' ?>
                                <?php if (!empty($r['decision_note'])): ?> · «<?= e($r['decision_note']) ?>»<?php endif; ?>
                            </p>
                        <?php endif; ?>
                    </div>
                    <?php if ($r['status'] === 'pending'): ?>
                        <div class="content-row__actions">
                            <details class="admin-menu">
                                <summary class="btn btn--primary btn--sm"><?= icon('badge-check') ?> <?= e(t('Aprobar')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $rid ?>">
                                        <input type="hidden" name="action" value="approve">
                                        <label class="field__label" for="approve-<?= $rid ?>"><?= e(t('Nota interna')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                                        <input class="input" id="approve-<?= $rid ?>" name="note" maxlength="255">
                                        <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('badge-check') ?> <?= e(t('Verificar cuenta')) ?></button>
                                    </form>
                                </div>
                            </details>
                            <details class="admin-menu">
                                <summary class="btn btn--ghost btn--sm"><?= icon('circle-x') ?> <?= e(t('Rechazar')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $rid ?>">
                                        <input type="hidden" name="action" value="reject">
                                        <label class="field__label" for="reject-<?= $rid ?>"><?= e(t('Motivo (lo verá la persona)')) ?></label>
                                        <input class="input" id="reject-<?= $rid ?>" name="reason" required minlength="5" maxlength="255">
                                        <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('circle-x') ?> <?= e(t('Rechazar solicitud')) ?></button>
                                    </form>
                                </div>
                            </details>
                        </div>
                    <?php endif; ?>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
