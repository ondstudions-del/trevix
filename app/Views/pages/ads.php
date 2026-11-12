<?php

use Trevix\Core\View;
use Trevix\Models\Ad;

/**
 * OND-ADS: crear un anuncio (publicación, comunidad o grupo propios, o anuncio libre) y «Mis anuncios».
 *
 * @var string      $tab
 * @var array       $tabs
 * @var array|null  $summary  AdService::summary()
 * @var list<array> $items    (mis anuncios) AdService::presentOwn()
 * @var string|null $nextUrl
 * @var array       $preset   ['kind' => '', 'target' => 0] elegido desde «Promocionar»
 * @var array       $errors, $old
 */
$action = url('ads.php', ['tab' => $tab === 'create' ? null : $tab]);
$kind = (string) ($old['kind'] ?? '') ?: ($preset['kind'] ?: 'post');
$targetId = (int) ($old['target_id'] ?? 0) ?: (int) $preset['target'];
$days = max(1, (int) ($old['days'] ?? 3));
$kindIcons = ['post' => 'file-text', 'community' => 'users-round', 'group' => 'users', 'custom' => 'megaphone'];
$statusChip = static fn (string $status): string => match ($status) {
    'active'   => 'chip--success',
    'pending'  => 'chip--brand',
    'finished' => 'chip--muted',
    default    => 'chip--danger',
};
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('wallet.php')) ?>" aria-label="<?= e(t('Volver')) ?>"><?= icon('arrow-left') ?></a>
        <h1 class="page-header__title page-header__title--visible">OND-ADS</h1>
    </div>
    <nav class="tabs" aria-label="OND-ADS">
        <?php foreach ($tabs as $key => $item): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('ads.php', ['tab' => $key === 'create' ? null : $key])) ?>"
                <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e(t($item['label'])) ?></a>
        <?php endforeach; ?>
    </nav>
</header>

<div class="appeals-page wallet-page ads-page">
<?php if ($summary === null): ?>
    <?php View::partial('empty-state', ['icon' => 'megaphone', 'heading' => 'Inicia sesión para anunciarte', 'text' => 'Con OND-ADS promocionas tus publicaciones, comunidades y grupos en el feed.']); ?>
<?php else: ?>
    <section class="card appeals-section wallet-balance gift-balance">
        <div>
            <p class="wallet-balance__label"><?= e(t('Saldo disponible')) ?></p>
            <p class="wallet-balance__amount"><?= e($summary['balance']['formatted']) ?></p>
        </div>
        <a class="btn btn--secondary btn--sm" href="<?= e(url('wallet.php')) ?>#recargar"><?= icon('plus') ?> <?= e(t('Recargar')) ?></a>
    </section>

    <?php if ($tab === 'create'): ?>
        <section class="card appeals-section ads-intro">
            <h2><?= icon('megaphone') ?> <?= e(t('Llega a más personas')) ?></h2>
            <p class="appeals-item__text">
                <?= e(t('Tu anuncio aparece en el feed como «Patrocinado». Cuesta {price} por día y cada día lo ven entre {min} y {max} personas distintas.', [
                    'price' => $summary['daily_price']['formatted'], 'min' => $summary['reach_min'], 'max' => $summary['reach_max'],
                ])) ?>
            </p>
            <p class="appeals-item__meta">
                <?= e(t('Se paga con tu monedero al crearlo y el equipo lo revisa antes de mostrarlo: si lo rechaza, te devolvemos todo. Si un día llega a menos de {min} personas, te devolvemos la parte proporcional.', ['min' => $summary['reach_min']])) ?>
            </p>
        </section>

        <?php if (!$summary['enabled']): ?>
            <?php View::partial('empty-state', ['icon' => 'megaphone', 'heading' => 'OND-ADS está en pausa', 'text' => 'Por ahora no se aceptan anuncios nuevos. Vuelve a intentarlo más tarde.']); ?>
        <?php else: ?>
            <form class="card appeals-section form ads-form" method="post" action="<?= e($action) ?>" enctype="multipart/form-data" novalidate
                data-ads-form data-daily-cents="<?= (int) $summary['daily_price']['cents'] ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="create">

                <fieldset class="field">
                    <legend class="field__label"><?= e(t('¿Qué quieres anunciar?')) ?></legend>
                    <div class="ads-kinds">
                        <?php foreach (Ad::KINDS as $key => $label): ?>
                            <label class="ads-kind">
                                <input type="radio" name="kind" value="<?= e($key) ?>"<?= $kind === $key ? ' checked' : '' ?> data-ads-kind>
                                <span class="ads-kind__box"><?= icon($kindIcons[$key]) ?> <?= e(t($label)) ?></span>
                            </label>
                        <?php endforeach; ?>
                    </div>
                    <?= field_error($errors, 'kind', 'ad-kind') ?>
                </fieldset>

                <fieldset class="field ads-panel" data-ads-panel="post">
                    <legend class="field__label"><?= e(t('Elige una publicación pública')) ?></legend>
                    <?php if ($summary['targets']['posts'] === []): ?>
                        <p class="appeals-item__meta"><?= e(t('No tienes publicaciones públicas para promocionar.')) ?> <a href="<?= e(url('feed.php')) ?>"><?= e(t('Publica algo')) ?></a></p>
                    <?php else: ?>
                        <div class="ads-targets">
                            <?php foreach ($summary['targets']['posts'] as $p): ?>
                                <label class="ads-target">
                                    <input type="radio" name="target_id_post" value="<?= (int) $p['id'] ?>"<?= $kind === 'post' && $targetId === $p['id'] ? ' checked' : '' ?>>
                                    <?php if ($p['thumb'] !== null): ?><img class="ads-target__thumb" src="<?= e(url($p['thumb'])) ?>" alt="" loading="lazy"><?php else: ?><span class="ads-target__thumb ads-target__thumb--icon"><?= icon('file-text') ?></span><?php endif; ?>
                                    <span class="ads-target__text"><?= e($p['excerpt']) ?><small><?= e(time_ago($p['created_at'])) ?></small></span>
                                </label>
                            <?php endforeach; ?>
                        </div>
                    <?php endif; ?>
                    <?= $kind === 'post' ? field_error($errors, 'target_id', 'ad-target-post') : '' ?>
                </fieldset>

                <fieldset class="field ads-panel" data-ads-panel="community">
                    <legend class="field__label"><?= e(t('Elige una comunidad pública que administres')) ?></legend>
                    <?php if ($summary['targets']['communities'] === []): ?>
                        <p class="appeals-item__meta"><?= e(t('No administras comunidades públicas.')) ?> <a href="<?= e(url('communities.php')) ?>"><?= e(t('Ver comunidades')) ?></a></p>
                    <?php else: ?>
                        <div class="ads-targets">
                            <?php foreach ($summary['targets']['communities'] as $c): ?>
                                <label class="ads-target">
                                    <input type="radio" name="target_id_community" value="<?= (int) $c['id'] ?>"<?= $kind === 'community' && $targetId === $c['id'] ? ' checked' : '' ?>>
                                    <?= community_icon($c) ?>
                                    <span class="ads-target__text"><?= e($c['name']) ?><small><?= e(tn($c['members_count'], '{n} miembro', '{n} miembros', ['n' => compact_number($c['members_count'])])) ?></small></span>
                                </label>
                            <?php endforeach; ?>
                        </div>
                    <?php endif; ?>
                    <?= $kind === 'community' ? field_error($errors, 'target_id', 'ad-target-community') : '' ?>
                </fieldset>

                <fieldset class="field ads-panel" data-ads-panel="group">
                    <legend class="field__label"><?= e(t('Elige un grupo público que administres')) ?></legend>
                    <?php if ($summary['targets']['groups'] === []): ?>
                        <p class="appeals-item__meta"><?= e(t('No administras grupos públicos. Puedes hacer público un grupo desde su información en Mensajes.')) ?></p>
                    <?php else: ?>
                        <div class="ads-targets">
                            <?php foreach ($summary['targets']['groups'] as $g): ?>
                                <label class="ads-target">
                                    <input type="radio" name="target_id_group" value="<?= (int) $g['id'] ?>"<?= $kind === 'group' && $targetId === $g['id'] ? ' checked' : '' ?>>
                                    <?= avatar(['avatar_path' => $g['avatar_path'], 'username' => $g['title'], 'display_name' => $g['title']], 'sm') ?>
                                    <span class="ads-target__text"><?= e($g['title']) ?><small><?= e(tn($g['members_count'], '{n} miembro', '{n} miembros', ['n' => compact_number($g['members_count'])])) ?></small></span>
                                </label>
                            <?php endforeach; ?>
                        </div>
                    <?php endif; ?>
                    <?= $kind === 'group' ? field_error($errors, 'target_id', 'ad-target-group') : '' ?>
                </fieldset>

                <fieldset class="ads-panel" data-ads-panel="custom">
                    <legend class="field__label"><?= e(t('Tu anuncio')) ?></legend>
                    <div class="field">
                        <label class="field__label" for="ad-title"><?= e(t('Título')) ?></label>
                        <input class="input" id="ad-title" name="title" maxlength="80" value="<?= e((string) ($old['title'] ?? '')) ?>"<?= invalid_attrs($errors, 'title', 'ad-title') ?>>
                        <?= field_error($errors, 'title', 'ad-title') ?>
                    </div>
                    <div class="field">
                        <label class="field__label" for="ad-body"><?= e(t('Texto')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                        <textarea class="input" id="ad-body" name="body" rows="3" maxlength="300"<?= invalid_attrs($errors, 'body', 'ad-body') ?>><?= e((string) ($old['body'] ?? '')) ?></textarea>
                        <?= field_error($errors, 'body', 'ad-body') ?>
                    </div>
                    <div class="field">
                        <label class="field__label" for="ad-image"><?= e(t('Imagen')) ?> <span class="field__hint"><?= e(t('(opcional · JPG, PNG o WEBP)')) ?></span></label>
                        <input class="input" id="ad-image" name="image" type="file" accept="image/jpeg,image/png,image/webp"<?= invalid_attrs($errors, 'image', 'ad-image') ?>>
                        <?= field_error($errors, 'image', 'ad-image') ?>
                    </div>
                    <div class="field">
                        <label class="field__label" for="ad-link"><?= e(t('Enlace del botón')) ?></label>
                        <input class="input" id="ad-link" name="link_url" type="url" maxlength="500" placeholder="https://" value="<?= e((string) ($old['link_url'] ?? '')) ?>"<?= invalid_attrs($errors, 'link_url', 'ad-link') ?>>
                        <?= field_error($errors, 'link_url', 'ad-link') ?>
                    </div>
                    <div class="field">
                        <label class="field__label" for="ad-cta"><?= e(t('Texto del botón')) ?></label>
                        <div class="select-wrap">
                            <select class="select" id="ad-cta" name="cta"<?= invalid_attrs($errors, 'cta', 'ad-cta') ?>>
                                <?php foreach ($summary['ctas'] as $c): ?>
                                    <option value="<?= e($c['id']) ?>"<?= ($old['cta'] ?? 'learn_more') === $c['id'] ? ' selected' : '' ?>><?= e($c['label']) ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                        <?= field_error($errors, 'cta', 'ad-cta') ?>
                    </div>
                </fieldset>

                <div class="field">
                    <label class="field__label" for="ad-days"><?= e(t('Días')) ?></label>
                    <input class="input wallet-rule-input" id="ad-days" name="days" type="number" min="1" max="<?= (int) $summary['max_days'] ?>" required
                        value="<?= $days ?>" data-ads-days<?= invalid_attrs($errors, 'days', 'ad-days') ?>>
                    <?= field_error($errors, 'days', 'ad-days') ?>
                    <p class="field__hint">
                        <?= e(t('Hasta {n} días.', ['n' => $summary['max_days']])) ?>
                        <span data-ads-total hidden></span>
                    </p>
                </div>
                <button type="submit" class="btn btn--primary"><?= icon('megaphone') ?> <?= e(t('Pagar y enviar a revisión')) ?></button>
            </form>
        <?php endif; ?>
        <script src="<?= e(asset('js/ads.js')) ?>" defer></script>

    <?php else: ?>
        <?php if ($items === []): ?>
            <?php View::partial('empty-state', ['icon' => 'megaphone', 'heading' => 'Todavía no creaste anuncios', 'text' => 'Promociona una publicación, una comunidad o un grupo para llegar a más personas.']); ?>
        <?php else: ?>
            <ul class="ads-list">
                <?php foreach ($items as $a): ?>
                    <li class="card appeals-section ads-item" id="anuncio-<?= (int) $a['id'] ?>">
                        <p class="appeals-item__text">
                            <span class="chip <?= $statusChip($a['status']) ?>"><?= e($a['status_label']) ?></span>
                            <span class="chip chip--muted"><?= icon($kindIcons[$a['kind']] ?? 'megaphone') ?> <?= e($a['kind_label']) ?></span>
                        </p>
                        <p class="ads-item__target"><strong><?= e($a['target']) ?></strong></p>
                        <dl class="ads-item__stats">
                            <div><dt><?= e(t('Personas alcanzadas')) ?></dt><dd><?= e(compact_number($a['impressions'])) ?></dd></div>
                            <div><dt><?= e(t('Toques')) ?></dt><dd><?= e(compact_number($a['clicks'])) ?></dd></div>
                            <div><dt><?= e(t('Pagado')) ?></dt><dd><?= e($a['total']['formatted']) ?></dd></div>
                            <?php if ($a['refunded']['cents'] > 0): ?>
                                <div><dt><?= e(t('Devuelto')) ?></dt><dd><?= e($a['refunded']['formatted']) ?></dd></div>
                            <?php endif; ?>
                        </dl>
                        <p class="appeals-item__meta">
                            <?= e(tn($a['days'], '{n} día', '{n} días', ['n' => $a['days']])) ?>
                            · <?= e(t('{min}–{max} personas por día', ['min' => $a['reach_min'], 'max' => $a['reach_max']])) ?>
                            <?php if ($a['days_left'] !== null): ?> · <?= e(tn($a['days_left'], 'Queda {n} día', 'Quedan {n} días', ['n' => $a['days_left']])) ?><?php endif; ?>
                            · <?= e(t('Creado {date}', ['date' => full_date($a['created_at'], false)])) ?>
                        </p>
                        <?php if (!empty($a['review_note'])): ?>
                            <p class="appeals-item__meta"><?= e(t('Motivo: {reason}', ['reason' => $a['review_note']])) ?></p>
                        <?php endif; ?>
                        <?php if ($a['can_cancel']): ?>
                            <form method="post" action="<?= e($action) ?>"
                                data-confirm="<?= e($a['status'] === 'pending'
                                    ? t('¿Cancelar el anuncio? Te devolveremos todo el pago.')
                                    : t('¿Cancelar el anuncio? Dejará de mostrarse y te devolveremos los días que faltan.')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="cancel">
                                <input type="hidden" name="id" value="<?= (int) $a['id'] ?>">
                                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('circle-x') ?> <?= e(t('Cancelar anuncio')) ?></button>
                            </form>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
            <?php if ($nextUrl !== null): ?>
                <p><a class="btn btn--ghost btn--block" href="<?= e($nextUrl) ?>"><?= e(t('Ver más')) ?></a></p>
            <?php endif; ?>
        <?php endif; ?>
    <?php endif; ?>
<?php endif; ?>
</div>
