<?php

use Trevix\Core\View;
use Trevix\Models\User;

/**
 * @var string      $q
 * @var string|null $role
 * @var string|null $status
 * @var array       $users
 */
$statusChip = ['active' => 'chip--success', 'suspended' => 'chip--danger', 'deactivated' => 'chip--muted'];
?>
<form class="admin-search" method="get" action="<?= e(url('admin/users.php')) ?>" role="search">
    <div class="input-wrap">
        <?= icon('search') ?>
        <input class="input" type="search" name="q" value="<?= e($q) ?>" maxlength="100"
            placeholder="<?= e(t('Usuario, nombre o correo')) ?>" aria-label="<?= e(t('Buscar cuentas')) ?>">
    </div>
    <div class="select-wrap">
        <select class="select" name="role" aria-label="<?= e(t('Rol')) ?>">
            <option value=""><?= e(t('Todos los roles')) ?></option>
            <?php foreach (User::ROLE_LABELS as $key => $label): ?>
                <option value="<?= e($key) ?>"<?= $role === $key ? ' selected' : '' ?>><?= e(t($label)) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <div class="select-wrap">
        <select class="select" name="status" aria-label="<?= e(t('Estado')) ?>">
            <option value=""><?= e(t('Todos los estados')) ?></option>
            <?php foreach (User::STATUS_LABELS as $key => $label): ?>
                <option value="<?= e($key) ?>"<?= $status === $key ? ' selected' : '' ?>><?= e(t($label)) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn--secondary"><?= e(t('Buscar')) ?></button>
</form>

<section class="panel">
    <?php if ($users === []): ?>
        <div class="panel__empty">
            <?= icon('users') ?>
            <p><?= e(t('No hay cuentas con estos filtros.')) ?></p>
        </div>
    <?php else: ?>
        <div class="table-wrap">
            <table class="admin-table">
                <thead>
                    <tr>
                        <th scope="col"><?= e(t('Cuenta')) ?></th>
                        <th scope="col"><?= e(t('Rol')) ?></th>
                        <th scope="col"><?= e(t('Estado')) ?></th>
                        <th scope="col" class="admin-table__num"><?= e(t('Publicaciones')) ?></th>
                        <th scope="col"><?= e(t('Fecha de alta')) ?></th>
                        <th scope="col"><span class="sr-only"><?= e(t('Acciones')) ?></span></th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($users as $u): ?>
                        <tr>
                            <td>
                                <div class="admin-table__user">
                                    <?= avatar($u, 'sm') ?>
                                    <div>
                                        <strong><?= e($u['display_name']) ?><?php if ($u['is_verified']): ?> <?= icon('badge-check', 'verified', t('Verificada')) ?><?php endif; ?></strong>
                                        <span>@<?= e($u['username']) ?> · <?= e($u['email']) ?></span>
                                    </div>
                                </div>
                            </td>
                            <td><?= e(t(User::ROLE_LABELS[$u['role']] ?? $u['role'])) ?></td>
                            <td>
                                <span class="chip <?= e($statusChip[$u['status']] ?? 'chip--muted') ?>"><?= e(t(User::STATUS_LABELS[$u['status']] ?? $u['status'])) ?></span>
                                <?php if ((int) $u['open_reports'] > 0): ?>
                                    <span class="chip chip--danger" title="<?= e(t('Reportes pendientes')) ?>"><?= icon('flag') ?> <?= (int) $u['open_reports'] ?></span>
                                <?php endif; ?>
                            </td>
                            <td class="admin-table__num"><?= compact_number((int) $u['posts_count']) ?></td>
                            <td><?= e(full_date((string) $u['created_at'], false)) ?></td>
                            <td class="admin-table__actions">
                                <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/users.php', ['id' => $u['id']])) ?>"><?= e(t('Gestionar')) ?></a>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
