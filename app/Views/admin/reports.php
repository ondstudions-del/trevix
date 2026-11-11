<?php

use Trevix\Core\View;
use Trevix\Models\Report;

/**
 * @var string      $status   open | resolved | dismissed
 * @var string|null $type
 * @var array       $targets
 * @var array       $counts   objetivos pendientes por tipo
 */
$statusTabs = ['open' => t('Pendientes'), 'resolved' => t('Resueltos'), 'dismissed' => t('Descartados')];
$totalOpen = array_sum($counts);
?>
<nav class="admin-tabs" aria-label="<?= e(t('Estado de los reportes')) ?>">
    <?php foreach ($statusTabs as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/reports.php', ['status' => $key, 'type' => $type])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e($label) ?>
            <?php if ($key === 'open' && $totalOpen > 0): ?><span class="admin-tabs__count"><?= $totalOpen ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<div class="admin-filters" role="group" aria-label="<?= e(t('Tipo de objetivo')) ?>">
    <a class="<?= cx('chip', ['is-active' => $type === null]) ?>" href="<?= e(url('admin/reports.php', ['status' => $status])) ?>"><?= e(t('Todos los tipos')) ?></a>
    <?php foreach (Report::TYPES as $key => $label): ?>
        <a class="<?= cx('chip', ['is-active' => $type === $key]) ?>" href="<?= e(url('admin/reports.php', ['status' => $status, 'type' => $key])) ?>">
            <?= e(t($label)) ?><?php if ($status === 'open' && $counts[$key] > 0): ?> · <?= $counts[$key] ?><?php endif; ?>
        </a>
    <?php endforeach; ?>
</div>

<section class="panel">
    <?php if ($targets === []): ?>
        <div class="panel__empty">
            <?= icon($status === 'open' ? 'circle-check' : 'inbox') ?>
            <p><?= $status === 'open' ? e(t('No hay reportes pendientes. Buen trabajo.')) : e(t('No hay reportes en esta lista.')) ?></p>
        </div>
    <?php else: ?>
        <ul class="report-list">
            <?php foreach ($targets as $target): ?>
                <?php View::partial('admin-report-row', ['target' => $target]); ?>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
