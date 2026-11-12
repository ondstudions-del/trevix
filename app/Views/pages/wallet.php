<?php

use Trevix\Core\View;

/**
 * Monedero, plan de colaborador y suscripciones compradas.
 *
 * @var string      $tab
 * @var array       $tabs
 * @var array       $errors
 * @var array       $old
 * @var array|null  $summary       WalletService::summary() (pestaña Monedero)
 * @var array       $transactions  WalletService::presentTransaction()
 * @var array       $topups        WalletService::presentTopup()
 * @var array       $withdrawals   WalletService::presentWithdrawal()
 * @var array       $status        CollaboratorService::status() (pestaña Colaborador)
 * @var array       $subscribers   Collaborator::subscribers()
 * @var array       $subscriptions Collaborator::subscriptionsOf()
 * @var string|null $nextUrl
 */
$action = url('wallet.php', ['tab' => $tab === 'wallet' ? null : $tab]);
$statusChip = ['pending' => 'chip--warning', 'approved' => 'chip--success', 'paid' => 'chip--success', 'rejected' => 'chip--danger', 'cancelled' => 'chip--muted'];
$nextUrl = $nextUrl ?? null;
$cents = static fn (array $amount): string => number_format($amount['cents'] / 100, 2, '.', '');
?>
<header class="page-header">
    <div class="page-header__row">
        <a class="icon-btn" href="<?= e(url('settings.php')) ?>" aria-label="<?= e(t('Volver')) ?>"><?= icon('arrow-left') ?></a>
        <h1 class="page-header__title page-header__title--visible"><?= e(t($tabs[$tab]['label'])) ?></h1>
    </div>
    <nav class="tabs" aria-label="<?= e(t('Monedero y colaborador')) ?>">
        <?php foreach ($tabs as $key => $item): ?>
            <a class="<?= cx('tabs__item', ['is-active' => $tab === $key]) ?>" href="<?= e(url('wallet.php', ['tab' => $key === 'wallet' ? null : $key])) ?>"
                <?= $tab === $key ? 'aria-current="page"' : '' ?>><?= e(t($item['label'])) ?></a>
        <?php endforeach; ?>
    </nav>
</header>

<div class="appeals-page wallet-page">
<?php if (!isset($status) && $summary === null && !isset($subscriptions)): ?>
    <?php View::partial('empty-state', ['icon' => 'wallet', 'heading' => 'Inicia sesión para ver tu monedero', 'text' => 'Tu saldo y tus movimientos son privados.']); ?>

<?php elseif ($tab === 'wallet'): ?>
    <section class="card appeals-section wallet-balance" aria-labelledby="balance-heading">
        <p class="wallet-balance__label" id="balance-heading"><?= e(t('Saldo disponible')) ?></p>
        <p class="wallet-balance__amount"><?= e($summary['balance']['formatted']) ?></p>
        <p class="appeals-item__meta">
            <?= e(t('Puedes retirar {amount} (lo ganado como colaborador y con regalos). Lo que recargas se usa dentro de TREVIX.', ['amount' => $summary['withdrawable']['formatted']])) ?>
            <?php if ($summary['pending_topups'] > 0): ?>
                · <span class="chip chip--warning"><?= e(plural($summary['pending_topups'], 'recarga en revisión', 'recargas en revisión')) ?></span>
            <?php endif; ?>
        </p>
        <p>
            <a class="btn btn--secondary btn--sm" href="<?= e(url('gifts.php')) ?>"><?= icon('gift') ?> <?= e(t('Regalos')) ?></a>
            <a class="btn btn--secondary btn--sm" href="<?= e(url('ads.php')) ?>"><?= icon('megaphone') ?> OND-ADS</a>
        </p>
    </section>

    <section class="card appeals-section" id="recargar" aria-labelledby="topup-heading">
        <h2 id="topup-heading"><?= icon('plus') ?> <?= e(t('Recargar')) ?></h2>
        <p class="appeals-item__meta">
            <?= e(t('El saldo recargado que no uses se puede devolver si lo pides dentro de los 30 días.')) ?>
            <a href="<?= e(url('legal.php', ['doc' => 'reembolsos'])) ?>" target="_blank" rel="noopener"><?= e(t('Política de reembolsos')) ?></a>
        </p>
        <?php if ($summary['methods'] === []): ?>
            <p class="appeals-item__meta"><?= e(t('Todavía no hay medios de pago disponibles. Vuelve a intentarlo más tarde.')) ?></p>
        <?php else: ?>
            <ol class="wallet-steps">
                <li><?= e(t('Elige un medio de pago y envía el dinero con los datos que aparecen.')) ?></li>
                <li><?= e(t('Escribe el monto, la referencia del pago y sube una captura del comprobante.')) ?></li>
                <li><?= e(t('El equipo lo revisa y el saldo aparece en tu monedero. Te avisaremos.')) ?></li>
            </ol>
            <div class="wallet-methods">
                <?php foreach ($summary['methods'] as $m): ?>
                    <details class="wallet-method">
                        <summary><strong><?= e($m['name']) ?></strong> <span class="appeals-item__meta"><?= e(t('mínimo {amount}', ['amount' => $m['min_amount']['formatted']])) ?></span></summary>
                        <p class="appeals-item__text"><?= e($m['instructions']) ?></p>
                    </details>
                <?php endforeach; ?>
            </div>
            <form class="form" method="post" action="<?= e(url('wallet.php')) ?>" enctype="multipart/form-data" novalidate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="topup">
                <div class="field">
                    <label class="field__label" for="tp-method"><?= e(t('Medio de pago')) ?></label>
                    <div class="select-wrap">
                        <select class="select" id="tp-method" name="method_id" required<?= invalid_attrs($errors, 'method_id', 'tp-method') ?>>
                            <option value=""><?= e(t('Elige uno')) ?></option>
                            <?php foreach ($summary['methods'] as $m): ?>
                                <option value="<?= (int) $m['id'] ?>" <?= (int) ($old['method_id'] ?? 0) === $m['id'] ? 'selected' : '' ?>><?= e($m['name']) ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <?= field_error($errors, 'method_id', 'tp-method') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="tp-amount"><?= e(t('Monto que pagaste (USD)')) ?></label>
                    <input class="input" id="tp-amount" name="amount" inputmode="decimal" required maxlength="12" placeholder="10.00"
                        value="<?= e((string) ($old['amount'] ?? '')) ?>"<?= invalid_attrs($errors, 'amount', 'tp-amount') ?>>
                    <?= field_error($errors, 'amount', 'tp-amount') ?>
                    <p class="field__hint"><?= e(t('Máximo {amount} por recarga.', ['amount' => $summary['max_topup']['formatted']])) ?></p>
                </div>
                <div class="field">
                    <label class="field__label" for="tp-reference"><?= e(t('Referencia o número de transacción')) ?></label>
                    <input class="input" id="tp-reference" name="reference" required maxlength="120"
                        value="<?= e((string) ($old['reference'] ?? '')) ?>"<?= invalid_attrs($errors, 'reference', 'tp-reference') ?>>
                    <?= field_error($errors, 'reference', 'tp-reference') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="tp-proof"><?= e(t('Comprobante (captura o foto)')) ?></label>
                    <input class="input" id="tp-proof" name="proof" type="file" accept="image/jpeg,image/png,image/webp" required<?= invalid_attrs($errors, 'proof', 'tp-proof') ?>>
                    <?= field_error($errors, 'proof', 'tp-proof') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="tp-note"><?= e(t('Nota para el equipo')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                    <input class="input" id="tp-note" name="note" maxlength="500" value="<?= e((string) ($old['note'] ?? '')) ?>">
                </div>
                <button type="submit" class="btn btn--primary"><?= icon('send') ?> <?= e(t('Enviar recarga')) ?></button>
            </form>
        <?php endif; ?>
    </section>

    <section class="card appeals-section" id="retirar" aria-labelledby="withdraw-heading">
        <h2 id="withdraw-heading"><?= icon('banknote') ?> <?= e(t('Retirar ganancias')) ?></h2>
        <?php $pendingW = $summary['pending_withdrawal']; ?>
        <?php if ($pendingW !== null): ?>
            <p class="appeals-item__text">
                <?= e(t('Tienes un retiro de {amount} en revisión hacia {method} ({account}).', ['amount' => $pendingW['amount']['formatted'], 'method' => $pendingW['method'], 'account' => $pendingW['account']])) ?>
            </p>
            <form method="post" action="<?= e(url('wallet.php')) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="cancel_withdrawal">
                <input type="hidden" name="id" value="<?= (int) $pendingW['id'] ?>">
                <button type="submit" class="btn btn--secondary btn--sm"><?= icon('x') ?> <?= e(t('Cancelar retiro')) ?></button>
            </form>
        <?php elseif ($summary['withdrawable']['cents'] < $summary['min_withdrawal']['cents']): ?>
            <p class="appeals-item__meta">
                <?= e(t('Puedes pedir un retiro cuando tus ganancias como colaborador lleguen a {amount}.', ['amount' => $summary['min_withdrawal']['formatted']])) ?>
            </p>
        <?php else: ?>
            <form class="form" method="post" action="<?= e(url('wallet.php')) ?>" novalidate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="withdraw">
                <div class="field">
                    <label class="field__label" for="w-amount"><?= e(t('Monto (USD)')) ?></label>
                    <input class="input" id="w-amount" name="amount" inputmode="decimal" required maxlength="12"
                        value="<?= e((string) ($old['w_amount'] ?? $cents($summary['withdrawable']))) ?>"<?= invalid_attrs($errors, 'w_amount', 'w-amount') ?>>
                    <?= field_error($errors, 'w_amount', 'w-amount') ?>
                    <p class="field__hint"><?= e(t('Entre {min} y {max}.', ['min' => $summary['min_withdrawal']['formatted'], 'max' => $summary['withdrawable']['formatted']])) ?></p>
                </div>
                <div class="field">
                    <label class="field__label" for="w-method"><?= e(t('¿Por dónde lo recibes?')) ?></label>
                    <input class="input" id="w-method" name="method" required maxlength="60" placeholder="<?= e(t('PayPal, Llave Bre-B…')) ?>"
                        value="<?= e((string) ($old['w_method'] ?? '')) ?>"<?= invalid_attrs($errors, 'w_method', 'w-method') ?>>
                    <?= field_error($errors, 'w_method', 'w-method') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="w-account"><?= e(t('Cuenta, correo o llave')) ?></label>
                    <input class="input" id="w-account" name="account" required maxlength="255"
                        value="<?= e((string) ($old['w_account'] ?? '')) ?>"<?= invalid_attrs($errors, 'w_account', 'w-account') ?>>
                    <?= field_error($errors, 'w_account', 'w-account') ?>
                </div>
                <button type="submit" class="btn btn--primary"><?= icon('banknote') ?> <?= e(t('Pedir retiro')) ?></button>
            </form>
        <?php endif; ?>
    </section>

    <?php if ($topups !== [] || $withdrawals !== []): ?>
        <section class="card appeals-section" aria-labelledby="requests-heading">
            <h2 id="requests-heading"><?= icon('clock') ?> <?= e(t('Recargas y retiros')) ?></h2>
            <ul class="appeals-list">
                <?php foreach ($topups as $tp): ?>
                    <li class="appeals-item">
                        <p class="appeals-item__meta">
                            <span class="chip chip--brand"><?= e(t('Recarga')) ?></span>
                            <span class="chip <?= e($statusChip[$tp['status']] ?? 'chip--muted') ?>"><?= e($tp['status_label']) ?></span>
                            <?= time_tag((string) $tp['created_at']) ?>
                        </p>
                        <p class="appeals-item__text">
                            <strong><?= e(($tp['credited'] ?? $tp['amount'])['formatted']) ?></strong> · <?= e($tp['method']) ?> · <?= e(t('ref. {ref}', ['ref' => $tp['reference']])) ?>
                        </p>
                        <?php if (!empty($tp['decision_note']) && $tp['status'] === 'rejected'): ?>
                            <p class="appeals-item__meta"><?= e(t('Motivo')) ?>: «<?= e($tp['decision_note']) ?>»</p>
                        <?php endif; ?>
                        <?php if ($tp['status'] === 'pending'): ?>
                            <form method="post" action="<?= e(url('wallet.php')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="cancel_topup">
                                <input type="hidden" name="id" value="<?= (int) $tp['id'] ?>">
                                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('x') ?> <?= e(t('Cancelar')) ?></button>
                            </form>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
                <?php foreach ($withdrawals as $w): ?>
                    <li class="appeals-item">
                        <p class="appeals-item__meta">
                            <span class="chip chip--brand"><?= e(t('Retiro')) ?></span>
                            <span class="chip <?= e($statusChip[$w['status']] ?? 'chip--muted') ?>"><?= e($w['status_label']) ?></span>
                            <?= time_tag((string) $w['created_at']) ?>
                        </p>
                        <p class="appeals-item__text"><strong><?= e($w['amount']['formatted']) ?></strong> · <?= e($w['method']) ?> · <?= e($w['account']) ?></p>
                        <?php if (!empty($w['decision_note']) && $w['status'] === 'rejected'): ?>
                            <p class="appeals-item__meta"><?= e(t('Motivo')) ?>: «<?= e($w['decision_note']) ?>»</p>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
        </section>
    <?php endif; ?>

    <section class="card appeals-section" aria-labelledby="history-heading">
        <h2 id="history-heading"><?= icon('history') ?> <?= e(t('Movimientos')) ?></h2>
        <?php if ($transactions === []): ?>
            <p class="appeals-item__meta"><?= e(t('Todavía no tienes movimientos.')) ?></p>
        <?php else: ?>
            <ul class="appeals-list">
                <?php foreach ($transactions as $tx): ?>
                    <li class="appeals-item wallet-tx">
                        <div>
                            <p class="appeals-item__text"><?= e($tx['label']) ?></p>
                            <p class="appeals-item__meta"><?= time_tag((string) $tx['created_at']) ?> · <?= e(t('saldo {amount}', ['amount' => $tx['balance_after']['formatted']])) ?></p>
                        </div>
                        <strong class="<?= cx('wallet-tx__amount', ['is-positive' => $tx['amount']['cents'] > 0]) ?>">
                            <?= $tx['amount']['cents'] > 0 ? '+' : '' ?><?= e($tx['amount']['formatted']) ?>
                        </strong>
                    </li>
                <?php endforeach; ?>
            </ul>
            <?php if ($nextUrl !== null): ?>
                <a class="btn btn--ghost btn--sm" href="<?= e($nextUrl) ?>"><?= e(t('Ver más')) ?></a>
            <?php endif; ?>
        <?php endif; ?>
    </section>

<?php elseif ($tab === 'collaborator'): ?>
    <?php $plan = $status['plan']; ?>
    <p class="appeals-page__intro">
        <?= e(t('Como colaborador, otras personas pagan una suscripción para ver tus publicaciones «Suscriptores». Tú eliges el precio en dólares y los días de acceso; TREVIX se queda con el {pct} % de cada compra y el resto llega a tu monedero.', ['pct' => $status['rules']['commission']])) ?>
    </p>

    <?php if ($plan !== null): ?>
        <section class="card appeals-section wallet-balance">
            <p class="wallet-balance__label">
                <?= e(t('Tu plan')) ?>
                <span class="chip <?= $status['active'] ? 'chip--success' : 'chip--muted' ?>"><?= e($status['active'] ? t('Activo') : t('En pausa')) ?></span>
            </p>
            <p class="wallet-balance__amount"><?= e(t('{price} por {days} días', ['price' => $plan['price']['formatted'], 'days' => $plan['days']])) ?></p>
            <p class="appeals-item__meta">
                <?= e(t('Recibes {amount} por cada compra.', ['amount' => $plan['you_receive']['formatted']])) ?>
                · <?= e(plural($status['stats']['subscribers'], 'suscriptor activo', 'suscriptores activos')) ?>
                · <?= e(t('ganaste {amount}', ['amount' => $status['stats']['earned']['formatted']])) ?>
                · <?= e(plural($status['stats']['exclusive_posts'], 'publicación exclusiva', 'publicaciones exclusivas')) ?>
            </p>
            <form method="post" action="<?= e($action) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="<?= $status['active'] ? 'pause' : 'resume' ?>">
                <button type="submit" class="btn btn--secondary btn--sm"><?= icon($status['active'] ? 'pause' : 'play') ?> <?= e($status['active'] ? t('Pausar suscripciones') : t('Reanudar suscripciones')) ?></button>
            </form>
        </section>
    <?php endif; ?>

    <section class="card appeals-section" aria-labelledby="req-heading">
        <h2 id="req-heading"><?= icon('circle-check') ?> <?= e(t('Requisitos')) ?></h2>
        <ul class="appeals-list">
            <?php foreach ($status['checks'] as $check): ?>
                <li class="appeals-item wallet-check">
                    <?= icon($check['ok'] ? 'circle-check' : 'circle-x', $check['ok'] ? 'wallet-check__ok' : 'wallet-check__no') ?>
                    <div>
                        <p class="appeals-item__text"><?= e($check['label']) ?></p>
                        <p class="appeals-item__meta"><?= e($check['detail']) ?></p>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
        <?php if ($plan !== null): ?>
            <p class="appeals-item__meta"><?= e(t('Ya activaste tu plan: los requisitos solo se piden la primera vez.')) ?></p>
        <?php elseif ($status['granted']): ?>
            <p class="appeals-item__text"><?= icon('badge-check') ?> <?= e(t('El equipo de TREVIX habilitó tu cuenta como colaboradora: puedes activar tu plan aunque no cumplas estos requisitos.')) ?></p>
        <?php endif; ?>
    </section>

    <?php if ($status['can_activate']): ?>
        <section class="card appeals-section" aria-labelledby="plan-heading">
            <h2 id="plan-heading"><?= icon('crown') ?> <?= e($plan === null ? t('Activar mi plan') : t('Editar mi plan')) ?></h2>
            <form class="form" method="post" action="<?= e($action) ?>" novalidate>
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="save_plan">
                <div class="field">
                    <label class="field__label" for="pl-price"><?= e(t('Precio (USD)')) ?></label>
                    <input class="input" id="pl-price" name="price" inputmode="decimal" required maxlength="12"
                        value="<?= e((string) ($old['price'] ?? ($plan !== null ? $cents($plan['price']) : ''))) ?>"<?= invalid_attrs($errors, 'price', 'pl-price') ?>>
                    <?= field_error($errors, 'price', 'pl-price') ?>
                    <p class="field__hint"><?= e(t('Entre {min} y {max}.', ['min' => $status['rules']['min_price']['formatted'], 'max' => $status['rules']['max_price']['formatted']])) ?></p>
                </div>
                <div class="field">
                    <label class="field__label" for="pl-days"><?= e(t('Días de acceso por compra')) ?></label>
                    <input class="input" id="pl-days" name="days" type="number" min="1" max="<?= (int) $status['rules']['max_days'] ?>" required
                        value="<?= e((string) ($old['days'] ?? ($plan['days'] ?? 30))) ?>"<?= invalid_attrs($errors, 'days', 'pl-days') ?>>
                    <?= field_error($errors, 'days', 'pl-days') ?>
                </div>
                <div class="field">
                    <label class="field__label" for="pl-desc"><?= e(t('¿Qué ofreces?')) ?> <span class="field__hint"><?= e(t('(opcional)')) ?></span></label>
                    <input class="input" id="pl-desc" name="description" maxlength="300"
                        value="<?= e((string) ($old['description'] ?? ($plan['description'] ?? ''))) ?>" placeholder="<?= e(t('Contenido detrás de cámaras, adelantos…')) ?>">
                </div>
                <button type="submit" class="btn btn--primary"><?= icon('check') ?> <?= e($plan === null ? t('Activar plan') : t('Guardar cambios')) ?></button>
            </form>
        </section>
    <?php endif; ?>

    <?php if ($plan !== null): ?>
        <section class="card appeals-section" aria-labelledby="subs-heading">
            <h2 id="subs-heading"><?= icon('users') ?> <?= e(t('Suscriptores')) ?></h2>
            <?php if ($subscribers === []): ?>
                <p class="appeals-item__meta"><?= e(t('Todavía nadie se suscribió. Publica con la visibilidad «Suscriptores» para ofrecer contenido exclusivo.')) ?></p>
            <?php else: ?>
                <ul class="appeals-list">
                    <?php foreach ($subscribers as $s): ?>
                        <li class="appeals-item wallet-person">
                            <a href="<?= e(profile_url($s)) ?>"><?= avatar($s, 'sm') ?></a>
                            <div>
                                <p class="appeals-item__text"><a href="<?= e(profile_url($s)) ?>"><strong><?= e($s['display_name']) ?></strong></a> @<?= e($s['username']) ?></p>
                                <p class="appeals-item__meta">
                                    <?= strtotime((string) $s['expires_at']) > time()
                                        ? e(t('Acceso hasta el {date}', ['date' => full_date((string) $s['expires_at'], false)]))
                                        : e(t('Venció el {date}', ['date' => full_date((string) $s['expires_at'], false)])) ?>
                                    · <?= e(plural((int) $s['purchases'], 'compra', 'compras')) ?>
                                </p>
                            </div>
                        </li>
                    <?php endforeach; ?>
                </ul>
                <?php if ($nextUrl !== null): ?><a class="btn btn--ghost btn--sm" href="<?= e($nextUrl) ?>"><?= e(t('Ver más')) ?></a><?php endif; ?>
            <?php endif; ?>
        </section>
    <?php endif; ?>

<?php else: ?>
    <section class="card appeals-section" aria-labelledby="mysubs-heading">
        <h2 id="mysubs-heading"><?= icon('star') ?> <?= e(t('Mis suscripciones')) ?></h2>
        <p class="appeals-item__meta">
            <?= e(t('Las suscripciones no son reembolsables, salvo un cobro duplicado, un error técnico o si retiramos la cuenta del colaborador.')) ?>
            <a href="<?= e(url('legal.php', ['doc' => 'reembolsos'])) ?>" target="_blank" rel="noopener"><?= e(t('Política de reembolsos')) ?></a>
        </p>
        <?php if ($subscriptions === []): ?>
            <p class="appeals-item__meta"><?= e(t('Todavía no te suscribiste a ningún colaborador. Busca el botón «Suscribirme» en su perfil.')) ?></p>
        <?php else: ?>
            <ul class="appeals-list">
                <?php foreach ($subscriptions as $s): ?>
                    <?php $active = strtotime((string) $s['expires_at']) > time(); ?>
                    <li class="appeals-item wallet-person">
                        <a href="<?= e(profile_url($s)) ?>"><?= avatar($s, 'sm') ?></a>
                        <div>
                            <p class="appeals-item__text"><a href="<?= e(profile_url($s)) ?>"><strong><?= e($s['display_name']) ?></strong></a> @<?= e($s['username']) ?></p>
                            <p class="appeals-item__meta">
                                <span class="chip <?= $active ? 'chip--success' : 'chip--muted' ?>"><?= e($active ? t('Activa') : t('Vencida')) ?></span>
                                <?= e($active
                                    ? t('Acceso hasta el {date}', ['date' => full_date((string) $s['expires_at'], false)])
                                    : t('Venció el {date}', ['date' => full_date((string) $s['expires_at'], false)])) ?>
                            </p>
                        </div>
                        <?php if (!empty($s['plan_active']) && $s['price_cents'] !== null): ?>
                            <form method="post" action="<?= e($action) ?>" data-confirm-label="<?= e(t('Pagar')) ?>" data-confirm="<?= e(t('¿Pagar {price} de tu monedero por {days} días más?', [
                                'price' => \Trevix\Services\WalletService::money((int) $s['price_cents']), 'days' => (int) $s['period_days'],
                            ])) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="action" value="subscribe">
                                <input type="hidden" name="collaborator_id" value="<?= (int) $s['id'] ?>">
                                <button type="submit" class="btn btn--secondary btn--sm"><?= e($active ? t('Extender') : t('Renovar')) ?></button>
                            </form>
                        <?php endif; ?>
                    </li>
                <?php endforeach; ?>
            </ul>
            <?php if ($nextUrl !== null): ?><a class="btn btn--ghost btn--sm" href="<?= e($nextUrl) ?>"><?= e(t('Ver más')) ?></a><?php endif; ?>
        <?php endif; ?>
    </section>
<?php endif; ?>
</div>
