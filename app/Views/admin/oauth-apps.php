<?php

use Trevix\Core\View;

/**
 * @var list<array> $items
 * @var bool        $hasMore
 * @var int         $pageNo
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
$action = url('admin/oauth-apps.php');
?>
<section class="panel" aria-labelledby="oauth-queue">
    <header class="panel__head">
        <h2 id="oauth-queue"><?= icon('app-window') ?> <?= e(t('Apps de desarrolladores')) ?></h2>
    </header>
    <?php if ($items === []): ?>
        <div class="panel__empty">
            <?= icon('app-window') ?>
            <p><?= e(t('No hay solicitudes de apps pendientes.')) ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($items as $app): ?>
                <li class="content-row" id="oauth-<?= (int) $app['id'] ?>">
                    <div class="content-row__media" aria-hidden="true">
                        <?php if (!empty($app['icon_url'])): ?>
                            <img src="<?= e($app['icon_url']) ?>" alt="" width="48" height="48" loading="lazy" style="border-radius:10px;object-fit:cover">
                        <?php else: ?>
                            <?= icon('app-window') ?>
                        <?php endif; ?>
                    </div>
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <strong><?= e($app['name']) ?></strong>
                            <span class="chip chip--muted"><?= e(t(ucfirst((string) $app['platform']))) ?></span>
                        </p>
                        <p><?= e($app['description']) ?></p>
                        <p class="muted">
                            <?php if (($app['platform'] ?? '') === 'web'): ?>
                                <?= e((string) ($app['website_url'] ?? '')) ?>
                            <?php else: ?>
                                <?= e((string) ($app['package_name'] ?? '')) ?>
                            <?php endif; ?>
                            · ID <?= e($app['client_id']) ?>
                        </p>
                        <?php if (!empty($app['owner'])): ?>
                            <p class="muted">@<?= e($app['owner']['username']) ?> · <?= e($app['owner']['display_name']) ?></p>
                        <?php endif; ?>
                    </div>
                    <div class="content-row__actions">
                        <form method="post" action="<?= e($action) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= (int) $app['id'] ?>">
                            <input type="hidden" name="action" value="approve">
                            <button type="submit" class="btn btn--primary btn--sm"><?= e(t('Aprobar')) ?></button>
                        </form>
                        <form method="post" action="<?= e($action) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= (int) $app['id'] ?>">
                            <input type="hidden" name="action" value="reject">
                            <input class="input" type="text" name="note" maxlength="500" placeholder="<?= e(t('Motivo (opcional)')) ?>">
                            <button type="submit" class="btn btn--danger btn--sm"><?= e(t('Rechazar')) ?></button>
                        </form>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
        <?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
    <?php endif; ?>
</section>
