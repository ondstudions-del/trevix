<?php

use Trevix\Core\View;
use Trevix\Models\User;

/**
 * Ficha de una cuenta en el panel.
 *
 * @var array $user
 * @var bool  $canAct    rango suficiente para actuar sobre ella
 * @var bool  $isAdmin
 * @var bool  $isSelf
 * @var int   $openReports
 * @var array $posts
 * @var array $history
 * @var array $durations
 * @var array $warnings    Warning::forUser($id, true)
 * @var int   $warningDays
 */
$statusChip = ['active' => 'chip--success', 'suspended' => 'chip--danger', 'deactivated' => 'chip--muted'];
$id = (int) $user['id'];
$action = url('admin/users.php');
$suspended = $user['status'] === 'suspended';
?>
<a class="admin-back" href="<?= e(url('admin/users.php')) ?>"><?= icon('arrow-left') ?> Volver a usuarios</a>

<div class="admin-detail">
    <div class="admin-detail__main">
        <section class="panel">
            <div class="user-card">
                <?= avatar($user, 'xl') ?>
                <div class="user-card__info">
                    <h2><?= e($user['display_name']) ?><?php if ($user['is_verified']): ?> <?= icon('badge-check', 'verified', 'Verificada') ?><?php endif; ?></h2>
                    <p class="user-card__handle">@<?= e($user['username']) ?> · <?= e($user['email']) ?></p>
                    <p class="user-card__chips">
                        <span class="chip chip--brand"><?= e(User::ROLE_LABELS[$user['role']] ?? $user['role']) ?></span>
                        <span class="chip <?= e($statusChip[$user['status']] ?? 'chip--muted') ?>"><?= e(User::STATUS_LABELS[$user['status']] ?? $user['status']) ?></span>
                        <?php if ($user['email_verified_at'] === null): ?><span class="chip chip--muted">Correo sin verificar</span><?php endif; ?>
                        <?php if ($user['is_private']): ?><span class="chip chip--muted"><?= icon('lock') ?> Privada</span><?php endif; ?>
                    </p>
                    <?php if ($user['bio']): ?><p class="user-card__bio"><?= e($user['bio']) ?></p><?php endif; ?>
                </div>
            </div>
            <?php if ($suspended): ?>
                <div class="alert alert--error user-card__alert">
                    <?= icon('ban') ?>
                    <p>
                        <strong>Suspendida <?= $user['suspended_until'] ? 'hasta el ' . e(full_date((string) $user['suspended_until'])) : 'sin fecha de fin' ?>.</strong>
                        <?php if ($user['suspended_until'] && strtotime((string) $user['suspended_until']) < time()): ?>
                            La suspensión ya venció: se reactivará cuando vuelva a iniciar sesión.
                        <?php endif; ?>
                        <?php if ($user['suspension_reason']): ?>Motivo: <?= e($user['suspension_reason']) ?><?php endif; ?>
                    </p>
                </div>
            <?php endif; ?>
            <dl class="user-stats">
                <div><dt>Publicaciones</dt><dd><?= compact_number((int) $user['posts_count']) ?></dd></div>
                <div><dt>Seguidores</dt><dd><?= compact_number((int) $user['followers_count']) ?></dd></div>
                <div><dt>Siguiendo</dt><dd><?= compact_number((int) $user['following_count']) ?></dd></div>
                <div><dt>Reportes pendientes</dt><dd><?= $openReports ?></dd></div>
                <div><dt>Alta</dt><dd><?= e(full_date((string) $user['created_at'], false)) ?></dd></div>
                <div><dt>Última actividad</dt><dd><?= $user['last_seen_at'] ? time_tag((string) $user['last_seen_at']) : '—' ?></dd></div>
            </dl>
            <?php if ($user['status'] === 'active'): ?>
                <p class="user-card__link"><a href="<?= e(profile_url($user)) ?>" target="_blank" rel="noopener">Ver perfil en TREVIX <?= icon('external-link') ?></a></p>
            <?php endif; ?>
        </section>

        <section class="panel">
            <header class="panel__head">
                <h2><?= icon('file-text') ?> Publicaciones recientes</h2>
                <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/content.php', ['q' => '@' . $user['username']])) ?>">Ver todas <?= icon('arrow-right') ?></a>
            </header>
            <?php if ($posts === []): ?>
                <div class="panel__empty"><?= icon('inbox') ?><p>Sin publicaciones.</p></div>
            <?php else: ?>
                <ul class="content-list">
                    <?php foreach ($posts as $post): ?>
                        <li class="content-row">
                            <div class="content-row__body">
                                <p class="content-row__text"><?= e(mb_strimwidth((string) ($post['body'] ?? ''), 0, 160, '…')) ?: '<span class="content-row__muted">Sin texto</span>' ?></p>
                                <p class="content-row__muted">
                                    <?= time_tag((string) $post['created_at']) ?>
                                    <?php if ($post['status'] === 'hidden'): ?> · <span class="chip chip--warning">Oculta</span><?php endif; ?>
                                    <?php if ((int) $post['open_reports'] > 0): ?> · <a href="<?= e(url('admin/reports.php', ['type' => 'post', 'id' => $post['id']])) ?>"><?= (int) $post['open_reports'] ?> reportes</a><?php endif; ?>
                                </p>
                            </div>
                        </li>
                    <?php endforeach; ?>
                </ul>
            <?php endif; ?>
        </section>
    </div>

    <aside class="admin-detail__side">
        <section class="panel">
            <header class="panel__head"><h2><?= icon('shield') ?> Acciones</h2></header>
            <?php if ($isSelf): ?>
                <div class="panel__empty"><?= icon('info') ?><p>Esta es tu cuenta: gestiónala desde Configuración de TREVIX.</p></div>
            <?php elseif (!$canAct && !$isAdmin): ?>
                <div class="panel__empty"><?= icon('lock') ?><p>Solo un administrador puede actuar sobre esta cuenta.</p></div>
            <?php else: ?>
                <div class="decision">
                    <?php if ($canAct): ?>
                        <?php if ($suspended): ?>
                            <form method="post" action="<?= e($action) ?>" data-confirm="¿Levantar la suspensión de @<?= e($user['username']) ?>?" data-confirm-label="Levantar">
                                <?= csrf_field() ?>
                                <input type="hidden" name="id" value="<?= $id ?>">
                                <input type="hidden" name="action" value="unsuspend">
                                <button type="submit" class="btn btn--secondary btn--block"><?= icon('user-check') ?> Levantar suspensión</button>
                            </form>
                        <?php endif; ?>
                        <form class="decision__form" method="post" action="<?= e($action) ?>"
                            data-confirm="¿Suspender a @<?= e($user['username']) ?>? Se cerrarán sus sesiones y no podrá entrar." data-confirm-label="Suspender">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="suspend">
                            <p class="decision__title"><?= $suspended ? 'Cambiar la suspensión' : 'Suspender cuenta' ?></p>
                            <div class="field">
                                <label class="field__label" for="suspend-days">Duración</label>
                                <select class="select" id="suspend-days" name="days">
                                    <?php foreach ($durations as $days => $label): ?>
                                        <option value="<?= (int) $days ?>"<?= $days === 7 ? ' selected' : '' ?>><?= e($label) ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <div class="field">
                                <label class="field__label" for="suspend-reason">Motivo</label>
                                <textarea class="input textarea" id="suspend-reason" name="reason" required minlength="5" maxlength="255" rows="3"
                                    placeholder="La persona verá este motivo al intentar entrar."></textarea>
                            </div>
                            <button type="submit" class="btn btn--danger btn--block"><?= icon('ban') ?> Suspender</button>
                        </form>
                        <form class="decision__form" method="post" action="<?= e($action) ?>"
                            data-confirm="¿Advertir a @<?= e($user['username']) ?>? Recibirá un aviso con el motivo." data-confirm-label="Advertir">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="warn">
                            <p class="decision__title">Advertir</p>
                            <div class="field">
                                <label class="field__label" for="warn-reason">Motivo</label>
                                <textarea class="input textarea" id="warn-reason" name="reason" required minlength="5" maxlength="255" rows="2"
                                    placeholder="La persona verá este motivo. Durante <?= (int) $warningDays ?> días no podrá pedir el verificado."></textarea>
                            </div>
                            <button type="submit" class="btn btn--secondary btn--block"><?= icon('triangle-alert') ?> Advertir</button>
                        </form>
                    <?php endif; ?>

                    <?php if ($isAdmin): ?>
                        <form class="decision__form" method="post" action="<?= e($action) ?>"
                            data-confirm="¿Cambiar el rol de @<?= e($user['username']) ?>?" data-confirm-label="Cambiar rol">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="role">
                            <div class="field">
                                <label class="field__label" for="user-role">Rol</label>
                                <select class="select" id="user-role" name="role">
                                    <?php foreach (User::ROLE_LABELS as $key => $label): ?>
                                        <option value="<?= e($key) ?>"<?= $user['role'] === $key ? ' selected' : '' ?>><?= e($label) ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <button type="submit" class="btn btn--secondary btn--block"><?= icon('shield-check') ?> Guardar rol</button>
                        </form>
                        <form method="post" action="<?= e($action) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="<?= $user['is_verified'] ? 'unverify' : 'verify' ?>">
                            <button type="submit" class="btn btn--ghost btn--block"><?= icon('badge-check') ?> <?= $user['is_verified'] ? 'Quitar verificación' : 'Verificar cuenta' ?></button>
                        </form>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </section>

        <?php if ($warnings !== []): ?>
            <section class="panel">
                <header class="panel__head"><h2><?= icon('triangle-alert') ?> Advertencias</h2></header>
                <ul class="content-list">
                    <?php foreach ($warnings as $w): ?>
                        <?php $recent = !$w['revoked'] && strtotime((string) $w['created_at']) > time() - $warningDays * 86400; ?>
                        <li class="content-row">
                            <div class="content-row__body">
                                <p class="content-row__text"><?= e($w['reason']) ?></p>
                                <p class="content-row__muted">
                                    <?= time_tag((string) $w['created_at']) ?><?= $w['issued_by_username'] !== null ? ' · @' . e($w['issued_by_username']) : '' ?>
                                    <?php if ($w['revoked']): ?>
                                        · <span class="chip chip--muted">Retirada<?= $w['revoked_by_username'] !== null ? ' por @' . e($w['revoked_by_username']) : '' ?></span>
                                    <?php elseif ($recent): ?>
                                        · <span class="chip chip--warning">Vigente</span>
                                    <?php endif; ?>
                                </p>
                            </div>
                            <?php if (!$w['revoked'] && $canAct): ?>
                                <form method="post" action="<?= e($action) ?>" data-confirm="¿Retirar esta advertencia? Dejará de contar para el verificado." data-confirm-label="Retirar">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= $id ?>">
                                    <input type="hidden" name="warning_id" value="<?= (int) $w['id'] ?>">
                                    <input type="hidden" name="action" value="revoke_warning">
                                    <button type="submit" class="btn btn--ghost btn--sm"><?= icon('undo-2') ?> Retirar</button>
                                </form>
                            <?php endif; ?>
                        </li>
                    <?php endforeach; ?>
                </ul>
            </section>
        <?php endif; ?>

        <?php if ($history !== []): ?>
            <section class="panel">
                <header class="panel__head"><h2><?= icon('history') ?> Historial</h2></header>
                <ul class="audit-list">
                    <?php foreach ($history as $entry): ?>
                        <?php View::partial('admin-audit-entry', ['entry' => $entry]); ?>
                    <?php endforeach; ?>
                </ul>
            </section>
        <?php endif; ?>
    </aside>
</div>
