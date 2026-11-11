<?php

use Trevix\Core\View;

/**
 * Regalos: tienda, «Mis regalos», recibidos y enviados. Con $target, la tienda envía el regalo a esa persona.
 *
 * @var string      $tab
 * @var array       $tabs
 * @var array|null  $summary  GiftService::summary()
 * @var array|null  $target   ['user' => fila, 'context' => profile|message|post|story, 'ref' => id, 'back' => url]
 * @var array       $history  (recibidos / enviados) GiftService::presentSend()
 * @var string|null $nextUrl
 */
$history = $history ?? [];
$action = url('gifts.php', ['tab' => $tab === 'shop' ? null : $tab]);
$sending = $target !== null;
$inventoryById = [];
foreach ($summary['inventory'] ?? [] as $item) {
    $inventoryById[$item['id']] = $item;
}
$contextLabel = [
    'message' => 'en el chat',
    'post'    => 'por su publicación',
    'story'   => 'por su historia',
    'profile' => 'en su perfil',
];
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e($sending ? $target['back'] : url('wallet.php')) ?>" aria-label="<?= e(t('Volver')) ?>"><?= icon('arrow-left') ?></a>
        <h1 class="page-header__title page-header__title--visible"><?= e($sending ? t('Enviar un regalo') : t('Regalos')) ?></h1>
    </div>
    <?php if (!$sending): ?>
        <nav class="tabs" aria-label="<?= e(t('Regalos')) ?>">
            <?php foreach ($tabs as $key => $item): ?>
                <a class="<?= cx('tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('gifts.php', ['tab' => $key === 'shop' ? null : $key])) ?>"
                    <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e(t($item['label'])) ?></a>
            <?php endforeach; ?>
        </nav>
    <?php endif; ?>
</header>

<div class="appeals-page wallet-page">
<?php if ($summary === null): ?>
    <?php View::partial('empty-state', ['icon' => 'gift', 'heading' => 'Inicia sesión para enviar regalos', 'text' => 'Los regalos se pagan con el saldo de tu monedero.']); ?>
<?php else: ?>
    <section class="card appeals-section wallet-balance gift-balance">
        <div>
            <p class="wallet-balance__label"><?= e(t('Saldo disponible')) ?></p>
            <p class="wallet-balance__amount"><?= e($summary['balance']['formatted']) ?></p>
        </div>
        <a class="btn btn--secondary btn--sm" href="<?= e(url('wallet.php')) ?>#recargar"><?= icon('plus') ?> <?= e(t('Recargar')) ?></a>
    </section>

    <?php if ($sending): ?>
        <?php $u = $target['user']; ?>
        <section class="card appeals-section gift-target">
            <?= avatar($u, 'md') ?>
            <div>
                <p class="appeals-item__text"><strong><?= e($u['display_name']) ?></strong> <span class="appeals-item__meta">@<?= e($u['username']) ?></span></p>
                <p class="appeals-item__meta">
                    <?= e(t('Elige un regalo para enviarle {where}. Recibirá su valor menos la comisión de TREVIX ({pct} %).', [
                        'where' => t($contextLabel[$target['context']] ?? 'en su perfil'), 'pct' => $summary['commission'],
                    ])) ?>
                </p>
            </div>
        </section>
    <?php endif; ?>

    <?php if ($tab === 'shop'): ?>
        <?php if ($sending && $summary['inventory'] !== []): ?>
            <section class="card appeals-section">
                <h2><?= icon('inbox') ?> <?= e(t('De Mis regalos')) ?></h2>
                <div class="gift-grid">
                    <?php foreach ($summary['inventory'] as $g): ?>
                        <article class="gift-card">
                            <img class="gift-card__media" src="<?= e($g['media_url']) ?>" alt="" loading="lazy">
                            <p class="gift-card__name"><?= e($g['name']) ?></p>
                            <p class="gift-card__price"><?= e(plural($g['quantity'], 'guardado', 'guardados')) ?></p>
                            <form method="post" action="<?= e($action) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="send">
                                <input type="hidden" name="gift_id" value="<?= (int) $g['id'] ?>">
                                <input type="hidden" name="source" value="inventory">
                                <input type="hidden" name="to" value="<?= e($target['user']['username']) ?>">
                                <input type="hidden" name="context" value="<?= e($target['context']) ?>">
                                <input type="hidden" name="ref" value="<?= (int) $target['ref'] ?>">
                                <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('send') ?> <?= e(t('Enviar')) ?></button>
                            </form>
                        </article>
                    <?php endforeach; ?>
                </div>
            </section>
        <?php endif; ?>

        <?php if ($summary['categories'] === []): ?>
            <?php View::partial('empty-state', ['icon' => 'gift', 'heading' => 'Todavía no hay regalos', 'text' => 'Pronto habrá regalos para enviar.']); ?>
        <?php endif; ?>
        <?php foreach ($summary['categories'] as $category): ?>
            <section class="card appeals-section">
                <h2><?= icon('gift') ?> <?= e($category['name']) ?></h2>
                <div class="gift-grid">
                    <?php foreach ($category['gifts'] as $g): ?>
                        <article class="gift-card">
                            <img class="gift-card__media" src="<?= e($g['media_url']) ?>" alt="" loading="lazy">
                            <p class="gift-card__name"><?= e($g['name']) ?></p>
                            <p class="gift-card__price"><?= e($g['price']['formatted']) ?></p>
                            <?php if ($sending): ?>
                                <form method="post" action="<?= e($action) ?>"
                                    data-confirm="<?= e(t('¿Enviar {gift} a {name} por {price}? Se descuenta de tu monedero.', [
                                        'gift' => $g['name'], 'name' => $target['user']['display_name'], 'price' => $g['price']['formatted'],
                                    ])) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="action" value="send">
                                    <input type="hidden" name="gift_id" value="<?= (int) $g['id'] ?>">
                                    <input type="hidden" name="source" value="buy">
                                    <input type="hidden" name="to" value="<?= e($target['user']['username']) ?>">
                                    <input type="hidden" name="context" value="<?= e($target['context']) ?>">
                                    <input type="hidden" name="ref" value="<?= (int) $target['ref'] ?>">
                                    <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('send') ?> <?= e(t('Enviar')) ?></button>
                                </form>
                            <?php else: ?>
                                <form class="gift-card__buy" method="post" action="<?= e($action) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="action" value="buy">
                                    <input type="hidden" name="gift_id" value="<?= (int) $g['id'] ?>">
                                    <label class="sr-only" for="qty-<?= (int) $g['id'] ?>"><?= e(t('Cantidad')) ?></label>
                                    <select class="select" id="qty-<?= (int) $g['id'] ?>" name="quantity">
                                        <?php foreach (array_unique([1, 3, 5, 10, $summary['max_quantity']]) as $n): ?>
                                            <?php if ($n <= $summary['max_quantity']): ?><option value="<?= (int) $n ?>">× <?= (int) $n ?></option><?php endif; ?>
                                        <?php endforeach; ?>
                                    </select>
                                    <button type="submit" class="btn btn--secondary btn--sm"><?= icon('plus') ?> <?= e(t('Comprar')) ?></button>
                                </form>
                                <?php if (isset($inventoryById[$g['id']])): ?>
                                    <p class="appeals-item__meta"><?= e(plural($inventoryById[$g['id']]['quantity'], 'guardado', 'guardados')) ?></p>
                                <?php endif; ?>
                            <?php endif; ?>
                        </article>
                    <?php endforeach; ?>
                </div>
            </section>
        <?php endforeach; ?>
        <?php if (!$sending): ?>
            <p class="appeals-item__meta">
                <?= e(t('Compra regalos para guardarlos en Mis regalos o envíalos al momento desde un perfil, el chat, una publicación, un reel o una historia.')) ?>
                <a href="<?= e(url('legal.php', ['doc' => 'reembolsos'])) ?>" target="_blank" rel="noopener"><?= e(t('Política de reembolsos')) ?></a>
            </p>
        <?php endif; ?>

    <?php elseif ($tab === 'mine'): ?>
        <?php if ($summary['inventory'] === []): ?>
            <?php View::partial('empty-state', ['icon' => 'inbox', 'heading' => 'No tienes regalos guardados', 'text' => 'Compra regalos en la tienda y envíalos cuando quieras desde un perfil, el chat, una publicación o una historia.']); ?>
        <?php else: ?>
            <section class="card appeals-section">
                <p class="appeals-item__meta"><?= e(t('Para enviar uno, abre el perfil, el chat, la publicación o la historia de la persona y toca el regalo.')) ?></p>
                <div class="gift-grid">
                    <?php foreach ($summary['inventory'] as $g): ?>
                        <article class="gift-card">
                            <img class="gift-card__media" src="<?= e($g['media_url']) ?>" alt="" loading="lazy">
                            <p class="gift-card__name"><?= e($g['name']) ?></p>
                            <p class="gift-card__price">× <?= (int) $g['quantity'] ?></p>
                        </article>
                    <?php endforeach; ?>
                </div>
            </section>
        <?php endif; ?>

    <?php else: ?>
        <?php if ($history === []): ?>
            <?php View::partial('empty-state', $tab === 'received'
                ? ['icon' => 'gift', 'heading' => 'Todavía no recibiste regalos', 'text' => 'Cuando alguien te envíe uno, lo verás aquí y su valor llegará a tu monedero. Solo tú ves tus regalos recibidos.']
                : ['icon' => 'send', 'heading' => 'Todavía no enviaste regalos', 'text' => 'Envía uno desde el perfil, el chat, una publicación o una historia.']); ?>
        <?php else: ?>
            <section class="card appeals-section">
                <?php if ($tab === 'received'): ?><p class="appeals-item__meta"><?= e(t('Solo tú ves tus regalos recibidos. Lo ganado se puede retirar desde tu monedero.')) ?></p><?php endif; ?>
                <ul class="appeals-list">
                    <?php foreach ($history as $s): ?>
                        <li class="appeals-item wallet-person gift-row">
                            <img class="gift-row__media" src="<?= e($s['gift']['media_url']) ?>" alt="" loading="lazy">
                            <div>
                                <p class="appeals-item__text">
                                    <strong><?= e($s['gift']['name']) ?></strong>
                                    <?php if ($s['user'] !== null): ?>
                                        · <?= e($tab === 'received' ? t('de') : t('para')) ?>
                                        <a href="<?= e(url('profile.php', ['u' => $s['user']['username']])) ?>"><?= e($s['user']['display_name']) ?></a>
                                    <?php else: ?>
                                        · <?= e(t('Cuenta no disponible')) ?>
                                    <?php endif; ?>
                                </p>
                                <p class="appeals-item__meta"><?= time_tag((string) $s['created_at']) ?></p>
                            </div>
                            <span class="wallet-tx__amount<?= $tab === 'received' ? ' is-positive' : '' ?>"><?= e(($tab === 'received' ? '+' : '−') . $s['amount']['formatted']) ?></span>
                        </li>
                    <?php endforeach; ?>
                </ul>
                <?php if ($nextUrl !== null): ?>
                    <a class="btn btn--secondary btn--sm" href="<?= e($nextUrl) ?>"><?= e(t('Ver más')) ?></a>
                <?php endif; ?>
            </section>
        <?php endif; ?>
    <?php endif; ?>
<?php endif; ?>
</div>
