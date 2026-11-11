<?php

use Trevix\Models\Report;

/**
 * Fila de la cola de reportes: un objetivo con todos sus reportes agrupados.
 *
 * @var array $target  elemento de Report::targets()
 */
$preview = $target['preview'];
$typeIcons = ['post' => 'file-text', 'comment' => 'message-circle', 'user' => 'user', 'community' => 'users-round', 'message' => 'messages-square', 'story' => 'circle-dashed'];
$href = url('admin/reports.php', ['type' => $target['type'], 'id' => $target['id']]);
?>
<li class="report-row">
    <a class="report-row__link" href="<?= e($href) ?>">
        <span class="report-row__icon"><?= icon($typeIcons[$target['type']] ?? 'flag') ?></span>
        <span class="report-row__body">
            <span class="report-row__top">
                <span class="chip chip--muted"><?= e(t(Report::TYPES[$target['type']] ?? $target['type'])) ?></span>
                <strong class="report-row__title"><?= e($preview['title'] ?? t('Ya no existe')) ?></strong>
                <?php if ($target['reviewing']): ?>
                    <span class="chip chip--warning"><?= e(t('En revisión')) ?></span>
                <?php endif; ?>
            </span>
            <?php if ($preview !== null && $preview['excerpt'] !== ''): ?>
                <span class="report-row__excerpt"><?= e(mb_strimwidth($preview['excerpt'], 0, 140, '…')) ?></span>
            <?php elseif ($preview === null): ?>
                <span class="report-row__excerpt"><?= e(t('El contenido se eliminó después de ser reportado.')) ?></span>
            <?php endif; ?>
            <span class="report-row__meta">
                <?= e(implode(' · ', array_map(static fn (string $r) => t(Report::REASONS[$r] ?? $r), $target['reasons']))) ?>
            </span>
        </span>
        <span class="report-row__side">
            <span class="report-row__count" title="<?= e(t('Reportes')) ?>"><?= icon('flag') ?> <?= (int) $target['reports_count'] ?></span>
            <?= time_tag((string) $target['last_reported_at']) ?>
        </span>
    </a>
</li>
