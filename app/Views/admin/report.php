<?php

use Trevix\Core\View;
use Trevix\Models\Report;

/**
 * Ficha de un objetivo reportado.
 *
 * @var string     $type
 * @var int        $id
 * @var array|null $preview
 * @var array      $reports
 * @var int        $pending
 * @var bool       $reviewing
 * @var array      $measures   clave => etiqueta
 * @var array      $durations  días => etiqueta
 * @var array      $history
 */
$statusLabels = [
    'published' => [t('Visible'), 'chip--success'], 'active' => [t('Activa'), 'chip--success'],
    'hidden' => [t('Oculta'), 'chip--warning'], 'suspended' => [t('Suspendida'), 'chip--danger'],
    'deactivated' => [t('Desactivada'), 'chip--muted'], 'removed' => [t('Eliminado'), 'chip--danger'],
];
$reportStatus = ['open' => t('Pendiente'), 'reviewing' => t('En revisión'), 'resolved' => t('Resuelto'), 'dismissed' => t('Descartado')];
$needsReason = ['warn_user', 'suspend_user', 'suspend_community', 'delete_community'];
$measureLabel = static function (string $key, string $label) use ($type, $preview): string {
    if ($type !== 'user' && $preview !== null && in_array($key, ['warn_user', 'suspend_user'], true)) {
        $username = $preview['author']['username'];
        return $key === 'warn_user'
            ? t('Advertir al autor (@{username})', ['username' => $username])
            : t('Suspender al autor (@{username})', ['username' => $username]);
    }
    return t($label);
};
?>
<a class="admin-back" href="<?= e(url('admin/reports.php')) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver a la cola')) ?></a>

<div class="admin-detail">
    <div class="admin-detail__main">
        <section class="panel">
            <header class="panel__head">
                <h2><?= icon('flag') ?> <?= in_array($type, ['comment', 'message'], true)
                    ? e(t('{type} reportado', ['type' => t(Report::TYPES[$type])]))
                    : e(t('{type} reportada', ['type' => t(Report::TYPES[$type])])) ?></h2>
                <?php if ($preview !== null && isset($statusLabels[$preview['status']])): ?>
                    <span class="chip <?= e($statusLabels[$preview['status']][1]) ?>"><?= e($statusLabels[$preview['status']][0]) ?></span>
                <?php endif; ?>
            </header>
            <?php if ($preview === null): ?>
                <div class="panel__empty">
                    <?= icon('trash-2') ?>
                    <p><?= e(t('Este contenido ya no existe (lo eliminó su autor o se borró la cuenta). Puedes cerrar los reportes.')) ?></p>
                </div>
            <?php else: ?>
                <article class="target-card">
                    <div class="target-card__author">
                        <?= avatar($preview['author'], 'md') ?>
                        <div>
                            <strong><?= e($preview['author']['display_name']) ?></strong>
                            <a href="<?= e(url('admin/users.php', ['id' => $preview['author']['id']])) ?>">@<?= e($preview['author']['username']) ?></a>
                            <?php if ($preview['author']['role'] !== 'user'): ?>
                                <span class="chip chip--brand"><?= e(t(\Trevix\Models\User::ROLE_LABELS[$preview['author']['role']] ?? '')) ?></span>
                            <?php endif; ?>
                        </div>
                    </div>
                    <?php if ($type === 'community' || $type === 'user'): ?>
                        <h3 class="target-card__title"><?= e($preview['title']) ?></h3>
                    <?php endif; ?>
                    <?php if ($preview['excerpt'] !== ''): ?>
                        <p class="target-card__text"><?= nl2br(e($preview['excerpt'])) ?></p>
                    <?php elseif ($type === 'message' && $preview['status'] === 'removed'): ?>
                        <p class="target-card__text target-card__text--muted"><?= e(t('Mensaje eliminado.')) ?></p>
                    <?php endif; ?>
                    <?php if (!empty($preview['media'])): ?>
                        <img class="target-card__media" src="<?= e(url($preview['media'])) ?>" alt="<?= e(t('Imagen del contenido reportado')) ?>" loading="lazy">
                    <?php elseif (!empty($preview['video'])): ?>
                        <video class="target-card__media" src="<?= e(url($preview['video'])) ?>" controls preload="metadata" muted playsinline></video>
                    <?php elseif (!empty($preview['audio'])): ?>
                        <audio class="target-card__media" src="<?= e(url($preview['audio'])) ?>" controls preload="none"></audio>
                    <?php endif; ?>
                    <p class="target-card__meta">
                        <?= time_tag((string) $preview['created_at']) ?>
                        <?php if (!empty($preview['community'])): ?> · <?= e(t('en {community}', ['community' => $preview['community']['name']])) ?><?php endif; ?>
                        <?php if (!empty($preview['media_count']) && $preview['media_count'] > 1): ?> · <?= e(tn((int) $preview['media_count'], '{n} adjunto', '{n} adjuntos')) ?><?php endif; ?>
                        <?php if ($type === 'user' && !empty($preview['suspended_until'])): ?> · <?= e(t('suspendida hasta {date}', ['date' => full_date((string) $preview['suspended_until'])])) ?><?php endif; ?>
                        <?php if ($preview['url'] !== null): ?>
                            · <a href="<?= e($preview['url']) ?>" target="_blank" rel="noopener"><?= e(t('Ver en TREVIX')) ?> <?= icon('external-link') ?></a>
                        <?php endif; ?>
                    </p>
                </article>
            <?php endif; ?>
        </section>

        <section class="panel">
            <header class="panel__head">
                <h2><?= icon('users') ?> <?= count($reports) ?> <?= plural(count($reports), 'reporte', 'reportes') ?></h2>
            </header>
            <ul class="reporter-list">
                <?php foreach ($reports as $report): ?>
                    <li class="reporter">
                        <div class="reporter__head">
                            <strong>@<?= e($report['reporter_username'] ?? t('cuenta eliminada')) ?></strong>
                            <span class="chip chip--muted"><?= e(t(Report::REASONS[$report['reason']] ?? $report['reason'])) ?></span>
                            <span class="reporter__status reporter__status--<?= e($report['status']) ?>"><?= e($reportStatus[$report['status']] ?? '') ?></span>
                            <?= time_tag((string) $report['created_at']) ?>
                        </div>
                        <?php if (!empty($report['details'])): ?>
                            <p class="reporter__details"><?= nl2br(e($report['details'])) ?></p>
                        <?php endif; ?>
                        <?php if (!empty($report['resolution_note']) && !in_array($report['status'], ['open', 'reviewing'], true)): ?>
                            <p class="reporter__note"><?= icon('check') ?> @<?= e($report['reviewer_username'] ?? '—') ?>: <?= e($report['resolution_note']) ?></p>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
        </section>
    </div>

    <aside class="admin-detail__side">
        <section class="panel">
            <header class="panel__head">
                <h2><?= icon('shield') ?> <?= e(t('Decisión')) ?></h2>
            </header>
            <?php if ($pending === 0): ?>
                <div class="panel__empty">
                    <?= icon('circle-check') ?>
                    <p><?= e(t('Todos los reportes de este objetivo ya están cerrados.')) ?></p>
                </div>
            <?php else: ?>
                <div class="decision">
                    <?php if (!$reviewing): ?>
                        <form method="post" action="<?= e(url('admin/reports.php')) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="type" value="<?= e($type) ?>">
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="take">
                            <button type="submit" class="btn btn--ghost btn--block"><?= icon('eye') ?> <?= e(t('Marcar como "en revisión"')) ?></button>
                        </form>
                    <?php endif; ?>

                    <form class="decision__form" method="post" action="<?= e(url('admin/reports.php')) ?>"
                        data-confirm="<?= e(tn($pending, '¿Aplicar la decisión y cerrar {n} reporte?', '¿Aplicar la decisión y cerrar {n} reportes?')) ?>" data-confirm-label="<?= e(t('Aplicar')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="type" value="<?= e($type) ?>">
                        <input type="hidden" name="id" value="<?= $id ?>">
                        <input type="hidden" name="action" value="resolve">
                        <fieldset class="decision__measures">
                            <legend class="field__label"><?= e(t('Medida')) ?></legend>
                            <label class="radio-row">
                                <input type="radio" name="measure" value="none" checked>
                                <span><?= e(t('Sin medidas: cerrar como resueltos')) ?></span>
                            </label>
                            <?php foreach ($measures as $key => $label): ?>
                                <label class="radio-row">
                                    <input type="radio" name="measure" value="<?= e($key) ?>"<?= in_array($key, $needsReason, true) ? ' data-needs-reason' : '' ?>>
                                    <span><?= e($measureLabel((string) $key, (string) $label)) ?></span>
                                </label>
                            <?php endforeach; ?>
                        </fieldset>
                        <?php if (isset($measures['suspend_user'])): ?>
                            <div class="field" data-show-for="suspend_user">
                                <label class="field__label" for="decision-days"><?= e(t('Duración de la suspensión')) ?></label>
                                <select class="select" id="decision-days" name="days">
                                    <?php foreach ($durations as $days => $label): ?>
                                        <option value="<?= (int) $days ?>"<?= $days === 7 ? ' selected' : '' ?>><?= e(t($label)) ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                        <?php endif; ?>
                        <div class="field">
                            <label class="field__label" for="decision-note"><?= e(t('Nota o motivo')) ?></label>
                            <textarea class="input textarea" id="decision-note" name="note" maxlength="255" rows="3"
                                placeholder="<?= e(t('Queda en la auditoría. Obligatorio para advertir, suspender o eliminar comunidades.')) ?>"></textarea>
                            <p class="field__hint"><?= e(t('Si adviertes o suspendes una cuenta, la persona verá este motivo.')) ?></p>
                        </div>
                        <button type="submit" class="btn btn--primary btn--block"><?= icon('check') ?> <?= e(t('Aplicar decisión')) ?></button>
                    </form>

                    <form method="post" action="<?= e(url('admin/reports.php')) ?>" class="decision__dismiss"
                        data-confirm="<?= e(tn($pending, '¿Descartar {n} reporte? El contenido se mantiene.', '¿Descartar {n} reportes? El contenido se mantiene.')) ?>" data-confirm-label="<?= e(t('Descartar')) ?>">
                        <?= csrf_field() ?>
                        <input type="hidden" name="type" value="<?= e($type) ?>">
                        <input type="hidden" name="id" value="<?= $id ?>">
                        <input type="hidden" name="action" value="dismiss">
                        <input type="hidden" name="note" value="No infringe las normas">
                        <button type="submit" class="btn btn--ghost btn--block"><?= icon('x') ?> <?= e(t('Descartar: no infringe las normas')) ?></button>
                    </form>
                </div>
            <?php endif; ?>
        </section>

        <?php if ($history !== []): ?>
            <section class="panel">
                <header class="panel__head">
                    <h2><?= icon('history') ?> <?= e(t('Historial')) ?></h2>
                </header>
                <ul class="audit-list">
                    <?php foreach ($history as $entry): ?>
                        <?php View::partial('admin-audit-entry', ['entry' => $entry]); ?>
                    <?php endforeach; ?>
                </ul>
            </section>
        <?php endif; ?>
    </aside>
</div>
