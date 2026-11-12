<?php

use Trevix\Controllers\Admin\AdsController;
use Trevix\Core\View;
use Trevix\Services\WalletService;

/**
 * OND-ADS: revisión de anuncios pagados, activos, historial y ajustes.
 *
 * @var string     $tab
 * @var array|null $totals    Ad::totals() (null en la vista previa)
 * @var array      $settings  AdService::settings()
 * @var list<array> $items    AdService::presentOwn()
 * @var bool       $hasMore
 * @var int        $pageNo
 * @var array|null $staff
 */
$action = url('admin/ads.php', ['tab' => $tab === 'pending' ? null : $tab]);
$disabled = $staff === null ? ' disabled' : '';
$cards = [
    ['inbox', t('En revisión'), 'pending', false],
    ['megaphone', t('Activos'), 'active', false],
    ['wallet', t('Cobrado (sin devoluciones)'), 'revenue', true],
];
$statusChip = static fn (string $status): string => match ($status) {
    'active'   => 'chip--success',
    'pending'  => 'chip--brand',
    'finished' => 'chip--muted',
    default    => 'chip--danger',
};
?>
<section class="stat-grid" aria-label="<?= e(t('Resumen de OND-ADS')) ?>">
    <?php foreach ($cards as [$iconName, $label, $key, $isMoney]): ?>
        <article class="stat-card">
            <span class="stat-card__icon"><?= icon($iconName) ?></span>
            <p class="stat-card__label"><?= e($label) ?></p>
            <p class="stat-card__value"><?= $totals !== null ? e($isMoney ? WalletService::money($totals[$key]) : compact_number($totals[$key])) : '—' ?></p>
            <p class="stat-card__hint"><?= e($totals !== null ? t('Datos en tiempo real') : t('Se calcula al conectar la base de datos')) ?></p>
        </article>
    <?php endforeach; ?>
</section>

<nav class="admin-tabs" aria-label="<?= e(t('Secciones de OND-ADS')) ?>">
    <?php foreach (AdsController::TABS as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('admin/ads.php', ['tab' => $key === 'pending' ? null : $key])) ?>"
            <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e(t($label)) ?></a>
    <?php endforeach; ?>
</nav>

<?php if ($tab === 'settings'): ?>
    <form class="panel admin-settings" method="post" action="<?= e($action) ?>">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="save_settings">
        <header class="panel__head">
            <h2><?= icon('megaphone') ?> <?= e(t('Ajustes de OND-ADS')) ?></h2>
        </header>
        <fieldset class="admin-settings__body"<?= $disabled ?>>
            <legend class="sr-only"><?= e(t('Ajustes de OND-ADS')) ?></legend>
            <p class="admin-setting__text">
                <?= e(t('Cada día pagado, el anuncio se muestra en el feed a entre {min} y {max} personas distintas. Al terminar, por cada día que no llegó al mínimo se devuelve la parte proporcional. Los cambios se aplican a las campañas nuevas.', [
                    'min' => $settings['reach_min'], 'max' => $settings['reach_max'],
                ])) ?>
            </p>
            <label class="checkbox admin-setting">
                <input type="checkbox" name="ads_enabled" value="1"<?= $settings['enabled'] ? ' checked' : '' ?>>
                <span><?= e(t('Aceptar anuncios nuevos y mostrarlos en el feed')) ?></span>
            </label>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="ads-price"><?= e(t('Precio por día (USD)')) ?></label>
                <input class="input wallet-rule-input" id="ads-price" name="ads_daily_price" inputmode="decimal" required maxlength="10"
                    value="<?= e(number_format($settings['daily_cents'] / 100, 2, '.', '')) ?>">
            </div>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="ads-min"><?= e(t('Personas mínimas por día')) ?></label>
                <input class="input wallet-rule-input" id="ads-min" name="ads_reach_min" type="number" min="1" max="100000" required value="<?= (int) $settings['reach_min'] ?>">
            </div>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="ads-max"><?= e(t('Personas máximas por día')) ?></label>
                <input class="input wallet-rule-input" id="ads-max" name="ads_reach_max" type="number" min="1" max="100000" required value="<?= (int) $settings['reach_max'] ?>">
            </div>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="ads-days"><?= e(t('Días máximos por campaña')) ?></label>
                <input class="input wallet-rule-input" id="ads-days" name="ads_max_days" type="number" min="1" max="365" required value="<?= (int) $settings['max_days'] ?>">
            </div>
        </fieldset>
        <footer class="admin-settings__footer">
            <button type="submit" class="btn btn--primary"<?= $disabled ?>><?= icon('check') ?> <?= e(t('Guardar cambios')) ?></button>
        </footer>
    </form>
<?php else: ?>
    <section class="panel">
        <?php if ($items === []): ?>
            <div class="panel__empty">
                <?= icon('megaphone') ?>
                <p><?= e(match ($tab) {
                    'pending' => t('No hay anuncios esperando revisión.'),
                    'active'  => t('No hay anuncios activos.'),
                    default   => t('Todavía no hay anuncios terminados.'),
                }) ?></p>
            </div>
        <?php else: ?>
            <ul class="content-list">
                <?php foreach ($items as $a): ?>
                    <?php $aid = (int) $a['id']; ?>
                    <li class="content-row" id="anuncio-<?= $aid ?>">
                        <?php if ($a['user'] !== null): ?><?= avatar($a['user'], 'md') ?><?php endif; ?>
                        <div class="content-row__body">
                            <p class="content-row__author">
                                <?php if ($a['user'] !== null): ?>
                                    <a href="<?= e(profile_url($a['user'])) ?>"><strong><?= e($a['user']['display_name']) ?></strong></a>
                                    <span class="content-row__muted">@<?= e($a['user']['username']) ?></span>
                                <?php endif; ?>
                                <span class="chip <?= $statusChip($a['status']) ?>"><?= e($a['status_label']) ?></span>
                                <span class="chip chip--muted"><?= e($a['kind_label']) ?></span>
                                <span class="chip chip--brand"><?= e($a['total']['formatted']) ?> · <?= e(tn($a['days'], '{n} día', '{n} días', ['n' => $a['days']])) ?></span>
                            </p>
                            <?php if ($a['kind'] === 'custom'): ?>
                                <div class="ad-review">
                                    <?php if ($a['image_path'] !== null): ?>
                                        <a href="<?= e(url($a['image_path'])) ?>" target="_blank" rel="noopener"><img class="ad-review__img" src="<?= e(url($a['image_path'])) ?>" alt="" loading="lazy"></a>
                                    <?php endif; ?>
                                    <div>
                                        <p><strong><?= e($a['title']) ?></strong></p>
                                        <?php if ($a['body'] !== null): ?><p><?= nl2br(e($a['body'])) ?></p><?php endif; ?>
                                        <p class="content-row__muted">
                                            <?= e($a['cta_label']) ?> →
                                            <a href="<?= e($a['link_url']) ?>" target="_blank" rel="noopener noreferrer nofollow"><?= e($a['link_url']) ?></a>
                                        </p>
                                    </div>
                                </div>
                            <?php else: ?>
                                <p>
                                    <?php if ($a['kind'] === 'post' && $a['post_id'] !== null): ?>
                                        <a href="<?= e(url('post.php', ['id' => $a['post_id']])) ?>" target="_blank" rel="noopener"><?= e($a['target']) ?></a>
                                    <?php elseif ($a['kind'] === 'community' && $a['community_slug'] !== null): ?>
                                        <a href="<?= e(url('community.php', ['c' => $a['community_slug']])) ?>" target="_blank" rel="noopener"><?= e($a['target']) ?></a>
                                    <?php else: ?>
                                        <?= e($a['target']) ?>
                                    <?php endif; ?>
                                </p>
                            <?php endif; ?>
                            <p class="content-row__muted">
                                <?= e(t('Creado {date}', ['date' => full_date($a['created_at'])])) ?>
                                <?php if ($a['status'] !== 'pending'): ?>
                                    · <?= e(t('{n} personas alcanzadas', ['n' => compact_number($a['impressions'])])) ?>
                                    · <?= e(t('{n} toques', ['n' => compact_number($a['clicks'])])) ?>
                                <?php endif; ?>
                                <?php if ($a['days_left'] !== null): ?> · <?= e(tn($a['days_left'], 'Queda {n} día', 'Quedan {n} días', ['n' => $a['days_left']])) ?><?php endif; ?>
                                <?php if ($a['refunded']['cents'] > 0): ?> · <?= e(t('Devuelto: {amount}', ['amount' => $a['refunded']['formatted']])) ?><?php endif; ?>
                            </p>
                            <?php if (!empty($a['review_note'])): ?>
                                <p class="content-row__muted"><?= e(t('Motivo: {reason}', ['reason' => $a['review_note']])) ?></p>
                            <?php endif; ?>
                        </div>
                        <div class="content-row__actions">
                            <?php if ($a['status'] === 'pending'): ?>
                                <form method="post" action="<?= e($action) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="action" value="approve">
                                    <input type="hidden" name="id" value="<?= $aid ?>">
                                    <button type="submit" class="btn btn--primary btn--sm"<?= $disabled ?>><?= icon('check') ?> <?= e(t('Aprobar')) ?></button>
                                </form>
                                <details class="admin-menu">
                                    <summary class="btn btn--ghost btn--sm"><?= icon('circle-x') ?> <?= e(t('Rechazar')) ?></summary>
                                    <div class="admin-menu__panel">
                                        <form method="post" action="<?= e($action) ?>">
                                            <?= csrf_field() ?>
                                            <input type="hidden" name="action" value="reject">
                                            <input type="hidden" name="id" value="<?= $aid ?>">
                                            <label class="field__label" for="reject-<?= $aid ?>"><?= e(t('Motivo (lo verá la persona)')) ?></label>
                                            <textarea class="input" id="reject-<?= $aid ?>" name="note" rows="3" required maxlength="255"></textarea>
                                            <button type="submit" class="btn btn--danger btn--sm btn--block"<?= $disabled ?>><?= e(t('Rechazar y devolver el pago')) ?></button>
                                        </form>
                                    </div>
                                </details>
                            <?php elseif ($a['status'] === 'active'): ?>
                                <details class="admin-menu">
                                    <summary class="btn btn--ghost btn--sm"><?= icon('ban') ?> <?= e(t('Retirar')) ?></summary>
                                    <div class="admin-menu__panel">
                                        <form method="post" action="<?= e($action) ?>">
                                            <?= csrf_field() ?>
                                            <input type="hidden" name="action" value="remove">
                                            <input type="hidden" name="id" value="<?= $aid ?>">
                                            <label class="field__label" for="remove-<?= $aid ?>"><?= e(t('Motivo (lo verá la persona)')) ?></label>
                                            <textarea class="input" id="remove-<?= $aid ?>" name="note" rows="3" required maxlength="255"></textarea>
                                            <button type="submit" class="btn btn--danger btn--sm btn--block"<?= $disabled ?>><?= e(t('Retirar y devolver los días restantes')) ?></button>
                                        </form>
                                    </div>
                                </details>
                            <?php endif; ?>
                        </div>
                    </li>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
    </section>
    <?php View::partial('admin-pager', [
        'prevUrl' => $pageNo > 1 ? url('admin/ads.php', ['tab' => $tab === 'pending' ? null : $tab, 'page' => $pageNo - 1]) : null,
        'nextUrl' => $hasMore ? url('admin/ads.php', ['tab' => $tab === 'pending' ? null : $tab, 'page' => $pageNo + 1]) : null,
    ]); ?>
<?php endif; ?>
