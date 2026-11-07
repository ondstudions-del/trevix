<?php

use Trevix\Controllers\Admin\AuditController;
use Trevix\Core\View;

/**
 * @var string|null $group
 * @var int|null    $adminId
 * @var array       $actors
 * @var array       $entries
 */
?>
<form class="admin-search" method="get" action="<?= e(url('admin/audit.php')) ?>">
    <div class="select-wrap">
        <select class="select" name="group" aria-label="Tipo de acción">
            <option value="">Todas las acciones</option>
            <?php foreach (AuditController::GROUPS as $key => $label): ?>
                <option value="<?= e($key) ?>"<?= $group === $key ? ' selected' : '' ?>><?= e($label) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <div class="select-wrap">
        <select class="select" name="admin" aria-label="Responsable">
            <option value="">Todo el equipo</option>
            <?php foreach ($actors as $actor): ?>
                <option value="<?= (int) $actor['id'] ?>"<?= $adminId === (int) $actor['id'] ? ' selected' : '' ?>>@<?= e($actor['username']) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn--secondary">Filtrar</button>
</form>

<section class="panel">
    <?php if ($entries === []): ?>
        <div class="panel__empty">
            <?= icon('history') ?>
            <p>No hay acciones registradas con estos filtros.</p>
        </div>
    <?php else: ?>
        <ul class="audit-list">
            <?php foreach ($entries as $entry): ?>
                <?php View::partial('admin-audit-entry', ['entry' => $entry, 'full' => true]); ?>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
