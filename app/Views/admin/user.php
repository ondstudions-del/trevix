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
 * @var array $record      UserRecord::summary()
 * @var array $reportsReceived Report::againstUser()
 * @var array $reportsMade Report::byReporter()
 * @var array $appeals     Appeal::forUser()
 * @var array $errors
 * @var array $old
 */
$statusChip = ['active' => 'chip--success', 'suspended' => 'chip--danger', 'deactivated' => 'chip--muted'];
$reportStatus = ['open' => ['Abierto', 'chip--warning'], 'reviewing' => ['En revisión', 'chip--warning'], 'resolved' => ['Con medida', 'chip--danger'], 'dismissed' => ['Descartado', 'chip--muted']];
$appealStatus = ['pending' => 'chip--warning', 'accepted' => 'chip--success', 'rejected' => 'chip--muted'];
$id = (int) $user['id'];
$action = url('admin/users.php');
$suspended = $user['status'] === 'suspended';
$banned = $suspended && empty($user['suspended_until']);
$canEdit = $isAdmin && $canAct;
$value = static fn (string $field) => (string) ($old[$field] ?? $user[$field] ?? '');
?>
<a class="admin-back" href="<?= e(url('admin/users.php')) ?>"><?= icon('arrow-left') ?> <?= e(t('Volver a usuarios')) ?></a>

<div class="admin-detail">
    <div class="admin-detail__main">
        <section class="panel">
            <div class="user-card">
                <?= avatar($user, 'xl') ?>
                <div class="user-card__info">
                    <h2><?= e($user['display_name']) ?><?php if ($user['is_verified']): ?> <?= icon('badge-check', 'verified', t('Verificada')) ?><?php endif; ?></h2>
                    <p class="user-card__handle">@<?= e($user['username']) ?> · <?= e($user['email']) ?><?php if (!empty($user['phone'])): ?> · <?= e($user['phone']) ?><?php endif; ?></p>
                    <p class="user-card__chips">
                        <span class="chip chip--brand"><?= e(t(User::ROLE_LABELS[$user['role']] ?? $user['role'])) ?></span>
                        <span class="chip <?= e($statusChip[$user['status']] ?? 'chip--muted') ?>"><?= e(t(User::STATUS_LABELS[$user['status']] ?? $user['status'])) ?></span>
                        <?php if ($user['email_verified_at'] === null): ?><span class="chip chip--muted"><?= e(t('Correo sin verificar')) ?></span><?php endif; ?>
                        <?php if ($user['is_private']): ?><span class="chip chip--muted"><?= icon('lock') ?> <?= e(t('Privada')) ?></span><?php endif; ?>
                    </p>
                    <?php if ($user['bio']): ?><p class="user-card__bio"><?= e($user['bio']) ?></p><?php endif; ?>
                </div>
            </div>
            <?php if ($suspended): ?>
                <div class="alert alert--error user-card__alert">
                    <?= icon('ban') ?>
                    <p>
                        <strong><?= $user['suspended_until']
                            ? e(t('Suspendida hasta el {date}.', ['date' => full_date((string) $user['suspended_until'])]))
                            : e(t('Baneada: suspendida sin fecha de fin.')) ?></strong>
                        <?php if ($user['suspended_until'] && strtotime((string) $user['suspended_until']) < time()): ?>
                            <?= e(t('La suspensión ya venció: se reactivará cuando vuelva a iniciar sesión.')) ?>
                        <?php endif; ?>
                        <?php if ($user['suspension_reason']): ?><?= e(t('Motivo:')) ?> <?= e($user['suspension_reason']) ?><?php endif; ?>
                    </p>
                </div>
            <?php endif; ?>
            <dl class="user-stats">
                <div><dt><?= e(t('Publicaciones')) ?></dt><dd><?= compact_number((int) $user['posts_count']) ?></dd></div>
                <div><dt><?= e(t('Seguidores')) ?></dt><dd><?= compact_number((int) $user['followers_count']) ?></dd></div>
                <div><dt><?= e(t('Siguiendo')) ?></dt><dd><?= compact_number((int) $user['following_count']) ?></dd></div>
                <div><dt><?= e(t('Reportes pendientes')) ?></dt><dd><?= $openReports ?></dd></div>
                <div><dt><?= e(t('Fecha de alta')) ?></dt><dd><?= e(full_date((string) $user['created_at'], false)) ?></dd></div>
                <div><dt><?= e(t('Última actividad')) ?></dt><dd><?= $user['last_seen_at'] ? time_tag((string) $user['last_seen_at']) : '—' ?></dd></div>
            </dl>
            <?php if ($user['status'] === 'active'): ?>
                <p class="user-card__link"><a href="<?= e(profile_url($user)) ?>" target="_blank" rel="noopener"><?= e(t('Ver perfil en TREVIX')) ?> <?= icon('external-link') ?></a></p>
            <?php endif; ?>
        </section>

        <section class="panel" id="historial">
            <header class="panel__head"><h2><?= icon('flag') ?> <?= e(t('Faltas, reportes y apelaciones')) ?></h2></header>
            <dl class="user-stats user-stats--record">
                <div class="<?= cx(['user-stats__alert' => $record['strikes'] > 0]) ?>"><dt><?= e(t('Faltas')) ?></dt><dd><?= (int) $record['strikes'] ?></dd></div>
                <div><dt><?= e(t('Advertencias vigentes')) ?></dt><dd><?= (int) $record['warnings_active'] ?></dd></div>
                <div><dt><?= e(t('Suspensiones')) ?></dt><dd><?= (int) $record['suspensions'] ?></dd></div>
                <div><dt><?= e(t('Baneos')) ?></dt><dd><?= (int) $record['bans'] ?></dd></div>
                <div><dt><?= e(t('Contenido retirado')) ?></dt><dd><?= (int) $record['removed_content'] ?></dd></div>
                <div><dt><?= e(t('Reportes recibidos')) ?></dt><dd><?= (int) $record['reports_received']['total'] ?></dd></div>
                <div><dt><?= e(t('Reportes con medida')) ?></dt><dd><?= (int) $record['reports_received']['resolved'] ?></dd></div>
                <div><dt><?= e(t('Reportes que hizo')) ?></dt><dd><?= (int) $record['reports_made']['total'] ?><?php if ($record['reports_made']['dismissed'] > 0): ?> <small>(<?= (int) $record['reports_made']['dismissed'] ?> <?= e(t('descartados')) ?>)</small><?php endif; ?></dd></div>
                <div><dt><?= e(t('Apelaciones')) ?></dt><dd><?= array_sum($record['appeals']) ?><?php if ($record['appeals']['pending'] > 0): ?> <small>(<?= (int) $record['appeals']['pending'] ?> <?= e(t('pendientes')) ?>)</small><?php endif; ?></dd></div>
            </dl>
            <p class="content-row__muted user-record__note">
                <?= e(t('Faltas = advertencias vigentes + suspensiones y baneos (sin contar los levantados por apelación) + contenido retirado por moderación.')) ?>
                <?= e(t('IX tiene en cuenta este historial al atender a la persona en soporte.')) ?>
            </p>

            <h3 class="user-record__title"><?= icon('scale') ?> <?= e(t('Apelaciones')) ?></h3>
            <?php if ($appeals === []): ?>
                <p class="content-row__muted user-record__note"><?= e(t('No ha enviado apelaciones.')) ?></p>
            <?php else: ?>
                <ul class="content-list">
                    <?php foreach ($appeals as $ap): ?>
                        <li class="content-row" id="apelacion-<?= (int) $ap['id'] ?>">
                            <div class="content-row__body">
                                <p class="content-row__author">
                                    <span class="chip chip--brand"><?= e(t(\Trevix\Models\Appeal::TYPES[$ap['type']] ?? $ap['type'])) ?></span>
                                    <span class="chip <?= e($appealStatus[$ap['status']] ?? 'chip--muted') ?>"><?= e(t(\Trevix\Models\Appeal::STATUSES[$ap['status']] ?? $ap['status'])) ?></span>
                                    <?= time_tag((string) $ap['created_at']) ?>
                                </p>
                                <?php if (!empty($ap['sanction_reason'])): ?>
                                    <p class="content-row__muted"><?= e(t('Sanción')) ?>: «<?= e($ap['sanction_reason']) ?>»</p>
                                <?php endif; ?>
                                <p class="content-row__text">«<?= e($ap['message']) ?>»</p>
                                <?php if ($ap['status'] !== 'pending'): ?>
                                    <p class="content-row__muted">
                                        <?= e(t('Revisada')) ?> <?= time_tag((string) $ap['reviewed_at']) ?><?= $ap['reviewer_username'] !== null ? ' · @' . e($ap['reviewer_username']) : '' ?>
                                        <?php if (!empty($ap['resolution_note'])): ?> · «<?= e($ap['resolution_note']) ?>»<?php endif; ?>
                                    </p>
                                <?php endif; ?>
                            </div>
                            <?php if ($ap['status'] === 'pending' && $canAct): ?>
                                <?php View::partial('admin-appeal-actions', ['appeal' => $ap]); ?>
                            <?php endif; ?>
                        </li>
                    <?php endforeach; ?>
                </ul>
            <?php endif; ?>

            <h3 class="user-record__title"><?= icon('flag') ?> <?= e(t('Reportes recibidos')) ?></h3>
            <?php if ($reportsReceived === []): ?>
                <p class="content-row__muted user-record__note"><?= e(t('Nadie ha reportado esta cuenta ni su contenido.')) ?></p>
            <?php else: ?>
                <ul class="content-list">
                    <?php foreach ($reportsReceived as $r): ?>
                        <?php [$statusLabel, $statusClass] = $reportStatus[$r['status']] ?? [$r['status'], 'chip--muted']; ?>
                        <li class="content-row">
                            <div class="content-row__body">
                                <p class="content-row__author">
                                    <span class="chip chip--brand"><?= e(t(\Trevix\Models\Report::TYPES[$r['target_type']] ?? $r['target_type'])) ?></span>
                                    <span class="chip <?= e($statusClass) ?>"><?= e(t($statusLabel)) ?></span>
                                    <strong><?= e(t(\Trevix\Models\Report::REASONS[$r['reason']] ?? $r['reason'])) ?></strong>
                                </p>
                                <?php if (!empty($r['details'])): ?><p class="content-row__text">«<?= e(mb_strimwidth((string) $r['details'], 0, 200, '…')) ?>»</p><?php endif; ?>
                                <p class="content-row__muted">
                                    <?= time_tag((string) $r['created_at']) ?><?= $r['reporter_username'] !== null ? ' · ' . e(t('reportó')) . ' @' . e($r['reporter_username']) : '' ?>
                                    · <a href="<?= e(url('admin/reports.php', ['type' => $r['target_type'], 'id' => (int) $r['target_id']])) ?>"><?= e(t('Ver reporte')) ?></a>
                                    <?php if (!empty($r['resolution_note'])): ?> · «<?= e($r['resolution_note']) ?>»<?php endif; ?>
                                </p>
                            </div>
                        </li>
                    <?php endforeach; ?>
                </ul>
            <?php endif; ?>

            <?php if ($reportsMade !== []): ?>
                <h3 class="user-record__title"><?= icon('send') ?> <?= e(t('Reportes que hizo')) ?></h3>
                <ul class="content-list">
                    <?php foreach ($reportsMade as $r): ?>
                        <?php [$statusLabel, $statusClass] = $reportStatus[$r['status']] ?? [$r['status'], 'chip--muted']; ?>
                        <li class="content-row">
                            <div class="content-row__body">
                                <p class="content-row__author">
                                    <span class="chip chip--brand"><?= e(t(\Trevix\Models\Report::TYPES[$r['target_type']] ?? $r['target_type'])) ?></span>
                                    <span class="chip <?= e($statusClass) ?>"><?= e(t($statusLabel)) ?></span>
                                    <?= e(t(\Trevix\Models\Report::REASONS[$r['reason']] ?? $r['reason'])) ?>
                                </p>
                                <p class="content-row__muted">
                                    <?= time_tag((string) $r['created_at']) ?>
                                    · <a href="<?= e(url('admin/reports.php', ['type' => $r['target_type'], 'id' => (int) $r['target_id']])) ?>"><?= e(t('Ver reporte')) ?></a>
                                </p>
                            </div>
                        </li>
                    <?php endforeach; ?>
                </ul>
            <?php endif; ?>
        </section>

        <?php if ($canEdit): ?>
            <section class="panel" id="editar">
                <header class="panel__head"><h2><?= icon('pencil') ?> <?= e(t('Editar datos de la cuenta')) ?></h2></header>
                <form class="form user-edit" method="post" action="<?= e($action) ?>" novalidate
                    data-confirm="<?= e(t('¿Guardar los cambios en la cuenta de @{username}? Le avisaremos por correo.', ['username' => $user['username']])) ?>" data-confirm-label="<?= e(t('Guardar')) ?>">
                    <?= csrf_field() ?>
                    <input type="hidden" name="id" value="<?= $id ?>">
                    <input type="hidden" name="action" value="edit">
                    <div class="user-edit__grid">
                        <div class="field">
                            <label class="field__label" for="edit-name"><?= e(t('Nombre')) ?></label>
                            <input class="input" id="edit-name" name="display_name" required maxlength="60" data-rule="required"
                                value="<?= e($value('display_name')) ?>"<?= invalid_attrs($errors, 'display_name', 'edit-name') ?>>
                            <?= field_error($errors, 'display_name', 'edit-name') ?>
                        </div>
                        <div class="field">
                            <label class="field__label" for="edit-username"><?= e(t('Nombre de usuario')) ?></label>
                            <div class="input-wrap input-wrap--prefix">
                                <span class="input-wrap__prefix">@</span>
                                <input class="input" id="edit-username" name="username" required minlength="3" maxlength="30" pattern="[a-z0-9_.]{3,30}"
                                    data-rule="username" spellcheck="false" autocapitalize="none"
                                    value="<?= e($value('username')) ?>"<?= invalid_attrs($errors, 'username', 'edit-username') ?>>
                            </div>
                            <?= field_error($errors, 'username', 'edit-username') ?>
                        </div>
                        <div class="field">
                            <label class="field__label" for="edit-email"><?= e(t('Correo electrónico')) ?></label>
                            <input class="input" id="edit-email" name="email" type="email" required maxlength="190" data-rule="email" spellcheck="false" autocapitalize="none"
                                value="<?= e($value('email')) ?>"<?= invalid_attrs($errors, 'email', 'edit-email') ?>>
                            <?= field_error($errors, 'email', 'edit-email') ?>
                        </div>
                        <div class="field">
                            <label class="field__label" for="edit-phone"><?= e(t('Teléfono')) ?> <span class="field__optional"><?= e(t('(opcional)')) ?></span></label>
                            <input class="input" id="edit-phone" name="phone" type="tel" maxlength="20" inputmode="tel" placeholder="+57 300 123 4567"
                                value="<?= e($value('phone')) ?>"<?= invalid_attrs($errors, 'phone', 'edit-phone') ?>>
                            <?= field_error($errors, 'phone', 'edit-phone') ?>
                        </div>
                        <div class="field">
                            <label class="field__label" for="edit-password"><?= e(t('Nueva contraseña')) ?> <span class="field__optional"><?= e(t('(déjala vacía para no cambiarla)')) ?></span></label>
                            <div class="input-wrap">
                                <?= icon('key-round') ?>
                                <input class="input" id="edit-password" name="new_password" type="password" autocomplete="new-password" maxlength="200"<?= invalid_attrs($errors, 'password', 'edit-password') ?>>
                                <button type="button" class="input-wrap__action" data-toggle-password aria-label="<?= e(t('Mostrar contraseña')) ?>" aria-pressed="false">
                                    <?= icon('eye', 'when-hidden') ?><?= icon('eye-off', 'when-visible') ?>
                                </button>
                            </div>
                            <?= field_error($errors, 'password', 'edit-password') ?>
                            <p class="field__hint"><?= e(t('Si la cambias, se cerrarán todas sus sesiones (web y app).')) ?></p>
                        </div>
                        <div class="field user-edit__check">
                            <?php $verifiedChecked = isset($old['email_verified']) ? (bool) $old['email_verified'] : !empty($user['email_verified_at']); ?>
                            <label class="checkbox">
                                <input type="checkbox" name="email_verified" value="1"<?= $verifiedChecked ? ' checked' : '' ?>>
                                <span class="checkbox__box"><?= icon('check') ?></span>
                                <span><?= e(t('Correo confirmado')) ?></span>
                            </label>
                            <p class="field__hint"><?= e(t('Si cambias el correo y lo dejas sin marcar, la persona tendrá que confirmarlo.')) ?></p>
                        </div>
                    </div>
                    <div class="form__actions">
                        <button type="submit" class="btn btn--primary"><?= icon('check') ?> <?= e(t('Guardar cambios')) ?></button>
                    </div>
                </form>
            </section>
        <?php endif; ?>

        <section class="panel">
            <header class="panel__head">
                <h2><?= icon('file-text') ?> <?= e(t('Publicaciones recientes')) ?></h2>
                <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/content.php', ['q' => '@' . $user['username']])) ?>"><?= e(t('Ver todas')) ?> <?= icon('arrow-right') ?></a>
            </header>
            <?php if ($posts === []): ?>
                <div class="panel__empty"><?= icon('inbox') ?><p><?= e(t('Sin publicaciones.')) ?></p></div>
            <?php else: ?>
                <ul class="content-list">
                    <?php foreach ($posts as $post): ?>
                        <li class="content-row">
                            <div class="content-row__body">
                                <p class="content-row__text"><?= e(mb_strimwidth((string) ($post['body'] ?? ''), 0, 160, '…')) ?: '<span class="content-row__muted">' . e(t('Sin texto')) . '</span>' ?></p>
                                <p class="content-row__muted">
                                    <?= time_tag((string) $post['created_at']) ?>
                                    <?php if ($post['status'] === 'hidden'): ?> · <span class="chip chip--warning"><?= e(t('Oculta')) ?></span><?php endif; ?>
                                    <?php if ((int) $post['open_reports'] > 0): ?> · <a href="<?= e(url('admin/reports.php', ['type' => 'post', 'id' => $post['id']])) ?>"><?= e(tn((int) $post['open_reports'], '{n} reporte', '{n} reportes')) ?></a><?php endif; ?>
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
            <header class="panel__head"><h2><?= icon('shield') ?> <?= e(t('Acciones')) ?></h2></header>
            <?php if ($isSelf): ?>
                <div class="panel__empty"><?= icon('info') ?><p><?= e(t('Esta es tu cuenta: gestiónala desde Configuración de TREVIX.')) ?></p></div>
            <?php elseif (!$canAct && !$isAdmin): ?>
                <div class="panel__empty"><?= icon('lock') ?><p><?= e(t('Solo un administrador puede actuar sobre esta cuenta.')) ?></p></div>
            <?php else: ?>
                <div class="decision">
                    <?php if ($canAct): ?>
                        <?php if ($suspended): ?>
                            <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Levantar la suspensión de @{username}?', ['username' => $user['username']])) ?>" data-confirm-label="<?= e(t('Levantar')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="id" value="<?= $id ?>">
                                <input type="hidden" name="action" value="unsuspend">
                                <button type="submit" class="btn btn--secondary btn--block"><?= icon('user-check') ?> <?= e(t('Levantar suspensión')) ?></button>
                            </form>
                        <?php endif; ?>
                        <form class="decision__form" method="post" action="<?= e($action) ?>"
                            data-confirm="<?= e(t('¿Suspender a @{username}? Se cerrarán sus sesiones y no podrá entrar.', ['username' => $user['username']])) ?>" data-confirm-label="<?= e(t('Suspender')) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="suspend">
                            <p class="decision__title"><?= $suspended ? e(t('Cambiar la suspensión')) : e(t('Suspender cuenta')) ?></p>
                            <div class="field">
                                <label class="field__label" for="suspend-days"><?= e(t('Duración')) ?></label>
                                <select class="select" id="suspend-days" name="days">
                                    <?php foreach ($durations as $days => $label): ?>
                                        <option value="<?= (int) $days ?>"<?= $days === 7 ? ' selected' : '' ?>><?= e(t($label)) ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <div class="field">
                                <label class="field__label" for="suspend-reason"><?= e(t('Motivo')) ?></label>
                                <textarea class="input textarea" id="suspend-reason" name="reason" required minlength="5" maxlength="255" rows="3"
                                    placeholder="<?= e(t('La persona verá este motivo al intentar entrar.')) ?>"></textarea>
                            </div>
                            <button type="submit" class="btn btn--danger btn--block"><?= icon('ban') ?> <?= e(t('Suspender')) ?></button>
                        </form>
                        <?php if ($isAdmin && !$banned): ?>
                            <form class="decision__form" method="post" action="<?= e($action) ?>"
                                data-confirm="<?= e(t('¿Banear a @{username}? No podrá entrar hasta que se levante el baneo o se acepte su apelación.', ['username' => $user['username']])) ?>" data-confirm-label="<?= e(t('Banear')) ?>">
                                <?= csrf_field() ?>
                                <input type="hidden" name="id" value="<?= $id ?>">
                                <input type="hidden" name="action" value="ban">
                                <p class="decision__title"><?= e(t('Banear cuenta')) ?></p>
                                <div class="field">
                                    <label class="field__label" for="ban-reason"><?= e(t('Motivo')) ?></label>
                                    <textarea class="input textarea" id="ban-reason" name="reason" required minlength="5" maxlength="255" rows="2"
                                        placeholder="<?= e(t('Suspensión sin fecha de fin. La persona verá el motivo y podrá apelar.')) ?>"></textarea>
                                </div>
                                <button type="submit" class="btn btn--danger btn--block"><?= icon('ban') ?> <?= e(t('Banear')) ?></button>
                            </form>
                        <?php endif; ?>
                        <form class="decision__form" method="post" action="<?= e($action) ?>"
                            data-confirm="<?= e(t('¿Advertir a @{username}? Recibirá un aviso con el motivo.', ['username' => $user['username']])) ?>" data-confirm-label="<?= e(t('Advertir')) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="warn">
                            <p class="decision__title"><?= e(t('Advertir')) ?></p>
                            <div class="field">
                                <label class="field__label" for="warn-reason"><?= e(t('Motivo')) ?></label>
                                <textarea class="input textarea" id="warn-reason" name="reason" required minlength="5" maxlength="255" rows="2"
                                    placeholder="<?= e(t('La persona verá este motivo. Durante {days} días no podrá pedir el verificado.', ['days' => (int) $warningDays])) ?>"></textarea>
                            </div>
                            <button type="submit" class="btn btn--secondary btn--block"><?= icon('triangle-alert') ?> <?= e(t('Advertir')) ?></button>
                        </form>
                    <?php endif; ?>

                    <?php if ($isAdmin): ?>
                        <form class="decision__form" method="post" action="<?= e($action) ?>"
                            data-confirm="<?= e(t('¿Cambiar el rol de @{username}?', ['username' => $user['username']])) ?>" data-confirm-label="<?= e(t('Cambiar rol')) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="role">
                            <div class="field">
                                <label class="field__label" for="user-role"><?= e(t('Rol')) ?></label>
                                <select class="select" id="user-role" name="role">
                                    <?php foreach (User::ROLE_LABELS as $key => $label): ?>
                                        <option value="<?= e($key) ?>"<?= $user['role'] === $key ? ' selected' : '' ?>><?= e(t($label)) ?></option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            <button type="submit" class="btn btn--secondary btn--block"><?= icon('shield-check') ?> <?= e(t('Guardar rol')) ?></button>
                        </form>
                        <form method="post" action="<?= e($action) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $id ?>">
                            <input type="hidden" name="action" value="<?= $user['is_verified'] ? 'unverify' : 'verify' ?>">
                            <button type="submit" class="btn btn--ghost btn--block"><?= icon('badge-check') ?> <?= $user['is_verified'] ? e(t('Quitar verificación')) : e(t('Verificar cuenta')) ?></button>
                        </form>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </section>

        <?php if ($warnings !== []): ?>
            <section class="panel">
                <header class="panel__head"><h2><?= icon('triangle-alert') ?> <?= e(t('Advertencias')) ?></h2></header>
                <ul class="content-list">
                    <?php foreach ($warnings as $w): ?>
                        <?php $recent = !$w['revoked'] && strtotime((string) $w['created_at']) > time() - $warningDays * 86400; ?>
                        <li class="content-row">
                            <div class="content-row__body">
                                <p class="content-row__text"><?= e($w['reason']) ?></p>
                                <p class="content-row__muted">
                                    <?= time_tag((string) $w['created_at']) ?><?= $w['issued_by_username'] !== null ? ' · @' . e($w['issued_by_username']) : '' ?>
                                    <?php if ($w['revoked']): ?>
                                        · <span class="chip chip--muted"><?= e(t('Retirada')) ?><?= $w['revoked_by_username'] !== null ? ' ' . e(t('por @{username}', ['username' => $w['revoked_by_username']])) : '' ?></span>
                                    <?php elseif ($recent): ?>
                                        · <span class="chip chip--warning"><?= e(t('Vigente')) ?></span>
                                    <?php endif; ?>
                                </p>
                            </div>
                            <?php if (!$w['revoked'] && $canAct): ?>
                                <form method="post" action="<?= e($action) ?>" data-confirm="<?= e(t('¿Retirar esta advertencia? Dejará de contar para el verificado.')) ?>" data-confirm-label="<?= e(t('Retirar')) ?>">
                                    <?= csrf_field() ?>
                                    <input type="hidden" name="id" value="<?= $id ?>">
                                    <input type="hidden" name="warning_id" value="<?= (int) $w['id'] ?>">
                                    <input type="hidden" name="action" value="revoke_warning">
                                    <button type="submit" class="btn btn--ghost btn--sm"><?= icon('undo-2') ?> <?= e(t('Retirar')) ?></button>
                                </form>
                            <?php endif; ?>
                        </li>
                    <?php endforeach; ?>
                </ul>
            </section>
        <?php endif; ?>

        <?php if ($history !== []): ?>
            <section class="panel">
                <header class="panel__head"><h2><?= icon('history') ?> <?= e(t('Historial')) ?></h2></header>
                <ul class="audit-list">
                    <?php foreach ($history as $entry): ?>
                        <?php View::partial('admin-audit-entry', ['entry' => $entry]); ?>
                    <?php endforeach; ?>
                </ul>
            </section>
        <?php endif; ?>
    </aside>
</div>
