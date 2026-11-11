<?php

use Trevix\Core\View;
use Trevix\Models\Community;

/**
 * @var string      $q
 * @var string|null $status
 * @var array       $communities
 */
$action = url('admin/communities.php');
?>
<form class="admin-search" method="get" action="<?= e($action) ?>" role="search">
    <div class="input-wrap">
        <?= icon('search') ?>
        <input class="input" type="search" name="q" value="<?= e($q) ?>" maxlength="100" placeholder="<?= e(t('Nombre de la comunidad')) ?>" aria-label="<?= e(t('Buscar comunidades')) ?>">
    </div>
    <div class="select-wrap">
        <select class="select" name="status" aria-label="<?= e(t('Estado')) ?>">
            <option value=""><?= e(t('Todos los estados')) ?></option>
            <?php foreach (Community::STATUS_LABELS as $key => $label): ?>
                <option value="<?= e($key) ?>"<?= $status === $key ? ' selected' : '' ?>><?= e(t($label)) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn--secondary"><?= e(t('Buscar')) ?></button>
</form>

<section class="panel">
    <?php if ($communities === []): ?>
        <div class="panel__empty">
            <?= icon('users-round') ?>
            <p><?= e(t('No hay comunidades con estos filtros.')) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($communities as $c): ?>
                <?php $suspended = $c['status'] === 'suspended'; ?>
                <li class="content-row">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <?= community_icon($c) ?>
                            <strong><?= e($c['name']) ?></strong>
                            <span class="chip chip--muted"><?= e(t(Community::VISIBILITIES[$c['visibility']] ?? '')) ?></span>
                            <?php if ($suspended): ?><span class="chip chip--danger"><?= e(t('Suspendida')) ?></span><?php endif; ?>
                            <?php if ((int) $c['open_reports'] > 0): ?>
                                <a class="chip chip--danger" href="<?= e(url('admin/reports.php', ['type' => 'community', 'id' => $c['id']])) ?>"><?= icon('flag') ?> <?= (int) $c['open_reports'] ?></a>
                            <?php endif; ?>
                        </p>
                        <p class="content-row__muted">
                            <?= e(t('Administra')) ?> <a href="<?= e(url('admin/users.php', ['id' => $c['owner_id']])) ?>">@<?= e($c['owner_username']) ?></a>
                            · <?= compact_number((int) $c['members_count']) ?> <?= plural((int) $c['members_count'], 'miembro', 'miembros') ?>
                            · <?= compact_number((int) $c['posts_count']) ?> <?= plural((int) $c['posts_count'], 'publicación', 'publicaciones') ?>
                            · <?= e(t('creada')) ?> <?= time_tag((string) $c['created_at']) ?>
                        </p>
                    </div>
                    <div class="content-row__actions">
                        <?php if (!$suspended): ?>
                            <a class="btn btn--ghost btn--sm" href="<?= e(community_url($c)) ?>" target="_blank" rel="noopener"><?= icon('external-link') ?> <?= e(t('Ver')) ?></a>
                        <?php endif; ?>
                        <details class="admin-menu">
                            <summary class="btn btn--ghost btn--sm"><?= icon('settings') ?> <?= e(t('Moderar')) ?></summary>
                            <div class="admin-menu__panel">
                                <?php if ($suspended): ?>
                                    <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Reactivar «{name}»?', ['name' => $c['name']])) ?>" data-confirm-label="<?= e(t('Reactivar')) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= (int) $c['id'] ?>">
                                        <input type="hidden" name="action" value="restore">
                                        <button type="submit" class="btn btn--secondary btn--sm btn--block"><?= icon('rotate-ccw') ?> <?= e(t('Reactivar')) ?></button>
                                    </form>
                                <?php else: ?>
                                    <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Suspender «{name}»? Dejará de ser visible y nadie podrá publicar.', ['name' => $c['name']])) ?>" data-confirm-label="<?= e(t('Suspender')) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= (int) $c['id'] ?>">
                                        <input type="hidden" name="action" value="suspend">
                                        <label class="field__label" for="suspend-<?= (int) $c['id'] ?>"><?= e(t('Motivo de la suspensión')) ?></label>
                                        <input class="input" id="suspend-<?= (int) $c['id'] ?>" name="reason" required minlength="5" maxlength="255">
                                        <button type="submit" class="btn btn--secondary btn--sm btn--block"><?= icon('ban') ?> <?= e(t('Suspender')) ?></button>
                                    </form>
                                <?php endif; ?>
                                <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Eliminar «{name}» y todas sus publicaciones? No se puede deshacer.', ['name' => $c['name']])) ?>" data-confirm-label="<?= e(t('Eliminar')) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= (int) $c['id'] ?>">
                                    <input type="hidden" name="action" value="delete">
                                    <label class="field__label" for="delete-<?= (int) $c['id'] ?>"><?= e(t('Motivo de la eliminación')) ?></label>
                                    <input class="input" id="delete-<?= (int) $c['id'] ?>" name="reason" required minlength="5" maxlength="255">
                                    <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('trash-2') ?> <?= e(t('Eliminar comunidad')) ?></button>
                                </form>
                            </div>
                        </details>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
