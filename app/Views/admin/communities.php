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
        <input class="input" type="search" name="q" value="<?= e($q) ?>" maxlength="100" placeholder="Nombre de la comunidad" aria-label="Buscar comunidades">
    </div>
    <div class="select-wrap">
        <select class="select" name="status" aria-label="Estado">
            <option value="">Todos los estados</option>
            <?php foreach (Community::STATUS_LABELS as $key => $label): ?>
                <option value="<?= e($key) ?>"<?= $status === $key ? ' selected' : '' ?>><?= e($label) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn--secondary">Buscar</button>
</form>

<section class="panel">
    <?php if ($communities === []): ?>
        <div class="panel__empty">
            <?= icon('users-round') ?>
            <p>No hay comunidades con estos filtros.</p>
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
                            <span class="chip chip--muted"><?= e(Community::VISIBILITIES[$c['visibility']] ?? '') ?></span>
                            <?php if ($suspended): ?><span class="chip chip--danger">Suspendida</span><?php endif; ?>
                            <?php if ((int) $c['open_reports'] > 0): ?>
                                <a class="chip chip--danger" href="<?= e(url('admin/reports.php', ['type' => 'community', 'id' => $c['id']])) ?>"><?= icon('flag') ?> <?= (int) $c['open_reports'] ?></a>
                            <?php endif; ?>
                        </p>
                        <p class="content-row__muted">
                            Administra <a href="<?= e(url('admin/users.php', ['id' => $c['owner_id']])) ?>">@<?= e($c['owner_username']) ?></a>
                            · <?= compact_number((int) $c['members_count']) ?> <?= plural((int) $c['members_count'], 'miembro', 'miembros') ?>
                            · <?= compact_number((int) $c['posts_count']) ?> <?= plural((int) $c['posts_count'], 'publicación', 'publicaciones') ?>
                            · creada <?= time_tag((string) $c['created_at']) ?>
                        </p>
                    </div>
                    <div class="content-row__actions">
                        <?php if (!$suspended): ?>
                            <a class="btn btn--ghost btn--sm" href="<?= e(community_url($c)) ?>" target="_blank" rel="noopener"><?= icon('external-link') ?> Ver</a>
                        <?php endif; ?>
                        <details class="admin-menu">
                            <summary class="btn btn--ghost btn--sm"><?= icon('settings') ?> Moderar</summary>
                            <div class="admin-menu__panel">
                                <?php if ($suspended): ?>
                                    <form method="post" action="<?= e($action) ?>" data-confirm="¿Reactivar «<?= e($c['name']) ?>»?" data-confirm-label="Reactivar">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= (int) $c['id'] ?>">
                                        <input type="hidden" name="action" value="restore">
                                        <button type="submit" class="btn btn--secondary btn--sm btn--block"><?= icon('rotate-ccw') ?> Reactivar</button>
                                    </form>
                                <?php else: ?>
                                    <form method="post" action="<?= e($action) ?>" data-confirm="¿Suspender «<?= e($c['name']) ?>»? Dejará de ser visible y nadie podrá publicar." data-confirm-label="Suspender">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= (int) $c['id'] ?>">
                                        <input type="hidden" name="action" value="suspend">
                                        <label class="field__label" for="suspend-<?= (int) $c['id'] ?>">Motivo de la suspensión</label>
                                        <input class="input" id="suspend-<?= (int) $c['id'] ?>" name="reason" required minlength="5" maxlength="255">
                                        <button type="submit" class="btn btn--secondary btn--sm btn--block"><?= icon('ban') ?> Suspender</button>
                                    </form>
                                <?php endif; ?>
                                <form method="post" action="<?= e($action) ?>" data-confirm="¿Eliminar «<?= e($c['name']) ?>» y todas sus publicaciones? No se puede deshacer." data-confirm-label="Eliminar">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= (int) $c['id'] ?>">
                                    <input type="hidden" name="action" value="delete">
                                    <label class="field__label" for="delete-<?= (int) $c['id'] ?>">Motivo de la eliminación</label>
                                    <input class="input" id="delete-<?= (int) $c['id'] ?>" name="reason" required minlength="5" maxlength="255">
                                    <button type="submit" class="btn btn--danger btn--sm btn--block"><?= icon('trash-2') ?> Eliminar comunidad</button>
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
