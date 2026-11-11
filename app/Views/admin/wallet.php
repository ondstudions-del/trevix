<?php

use Trevix\Controllers\Admin\WalletController;
use Trevix\Core\View;
use Trevix\Services\WalletService;

/**
 * Monedero: recargas con comprobante, retiros, medios de pago y colaboradores (requisitos y comisión).
 *
 * @var string      $tab
 * @var array       $totals   Wallet::totals()
 * @var array       $pending  ['topups' => n, 'withdrawals' => n]
 * @var string|null $status   (recargas y retiros)
 * @var array       $statuses (recargas y retiros)
 * @var array       $counts   (recargas y retiros)
 * @var array       $items    (recargas y retiros) Wallet::adminList()
 * @var array       $methods  (medios de pago)
 * @var array       $collaborators, $settings, $rules (colaboradores)
 * @var array|null  $staff
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
$action = url('admin/wallet.php', ['tab' => $tab === 'topups' ? null : $tab]);
$money = static fn (int $cents): string => WalletService::money($cents);
$disabled = $staff === null ? ' disabled' : '';
$cards = [
    ['wallet', t('Saldo en monederos'), 'balances', t('Dinero de las personas dentro de TREVIX')],
    ['crown', t('Ventas de suscripciones'), 'sales', null],
    ['banknote', t('Comisiones de TREVIX'), 'commissions', null],
    ['clock', t('Retiros por pagar'), 'pending_withdrawals', null],
];
?>
<section class="stat-grid" aria-label="<?= e(t('Resumen del monedero')) ?>">
    <?php foreach ($cards as [$iconName, $label, $key, $hint]): ?>
        <article class="stat-card">
            <span class="stat-card__icon"><?= icon($iconName) ?></span>
            <p class="stat-card__label"><?= e($label) ?></p>
            <p class="stat-card__value"><?= isset($totals[$key]) ? e($money($totals[$key])) : '—' ?></p>
            <p class="stat-card__hint">
                <?php if (!isset($totals[$key])): ?>
                    <?= e(t('Se calcula al conectar la base de datos')) ?>
                <?php elseif ($key === 'balances'): ?>
                    <?= e(t('Recargado: {in} · pagado en retiros: {out}', ['in' => $money($totals['topped_up']), 'out' => $money($totals['paid_out'])])) ?>
                <?php else: ?>
                    <?= e($hint ?? t('Datos en tiempo real')) ?>
                <?php endif; ?>
            </p>
        </article>
    <?php endforeach; ?>
</section>

<nav class="admin-tabs" aria-label="<?= e(t('Secciones del monedero')) ?>">
    <?php foreach (WalletController::TABS as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('admin/wallet.php', ['tab' => $key === 'topups' ? null : $key])) ?>"
            <?= $tab === $key ? 'aria-current="page"' : '' ?>>
            <?= e(t($label)) ?>
            <?php if (($pending[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $pending[$key] ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<?php if ($tab === 'topups' || $tab === 'withdrawals'): ?>
    <?php $isTopups = $tab === 'topups'; ?>
    <nav class="admin-tabs admin-tabs--sub" aria-label="<?= e(t('Estado')) ?>">
        <?php foreach ($statuses as $key => $label): ?>
            <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>"
                href="<?= e(url('admin/wallet.php', ['tab' => $isTopups ? null : $tab, 'status' => $key === 'pending' ? null : $key])) ?>"
                <?= $status === $key ? 'aria-current="page"' : '' ?>>
                <?= e($key === 'pending' ? t('Por revisar') : t($label)) ?>
                <?php if (($counts[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $counts[$key] ?></span><?php endif; ?>
            </a>
        <?php endforeach; ?>
    </nav>

    <p class="content-row__muted">
        <?= e($isTopups
            ? t('Revisa el comprobante en la cuenta del medio de pago antes de aprobar. Puedes acreditar un monto distinto si lo recibido no coincide.')
            : t('Envía el dinero por fuera (PayPal, Llave Bre-B…) y después márcalo como pagado. Si lo rechazas, el dinero vuelve a su monedero.')) ?>
    </p>

    <section class="panel">
        <?php if ($items === []): ?>
            <div class="panel__empty">
                <?= icon($isTopups ? 'wallet' : 'banknote') ?>
                <p><?= e($status === 'pending' ? ($isTopups ? t('No hay recargas por revisar.') : t('No hay retiros por pagar.')) : t('No hay nada en este estado.')) ?></p>
            </div>
        <?php else: ?>
            <ul class="content-list">
                <?php foreach ($items as $r): ?>
                    <?php $rid = (int) $r['id']; ?>
                    <li class="content-row" id="<?= $isTopups ? 'recarga' : 'retiro' ?>-<?= $rid ?>">
                        <div class="content-row__body">
                            <p class="content-row__author">
                                <?= avatar($r, 'xs') ?>
                                <a href="<?= e(url('admin/users.php', ['id' => $r['user_id']])) ?>"><strong><?= e($r['display_name']) ?></strong> (@<?= e($r['username']) ?>)</a>
                                <span class="chip chip--brand"><?= e($money((int) $r['amount_cents'])) ?></span>
                                <?php if ($r['user_status'] !== 'active'): ?><span class="chip chip--danger"><?= e(t('Cuenta no activa')) ?></span><?php endif; ?>
                            </p>
                            <?php if ($isTopups): ?>
                                <p class="content-row__text">
                                    <?= e(t('Medio:')) ?> <strong><?= e($r['method_name']) ?></strong>
                                    · <?= e(t('Referencia:')) ?> <strong><?= e($r['reference']) ?></strong>
                                </p>
                                <?php if (!empty($r['note'])): ?><p class="content-row__text">«<?= e($r['note']) ?>»</p><?php endif; ?>
                                <?php if ($r['credited_cents'] !== null && (int) $r['credited_cents'] !== (int) $r['amount_cents']): ?>
                                    <p class="content-row__text"><?= e(t('Acreditado: {amount}', ['amount' => $money((int) $r['credited_cents'])])) ?></p>
                                <?php endif; ?>
                                <?php $proofUrl = url('admin/wallet.php', ['proof' => $rid]); ?>
                                <a class="wallet-proof" href="<?= e($proofUrl) ?>" target="_blank" rel="noopener">
                                    <img src="<?= e($proofUrl) ?>" alt="<?= e(t('Comprobante de pago')) ?>" loading="lazy" width="160">
                                    <span><?= icon('external-link') ?> <?= e(t('Ver comprobante')) ?></span>
                                </a>
                            <?php else: ?>
                                <p class="content-row__text">
                                    <?= e(t('Enviar a:')) ?> <strong><?= e($r['method']) ?></strong> · <strong><?= e($r['account']) ?></strong>
                                </p>
                                <?php if (!empty($r['payout_reference'])): ?>
                                    <p class="content-row__text"><?= e(t('Referencia del pago:')) ?> <?= e($r['payout_reference']) ?></p>
                                <?php endif; ?>
                            <?php endif; ?>
                            <p class="content-row__muted">
                                <?= e(t('Saldo actual: {amount}', ['amount' => $money((int) $r['balance_cents'])])) ?>
                                · <?= e(t('enviada')) ?> <?= time_tag((string) $r['created_at']) ?>
                            </p>
                            <?php if ($r['reviewed_at'] !== null): ?>
                                <p class="content-row__muted">
                                    <?= e(t('Revisada')) ?> <?= time_tag((string) $r['reviewed_at']) ?><?= $r['reviewer_username'] !== null ? ' ' . e(t('por @{username}', ['username' => $r['reviewer_username']])) : '' ?>
                                    <?php if (!empty($r['decision_note'])): ?> · «<?= e($r['decision_note']) ?>»<?php endif; ?>
                                </p>
                            <?php endif; ?>
                        </div>
                        <?php if ($r['status'] === 'pending'): ?>
                            <div class="content-row__actions">
                                <details class="admin-menu">
                                    <summary class="btn btn--primary btn--sm"><?= icon('circle-check') ?> <?= e($isTopups ? t('Aprobar') : t('Marcar pagado')) ?></summary>
                                    <div class="admin-menu__panel">
                                        <form method="post" action="<?= e($action) ?>">
                                            <?= csrf_field() ?>
                                            <input type="hidden" name="id" value="<?= $rid ?>">
                                            <?php if ($isTopups): ?>
                                                <input type="hidden" name="action" value="approve_topup">
                                                <label class="field__label" for="credit-<?= $rid ?>"><?= e(t('Monto a acreditar (USD)')) ?></label>
                                                <input class="input" id="credit-<?= $rid ?>" name="credited" inputmode="decimal" maxlength="12"
                                                    value="<?= e(number_format((int) $r['amount_cents'] / 100, 2, '.', '')) ?>">
                                            <?php else: ?>
                                                <input type="hidden" name="action" value="pay_withdrawal">
                                                <label class="field__label" for="ref-<?= $rid ?>"><?= e(t('Referencia del pago')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                                                <input class="input" id="ref-<?= $rid ?>" name="reference" maxlength="120">
                                            <?php endif; ?>
                                            <label class="field__label" for="note-<?= $rid ?>"><?= e(t('Nota interna')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                                            <input class="input" id="note-<?= $rid ?>" name="note" maxlength="255">
                                            <button type="submit" class="btn btn--primary btn--sm btn--block"<?= $disabled ?>>
                                                <?= icon('check') ?> <?= e($isTopups ? t('Acreditar en el monedero') : t('Ya lo pagué')) ?>
                                            </button>
                                        </form>
                                    </div>
                                </details>
                                <details class="admin-menu">
                                    <summary class="btn btn--ghost btn--sm"><?= icon('circle-x') ?> <?= e(t('Rechazar')) ?></summary>
                                    <div class="admin-menu__panel">
                                        <form method="post" action="<?= e($action) ?>">
                                            <?= csrf_field() ?>
                                            <input type="hidden" name="id" value="<?= $rid ?>">
                                            <input type="hidden" name="action" value="<?= $isTopups ? 'reject_topup' : 'reject_withdrawal' ?>">
                                            <label class="field__label" for="reject-<?= $rid ?>"><?= e(t('Motivo (lo verá la persona)')) ?></label>
                                            <input class="input" id="reject-<?= $rid ?>" name="reason" required minlength="5" maxlength="255">
                                            <button type="submit" class="btn btn--danger btn--sm btn--block"<?= $disabled ?>><?= icon('circle-x') ?> <?= e($isTopups ? t('Rechazar recarga') : t('Rechazar y devolver')) ?></button>
                                        </form>
                                    </div>
                                </details>
                            </div>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
    </section>

<?php elseif ($tab === 'methods'): ?>
    <p class="content-row__muted"><?= e(t('Las personas eligen uno de estos medios al recargar, pagan por fuera con los datos que escribas y envían el comprobante.')) ?></p>
    <section class="panel">
        <ul class="content-list">
            <?php foreach ([...$methods, null] as $m): ?>
                <?php $mid = $m !== null ? (int) $m['id'] : 0; ?>
                <li class="content-row">
                    <div class="content-row__body">
                        <?php if ($m !== null): ?>
                            <p class="content-row__author">
                                <strong><?= e($m['name']) ?></strong>
                                <span class="chip <?= (int) $m['is_active'] === 1 ? 'chip--success' : 'chip--muted' ?>"><?= e((int) $m['is_active'] === 1 ? t('Activo') : t('Oculto')) ?></span>
                                <span class="chip chip--muted"><?= e(t('Mínimo {amount}', ['amount' => $money((int) $m['min_amount_cents'])])) ?></span>
                            </p>
                            <p class="content-row__text wallet-preline"><?= e($m['instructions']) ?></p>
                        <?php else: ?>
                            <p class="content-row__author"><strong><?= icon('plus') ?> <?= e(t('Nuevo medio de pago')) ?></strong></p>
                            <p class="content-row__muted"><?= e(t('Por ejemplo PayPal (correo de la cuenta) o Llave Bre-B (la llave y el nombre del titular).')) ?></p>
                        <?php endif; ?>
                    </div>
                    <div class="content-row__actions">
                        <details class="admin-menu"<?= $m === null && $methods === [] ? ' open' : '' ?>>
                            <summary class="btn btn--<?= $m === null ? 'primary' : 'ghost' ?> btn--sm"><?= icon($m === null ? 'plus' : 'pencil') ?> <?= e($m === null ? t('Agregar') : t('Editar')) ?></summary>
                            <div class="admin-menu__panel">
                                <form method="post" action="<?= e($action) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="action" value="save_method">
                                    <input type="hidden" name="id" value="<?= $mid ?>">
                                    <label class="field__label" for="m-name-<?= $mid ?>"><?= e(t('Nombre')) ?></label>
                                    <input class="input" id="m-name-<?= $mid ?>" name="name" required minlength="2" maxlength="60" value="<?= e($m['name'] ?? '') ?>" placeholder="PayPal">
                                    <label class="field__label" for="m-ins-<?= $mid ?>"><?= e(t('Datos e instrucciones para pagar')) ?></label>
                                    <textarea class="input textarea" id="m-ins-<?= $mid ?>" name="instructions" required minlength="5" maxlength="1000" rows="4"
                                        placeholder="<?= e(t('Envía el pago a pagos@ejemplo.com y escribe tu usuario de TREVIX en la nota.')) ?>"><?= e($m['instructions'] ?? '') ?></textarea>
                                    <label class="field__label" for="m-min-<?= $mid ?>"><?= e(t('Recarga mínima (USD)')) ?></label>
                                    <input class="input" id="m-min-<?= $mid ?>" name="min_amount" inputmode="decimal" required maxlength="12"
                                        value="<?= e($m !== null ? number_format((int) $m['min_amount_cents'] / 100, 2, '.', '') : '1') ?>">
                                    <label class="field__label" for="m-pos-<?= $mid ?>"><?= e(t('Orden')) ?></label>
                                    <input class="input" id="m-pos-<?= $mid ?>" name="position" type="number" min="0" max="999" value="<?= (int) ($m['position'] ?? 0) ?>">
                                    <label class="checkbox">
                                        <input type="checkbox" name="active" value="1"<?= $m === null || (int) $m['is_active'] === 1 ? ' checked' : '' ?>>
                                        <span><?= e(t('Mostrarlo al recargar')) ?></span>
                                    </label>
                                    <button type="submit" class="btn btn--primary btn--sm btn--block"<?= $disabled ?>><?= icon('check') ?> <?= e(t('Guardar')) ?></button>
                                </form>
                                <?php if ($m !== null): ?>
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="action" value="delete_method">
                                        <input type="hidden" name="id" value="<?= $mid ?>">
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
        <input type="hidden" name="action" value="save_rules">
        <header class="panel__head">
            <h2><?= icon('crown') ?> <?= e(t('Requisitos y comisión')) ?></h2>
        </header>
        <fieldset class="admin-settings__body"<?= $disabled ?>>
            <legend class="sr-only"><?= e(t('Requisitos para ser colaborador')) ?></legend>
            <p class="admin-setting__text">
                <?= e(t('Los requisitos se piden solo para activar el plan la primera vez. Con la comisión actual ({pct} %), de una suscripción de US$ 10 el colaborador recibe {net}.', [
                    'pct' => $rules['commission'],
                    'net' => $money(1000 - intdiv(1000 * $rules['commission'] + 50, 100)),
                ])) ?>
            </p>
            <?php foreach (WalletController::RULES as $key => [$label, $min, $max, $hint]): ?>
                <div class="field admin-setting">
                    <div>
                        <label class="admin-setting__title" for="rule-<?= e($key) ?>"><?= e(t($label)) ?></label>
                        <?php if ($hint !== null): ?><p class="admin-setting__text"><?= e(t($hint)) ?></p><?php endif; ?>
                    </div>
                    <input class="input wallet-rule-input" id="rule-<?= e($key) ?>" name="<?= e($key) ?>" type="number" min="<?= $min ?>" max="<?= $max ?>" required
                        value="<?= e($settings[$key]) ?>">
                </div>
            <?php endforeach; ?>
            <?php foreach (WalletController::AMOUNTS as $key => $label): ?>
                <div class="field admin-setting">
                    <label class="admin-setting__title" for="rule-<?= e($key) ?>"><?= e(t($label)) ?></label>
                    <input class="input wallet-rule-input" id="rule-<?= e($key) ?>" name="<?= e($key) ?>" inputmode="decimal" maxlength="12" required
                        value="<?= e($settings[$key]) ?>">
                </div>
            <?php endforeach; ?>
        </fieldset>
        <footer class="admin-settings__footer">
            <button type="submit" class="btn btn--primary"<?= $disabled ?>><?= icon('check') ?> <?= e(t('Guardar cambios')) ?></button>
        </footer>
    </form>

    <section class="panel">
        <header class="panel__head">
            <h2><?= icon('users') ?> <?= e(t('Colaboradores')) ?></h2>
        </header>
        <?php if ($collaborators === []): ?>
            <div class="panel__empty">
                <?= icon('crown') ?>
                <p><?= e(t('Todavía nadie activó su plan de colaborador.')) ?></p>
            </div>
        <?php else: ?>
            <ul class="content-list">
                <?php foreach ($collaborators as $c): ?>
                    <li class="content-row">
                        <div class="content-row__body">
                            <p class="content-row__author">
                                <?= avatar($c, 'xs') ?>
                                <a href="<?= e(url('admin/users.php', ['id' => $c['user_id']])) ?>"><strong><?= e($c['display_name']) ?></strong> (@<?= e($c['username']) ?>)</a>
                                <span class="chip <?= (int) $c['is_active'] === 1 ? 'chip--success' : 'chip--muted' ?>"><?= e((int) $c['is_active'] === 1 ? t('Activo') : t('En pausa')) ?></span>
                                <span class="chip chip--brand"><?= e(t('{price} por {days} días', ['price' => $money((int) $c['price_cents']), 'days' => (int) $c['period_days']])) ?></span>
                            </p>
                            <p class="content-row__muted">
                                <?= e(t('{subs} suscriptores activos · {sales} ventas · ganó {earned} · comisión {commission}', [
                                    'subs'       => compact_number((int) $c['subscribers']),
                                    'sales'      => compact_number((int) $c['sales']),
                                    'earned'     => $money((int) $c['earned']),
                                    'commission' => $money((int) $c['commission']),
                                ])) ?>
                                · <?= e(t('{n} seguidores', ['n' => compact_number((int) $c['followers_count'])])) ?>
                                <?php if ($c['activated_at'] !== null): ?> · <?= e(t('desde')) ?> <?= time_tag((string) $c['activated_at']) ?><?php endif; ?>
                            </p>
                        </div>
                    </li>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
    </section>
<?php endif; ?>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
