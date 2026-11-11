<?php

use Trevix\Controllers\Admin\GiftsController;
use Trevix\Models\Gift;
use Trevix\Services\GiftService;
use Trevix\Services\WalletService;

/**
 * Regalos: catálogo (nombre, GIF o sticker subido o de GIPHY, costo, categoría y orden), categorías y comisión.
 *
 * @var string     $tab
 * @var array      $totals      Gift::totals()
 * @var array      $categories  Gift::categories(false)
 * @var int        $commission
 * @var array      $gifts        (regalos) Gift::adminList()
 * @var string     $giphyQuery, $giphyKind (regalos)
 * @var array      $giphyResults (regalos) resultados de GIPHY para elegir
 * @var string|null $giphyError
 * @var bool       $giphyEnabled
 * @var array|null $staff
 */
$action = url('admin/gifts.php', ['tab' => $tab === 'gifts' ? null : $tab]);
$money = static fn (int $cents): string => WalletService::money($cents);
$disabled = $staff === null ? ' disabled' : '';
$cards = [
    ['gift', t('Regalos enviados'), 'sends', false],
    ['wallet', t('Ventas de regalos'), 'sales', true],
    ['banknote', t('Comisiones de TREVIX'), 'commissions', true],
    ['inbox', t('Guardados en Mis regalos'), 'stored', false],
];
?>
<section class="stat-grid" aria-label="<?= e(t('Resumen de regalos')) ?>">
    <?php foreach ($cards as [$iconName, $label, $key, $isMoney]): ?>
        <article class="stat-card">
            <span class="stat-card__icon"><?= icon($iconName) ?></span>
            <p class="stat-card__label"><?= e($label) ?></p>
            <p class="stat-card__value"><?= isset($totals[$key]) ? e($isMoney ? $money($totals[$key]) : compact_number($totals[$key])) : '—' ?></p>
            <p class="stat-card__hint">
                <?php if (!isset($totals[$key])): ?>
                    <?= e(t('Se calcula al conectar la base de datos')) ?>
                <?php elseif ($key === 'commissions'): ?>
                    <?= e(t('Acreditado a quienes recibieron: {amount}', ['amount' => $money($totals['earnings'])])) ?>
                <?php else: ?>
                    <?= e(t('Datos en tiempo real')) ?>
                <?php endif; ?>
            </p>
        </article>
    <?php endforeach; ?>
</section>

<nav class="admin-tabs" aria-label="<?= e(t('Secciones de regalos')) ?>">
    <?php foreach (GiftsController::TABS as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('admin/gifts.php', ['tab' => $key === 'gifts' ? null : $key])) ?>"
            <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e(t($label)) ?></a>
    <?php endforeach; ?>
</nav>

<?php if ($tab === 'gifts'): ?>
    <?php
    /** Formulario de un regalo: $g = null para agregar uno nuevo. */
    $giftForm = static function (?array $g) use ($action, $categories, $disabled, $giphyResults, $giphyKind): void {
        $gid = $g !== null ? (int) $g['id'] : 0;
        ?>
        <form method="post" action="<?= e($action) ?>" enctype="multipart/form-data">
            <?= csrf_field() ?>
            <input type="hidden" name="action" value="save_gift">
            <input type="hidden" name="id" value="<?= $gid ?>">
            <label class="field__label" for="g-name-<?= $gid ?>"><?= e(t('Nombre del regalo')) ?></label>
            <input class="input" id="g-name-<?= $gid ?>" name="name" required minlength="2" maxlength="60" value="<?= e($g['name'] ?? '') ?>" placeholder="<?= e(t('Rosa')) ?>">
            <label class="field__label" for="g-cat-<?= $gid ?>"><?= e(t('Categoría')) ?></label>
            <select class="input" id="g-cat-<?= $gid ?>" name="category_id">
                <option value="0"><?= e(t('Otros (sin categoría)')) ?></option>
                <?php foreach ($categories as $c): ?>
                    <option value="<?= (int) $c['id'] ?>"<?= (int) ($g['category_id'] ?? 0) === (int) $c['id'] ? ' selected' : '' ?>><?= e($c['name']) ?></option>
                <?php endforeach; ?>
            </select>
            <label class="field__label" for="g-price-<?= $gid ?>"><?= e(t('Costo (USD)')) ?></label>
            <input class="input" id="g-price-<?= $gid ?>" name="price" inputmode="decimal" required maxlength="12"
                value="<?= e($g !== null ? number_format((int) $g['price_cents'] / 100, 2, '.', '') : '') ?>" placeholder="1.00">
            <label class="field__label" for="g-kind-<?= $gid ?>"><?= e(t('Tipo')) ?></label>
            <select class="input" id="g-kind-<?= $gid ?>" name="kind">
                <?php foreach (Gift::KINDS as $kind => $label): ?>
                    <option value="<?= e($kind) ?>"<?= ($g['kind'] ?? ($g === null ? $giphyKind : 'sticker')) === $kind ? ' selected' : '' ?>><?= e(t($label)) ?></option>
                <?php endforeach; ?>
            </select>
            <label class="field__label" for="g-media-<?= $gid ?>">
                <?= e($g === null ? t('GIF o sticker (GIF, PNG o WEBP, hasta 4 MB)') : t('Cambiar la imagen (opcional)')) ?>
            </label>
            <input class="input" id="g-media-<?= $gid ?>" name="media" type="file" accept="image/gif,image/png,image/webp">
            <label class="field__label" for="g-giphy-<?= $gid ?>"><?= e(t('…o enlace o id de GIPHY')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
            <input class="input" id="g-giphy-<?= $gid ?>" name="giphy_link" maxlength="300" autocomplete="off" placeholder="https://giphy.com/stickers/…">
            <?php if ($g === null && $giphyResults !== []): ?>
                <fieldset class="gift-picker">
                    <legend class="field__label"><?= e(t('…o elige uno de los resultados de GIPHY')) ?></legend>
                    <?php foreach ($giphyResults as $r): ?>
                        <label class="gift-picker__item" title="<?= e($r['title']) ?>">
                            <input type="radio" name="giphy" value="<?= e($r['id']) ?>">
                            <img src="<?= e($r['preview'] ?: $r['url']) ?>" alt="<?= e($r['title']) ?>" loading="lazy" width="88" height="88">
                        </label>
                    <?php endforeach; ?>
                </fieldset>
            <?php endif; ?>
            <label class="field__label" for="g-pos-<?= $gid ?>"><?= e(t('Orden')) ?></label>
            <input class="input" id="g-pos-<?= $gid ?>" name="position" type="number" min="0" max="999" value="<?= (int) ($g['position'] ?? 0) ?>">
            <label class="checkbox">
                <input type="checkbox" name="active" value="1"<?= $g === null || (int) $g['is_active'] === 1 ? ' checked' : '' ?>>
                <span><?= e(t('A la venta')) ?></span>
            </label>
            <button type="submit" class="btn btn--primary btn--sm btn--block"<?= $disabled ?>><?= icon('check') ?> <?= e($g === null ? t('Agregar regalo') : t('Guardar')) ?></button>
        </form>
        <?php
    };
    ?>
    <p class="content-row__muted">
        <?= e(t('Las personas compran los regalos con el saldo de su monedero y los envían desde un perfil, el chat privado, una publicación o reel, o una historia. Quien lo recibe gana el costo menos la comisión ({pct} %), y lo puede retirar.', ['pct' => $commission])) ?>
    </p>

    <section class="panel">
        <header class="panel__head">
            <h2><?= icon('plus') ?> <?= e(t('Agregar regalo')) ?></h2>
        </header>
        <?php if ($giphyEnabled): ?>
            <form class="gift-search" method="get" action="<?= e(url('admin/gifts.php')) ?>">
                <label class="sr-only" for="giphy-q"><?= e(t('Buscar en GIPHY')) ?></label>
                <input class="input" id="giphy-q" name="giphy" maxlength="50" value="<?= e($giphyQuery) ?>" placeholder="<?= e(t('Buscar en GIPHY: rosa, corazón, corona…')) ?>">
                <select class="input wallet-rule-input" name="giphy_kind" aria-label="<?= e(t('Tipo')) ?>">
                    <option value="sticker"<?= $giphyKind === 'sticker' ? ' selected' : '' ?>><?= e(t('Stickers')) ?></option>
                    <option value="gif"<?= $giphyKind === 'gif' ? ' selected' : '' ?>><?= e(t('GIF')) ?></option>
                </select>
                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('search') ?> <?= e(t('Buscar')) ?></button>
            </form>
            <?php if ($giphyError !== null): ?><p class="content-row__muted"><?= e($giphyError) ?></p><?php endif; ?>
            <?php if ($giphyQuery !== '' && $giphyResults === [] && $giphyError === null && $staff !== null): ?>
                <p class="content-row__muted"><?= e(t('GIPHY no encontró nada para «{query}».', ['query' => $giphyQuery])) ?></p>
            <?php endif; ?>
        <?php else: ?>
            <p class="content-row__muted"><?= e(t('GIPHY no está configurado: sube la imagen del regalo.')) ?></p>
        <?php endif; ?>
        <div class="gift-new"><?php $giftForm(null); ?></div>
    </section>

    <section class="panel">
        <header class="panel__head">
            <h2><?= icon('gift') ?> <?= e(t('Catálogo')) ?></h2>
        </header>
        <?php if ($gifts === []): ?>
            <div class="panel__empty">
                <?= icon('gift') ?>
                <p><?= e(t('Todavía no hay regalos. Agrega el primero arriba.')) ?></p>
            </div>
        <?php else: ?>
            <ul class="content-list">
                <?php foreach ($gifts as $g): ?>
                    <?php $gid = (int) $g['id']; ?>
                    <li class="content-row" id="regalo-<?= $gid ?>">
                        <img class="gift-thumb" src="<?= e(GiftService::mediaUrl(Gift::media($g))) ?>" alt="<?= e($g['name']) ?>" loading="lazy" width="64" height="64">
                        <div class="content-row__body">
                            <p class="content-row__author">
                                <strong><?= e($g['name']) ?></strong>
                                <span class="chip chip--brand"><?= e($money((int) $g['price_cents'])) ?></span>
                                <span class="chip <?= (int) $g['is_active'] === 1 ? 'chip--success' : 'chip--muted' ?>"><?= e((int) $g['is_active'] === 1 ? t('A la venta') : t('Oculto')) ?></span>
                                <span class="chip chip--muted"><?= e(t(Gift::KINDS[$g['kind']] ?? 'Sticker')) ?> · <?= e($g['source'] === 'giphy' ? 'GIPHY' : t('Subido')) ?></span>
                            </p>
                            <p class="content-row__muted">
                                <?= e($g['category_name'] ?? t('Otros')) ?> · <?= e(t('Orden {n}', ['n' => (int) $g['position']])) ?>
                                · <?= e(t('{n} enviados', ['n' => compact_number((int) $g['sends_count'])])) ?>
                                · <?= e(t('{n} guardados', ['n' => compact_number((int) $g['stored_count'])])) ?>
                            </p>
                        </div>
                        <div class="content-row__actions">
                            <details class="admin-menu">
                                <summary class="btn btn--ghost btn--sm"><?= icon('pencil') ?> <?= e(t('Editar')) ?></summary>
                                <div class="admin-menu__panel"><?php $giftForm($g); ?></div>
                            </details>
                            <form method="post" action="<?= e($action) ?>"
                                data-confirm="<?= e((int) $g['sends_count'] + (int) $g['stored_count'] > 0
                                    ? t('Este regalo ya se compró: lo ocultaremos del catálogo en lugar de borrarlo. ¿Continuar?')
                                    : t('¿Eliminar este regalo del catálogo?')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="delete_gift">
                                <input type="hidden" name="id" value="<?= $gid ?>">
                                <button type="submit" class="btn btn--ghost btn--sm"<?= $disabled ?>><?= icon('trash-2') ?> <?= e(t('Eliminar')) ?></button>
                            </form>
                        </div>
                    </li>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
    </section>

<?php elseif ($tab === 'categories'): ?>
    <p class="content-row__muted"><?= e(t('Las categorías ordenan el catálogo (por ejemplo Amor, Celebración, Premium). Las ocultas no se muestran, ni sus regalos.')) ?></p>
    <section class="panel">
        <ul class="content-list">
            <?php foreach ([...$categories, null] as $c): ?>
                <?php $cid = $c !== null ? (int) $c['id'] : 0; ?>
                <li class="content-row">
                    <div class="content-row__body">
                        <?php if ($c !== null): ?>
                            <p class="content-row__author">
                                <strong><?= e($c['name']) ?></strong>
                                <span class="chip <?= (int) $c['is_active'] === 1 ? 'chip--success' : 'chip--muted' ?>"><?= e((int) $c['is_active'] === 1 ? t('Visible') : t('Oculta')) ?></span>
                                <span class="chip chip--muted"><?= e(t('{n} regalos', ['n' => (int) $c['gifts_count']])) ?></span>
                            </p>
                            <p class="content-row__muted"><?= e(t('Orden {n}', ['n' => (int) $c['position']])) ?></p>
                        <?php else: ?>
                            <p class="content-row__author"><strong><?= icon('plus') ?> <?= e(t('Nueva categoría')) ?></strong></p>
                        <?php endif; ?>
                    </div>
                    <div class="content-row__actions">
                        <details class="admin-menu"<?= $c === null && $categories === [] ? ' open' : '' ?>>
                            <summary class="btn btn--<?= $c === null ? 'primary' : 'ghost' ?> btn--sm"><?= icon($c === null ? 'plus' : 'pencil') ?> <?= e($c === null ? t('Agregar') : t('Editar')) ?></summary>
                            <div class="admin-menu__panel">
                                <form method="post" action="<?= e($action) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="action" value="save_category">
                                    <input type="hidden" name="id" value="<?= $cid ?>">
                                    <label class="field__label" for="c-name-<?= $cid ?>"><?= e(t('Nombre')) ?></label>
                                    <input class="input" id="c-name-<?= $cid ?>" name="name" required minlength="2" maxlength="60" value="<?= e($c['name'] ?? '') ?>" placeholder="<?= e(t('Amor')) ?>">
                                    <label class="field__label" for="c-pos-<?= $cid ?>"><?= e(t('Orden')) ?></label>
                                    <input class="input" id="c-pos-<?= $cid ?>" name="position" type="number" min="0" max="999" value="<?= (int) ($c['position'] ?? 0) ?>">
                                    <label class="checkbox">
                                        <input type="checkbox" name="active" value="1"<?= $c === null || (int) $c['is_active'] === 1 ? ' checked' : '' ?>>
                                        <span><?= e(t('Visible en el catálogo')) ?></span>
                                    </label>
                                    <button type="submit" class="btn btn--primary btn--sm btn--block"<?= $disabled ?>><?= icon('check') ?> <?= e(t('Guardar')) ?></button>
                                </form>
                                <?php if ($c !== null): ?>
                                    <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Eliminar la categoría? Sus regalos quedarán en «Otros».')) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="action" value="delete_category">
                                        <input type="hidden" name="id" value="<?= $cid ?>">
                                        <button type="submit" class="btn btn--danger btn--sm btn--block"<?= $disabled ?>><?= icon('trash-2') ?> <?= e(t('Eliminar')) ?></button>
                                    </form>
                                <?php endif; ?>
                            </div>
                        </details>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    </section>

<?php else: ?>
    <form class="panel admin-settings" method="post" action="<?= e($action) ?>">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="save_commission">
        <header class="panel__head">
            <h2><?= icon('banknote') ?> <?= e(t('Comisión de TREVIX')) ?></h2>
        </header>
        <fieldset class="admin-settings__body"<?= $disabled ?>>
            <legend class="sr-only"><?= e(t('Comisión de los regalos')) ?></legend>
            <p class="admin-setting__text">
                <?= e(t('Con la comisión actual ({pct} %), de un regalo de US$ 10 quien lo recibe gana {net}. Los regalos guardados en Mis regalos usan lo que se pagó por ellos y la comisión vigente al enviarlos.', [
                    'pct' => $commission,
                    'net' => $money(1000 - intdiv(1000 * $commission + 50, 100)),
                ])) ?>
            </p>
            <div class="field admin-setting">
                <label class="admin-setting__title" for="gift-commission"><?= e(t('Comisión de TREVIX en regalos (%)')) ?></label>
                <input class="input wallet-rule-input" id="gift-commission" name="gift_commission" type="number" min="0" max="90" required value="<?= (int) $commission ?>">
            </div>
        </fieldset>
        <footer class="admin-settings__footer">
            <button type="submit" class="btn btn--primary"<?= $disabled ?>><?= icon('check') ?> <?= e(t('Guardar cambios')) ?></button>
        </footer>
    </form>
<?php endif; ?>
