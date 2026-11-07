<?php
/**
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
if ($prevUrl === null && $nextUrl === null) {
    return;
}
?>
<nav class="admin-pager" aria-label="Paginación">
    <?php if ($prevUrl !== null): ?>
        <a class="btn btn--ghost btn--sm" href="<?= e($prevUrl) ?>" rel="prev"><?= icon('chevron-left') ?> Anterior</a>
    <?php else: ?>
        <span></span>
    <?php endif; ?>
    <?php if ($nextUrl !== null): ?>
        <a class="btn btn--ghost btn--sm" href="<?= e($nextUrl) ?>" rel="next">Siguiente <?= icon('chevron-right') ?></a>
    <?php endif; ?>
</nav>
