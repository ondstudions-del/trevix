<?php

use Trevix\Controllers\Admin\ContentController;
use Trevix\Core\View;
use Trevix\Services\Moderation;

/**
 * @var string      $tab     posts | comments
 * @var string      $q
 * @var string|null $status
 * @var array       $items
 * @var array|null  $staff
 */
$canModerate = static fn (array $row): bool => $staff !== null
    && Moderation::canModerateContentOf($staff, ['id' => $row['user_id'], 'role' => $row['author_role']]);
$canFeature = $staff !== null && Moderation::isAdmin($staff);
$isPublic = static fn (array $row): bool => $row['visibility'] === 'public'
    && ($row['community_visibility'] ?? 'public') === 'public';
$action = url('admin/content.php');
?>
<nav class="admin-tabs" aria-label="<?= e(t('Tipo de contenido')) ?>">
    <?php foreach (ContentController::TABS as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('admin/content.php', ['tab' => $key])) ?>"
            <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e(t($label)) ?></a>
    <?php endforeach; ?>
</nav>

<form class="admin-search" method="get" action="<?= e($action) ?>" role="search">
    <input type="hidden" name="tab" value="<?= e($tab) ?>">
    <div class="input-wrap">
        <?= icon('search') ?>
        <input class="input" type="search" name="q" value="<?= e($q) ?>" maxlength="100"
            placeholder="<?= e(t('Buscar texto o @usuario')) ?>" aria-label="<?= e(t('Buscar contenido')) ?>">
    </div>
    <?php if ($tab === 'posts'): ?>
        <div class="select-wrap">
            <select class="select" name="status" aria-label="<?= e(t('Estado')) ?>">
                <option value=""><?= e(t('Todos los estados')) ?></option>
                <?php foreach (ContentController::POST_STATUSES as $key => $label): ?>
                    <option value="<?= e($key) ?>"<?= $status === $key ? ' selected' : '' ?>><?= e(t($label)) ?></option>
                <?php endforeach; ?>
            </select>
        </div>
    <?php endif; ?>
    <button type="submit" class="btn btn--secondary"><?= e(t('Buscar')) ?></button>
</form>

<section class="panel">
    <?php if ($items === []): ?>
        <div class="panel__empty">
            <?= icon('inbox') ?>
            <p><?= $q !== '' || $status !== null ? e(t('No hay resultados con estos filtros.')) : e(t('Todavía no hay contenido.')) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($items as $row): ?>
                <?php $hidden = ($row['status'] ?? 'published') === 'hidden'; ?>
                <li class="content-row">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <?= avatar($row, 'xs') ?>
                            <a href="<?= e(url('admin/users.php', ['id' => $row['user_id']])) ?>">@<?= e($row['username']) ?></a>
                            <?php if ($tab === 'posts' && !empty($row['community_name'])): ?>
                                <span class="content-row__muted"><?= e(t('en {community}', ['community' => $row['community_name']])) ?></span>
                            <?php endif; ?>
                            <span class="content-row__muted">· <?= time_tag((string) $row['created_at']) ?></span>
                            <?php if ($hidden): ?><span class="chip chip--warning"><?= e(t('Oculta')) ?></span><?php endif; ?>
                            <?php if ($tab === 'posts' && !empty($row['featured_at']) && !$hidden): ?><span class="chip chip--brand"><?= icon('star') ?> <?= e(t('Destacada')) ?></span><?php endif; ?>
                            <?php if ((int) $row['open_reports'] > 0): ?>
                                <a class="chip chip--danger" href="<?= e(url('admin/reports.php', ['type' => $tab === 'posts' ? 'post' : 'comment', 'id' => $row['id']])) ?>">
                                    <?= icon('flag') ?> <?= (int) $row['open_reports'] ?>
                                </a>
                            <?php endif; ?>
                        </p>
                        <p class="content-row__text">
                            <?php if ((string) $row['body'] !== ''): ?>
                                <?= e(mb_strimwidth((string) $row['body'], 0, 220, '…')) ?>
                            <?php elseif (empty($row['gif_url'])): ?>
                                <span class="content-row__muted"><?= !empty($row['shared_post_id']) ? e(t('Compartió una publicación')) : e(t('Sin texto')) ?></span>
                            <?php endif; ?>
                        </p>
                        <?php if (!empty($row['gif_url'])): ?>
                            <img class="content-row__gif" src="<?= e($row['gif_url']) ?>" alt="<?= $row['gif_kind'] === 'sticker' ? 'Sticker' : 'GIF' ?>" loading="lazy" height="90">
                        <?php endif; ?>
                        <p class="content-row__muted">
                            <?php if ($tab === 'posts'): ?>
                                <?php if ((int) $row['media_count'] > 0): ?><?= icon('image') ?> <?= (int) $row['media_count'] ?> · <?php endif; ?>
                                <?= icon('heart') ?> <?= compact_number((int) $row['likes_count']) ?> · <?= icon('message-circle') ?> <?= compact_number((int) $row['comments_count']) ?>
                            <?php else: ?>
                                <?= $row['parent_id'] !== null
                                    ? e(t('Respuesta en la publicación #{id}', ['id' => (int) $row['post_id']]))
                                    : e(t('Comentario en la publicación #{id}', ['id' => (int) $row['post_id']])) ?>
                            <?php endif; ?>
                        </p>
                    </div>
                    <div class="content-row__actions">
                        <?php if ($tab === 'posts' && !$hidden): ?>
                            <a class="btn btn--ghost btn--sm" href="<?= e(url('post.php', ['id' => $row['id']])) ?>" target="_blank" rel="noopener"><?= icon('external-link') ?> <?= e(t('Ver')) ?></a>
                            <?php $featured = !empty($row['featured_at']); ?>
                            <?php if ($canFeature && ($featured || $isPublic($row))): ?>
                                <form method="post" action="<?= e($action) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= (int) $row['id'] ?>">
                                    <input type="hidden" name="action" value="<?= $featured ? 'unfeature' : 'feature' ?>">
                                    <button type="submit" class="btn btn--ghost btn--sm"><?= icon('star') ?> <?= $featured ? e(t('Quitar destacado')) : e(t('Destacar')) ?></button>
                                </form>
                            <?php endif; ?>
                        <?php elseif ($tab === 'comments'): ?>
                            <a class="btn btn--ghost btn--sm" href="<?= e(url('post.php', ['id' => $row['post_id']]) . '#comentario-' . (int) $row['id']) ?>" target="_blank" rel="noopener"><?= icon('external-link') ?> <?= e(t('Ver')) ?></a>
                        <?php endif; ?>
                        <?php if ($canModerate($row)): ?>
                            <?php if ($tab === 'posts'): ?>
                                <form method="post" action="<?= e($action) ?>"
                                    <?= $hidden ? '' : 'data-confirm="' . e(t('¿Ocultar esta publicación? Dejará de verse en TREVIX hasta que la restaures.')) . '" data-confirm-label="' . e(t('Ocultar')) . '"' ?>>
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= (int) $row['id'] ?>">
                                    <input type="hidden" name="action" value="<?= $hidden ? 'restore' : 'hide' ?>">
                                    <button type="submit" class="btn btn--ghost btn--sm"><?= icon($hidden ? 'rotate-ccw' : 'eye-off') ?> <?= $hidden ? e(t('Restaurar')) : e(t('Ocultar')) ?></button>
                                </form>
                                <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Eliminar esta publicación de forma permanente? Se borrarán sus adjuntos y comentarios.')) ?>" data-confirm-label="<?= e(t('Eliminar')) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= (int) $row['id'] ?>">
                                    <input type="hidden" name="action" value="delete">
                                    <button type="submit" class="btn btn--danger-ghost btn--sm"><?= icon('trash-2') ?> <?= e(t('Eliminar')) ?></button>
                                </form>
                            <?php else: ?>
                                <form method="post" action="<?= e($action) ?>" data-confirm="<?= (int) $row['replies_count'] > 0 ? e(t('¿Eliminar este comentario y sus respuestas?')) : e(t('¿Eliminar este comentario?')) ?>" data-confirm-label="<?= e(t('Eliminar')) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= (int) $row['id'] ?>">
                                    <input type="hidden" name="action" value="delete_comment">
                                    <button type="submit" class="btn btn--danger-ghost btn--sm"><?= icon('trash-2') ?> <?= e(t('Eliminar')) ?></button>
                                </form>
                            <?php endif; ?>
                        <?php endif; ?>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
