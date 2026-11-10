<?php

use Trevix\Core\View;
use Trevix\Models\Support;

/**
 * Solicitudes que IX registró en el chat de soporte: categoría, prioridad, resumen y lo último que escribió la
 * persona; responder como la cuenta de soporte, cerrar o reabrir.
 *
 * @var string      $status
 * @var string|null $category
 * @var array       $counts     Support::counts()
 * @var array       $tickets    Support::adminList()
 * @var array|null  $account    cuenta de soporte
 * @var bool        $configured hay clave de Gemini
 * @var string      $username   usuario configurado para soporte
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
$action = url('admin/support.php');
$priorityChip = ['alta' => 'chip--danger', 'media' => 'chip--warning', 'baja' => 'chip--muted'];
?>
<?php if ($account === null): ?>
    <div class="alert alert--error" role="alert">
        <?= icon('triangle-alert') ?>
        <p>No existe una cuenta activa @<?= e($username) ?>. IX no puede responder ni dar la bienvenida hasta que exista.</p>
    </div>
<?php elseif (!$configured): ?>
    <div class="alert alert--info" role="status">
        <?= icon('info') ?>
        <p>
            IX aún no tiene la clave de la API de Gemini (Google AI Studio). Mientras tanto avisa a quien escribe que el
            equipo revisará su mensaje, registra cada consulta aquí y envía bienvenidas con mensajes preparados.
        </p>
    </div>
<?php endif; ?>

<nav class="admin-tabs" aria-label="Estado de las solicitudes">
    <?php foreach (Support::STATUSES as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/support.php', ['status' => $key === 'open' ? null : $key, 'category' => $category])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e($label) ?>
            <?php if (($counts[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $counts[$key] ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<form class="admin-search" method="get" action="<?= e($action) ?>">
    <?php if ($status !== 'open'): ?><input type="hidden" name="status" value="<?= e($status) ?>"><?php endif; ?>
    <div class="select-wrap">
        <select class="select" name="category" aria-label="Categoría">
            <option value="">Todas las categorías</option>
            <?php foreach (Support::CATEGORIES as $key => $label): ?>
                <option value="<?= e($key) ?>"<?= $category === $key ? ' selected' : '' ?>><?= e($label) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn--secondary">Filtrar</button>
</form>

<p class="content-row__muted">
    IX responde en el chat de @<?= e($username) ?> y registra aquí los errores, sugerencias, reportes, quejas, reclamos,
    peticiones y lo que necesita a una persona. Si respondes desde aquí (o desde la cuenta de soporte), IX se pausa en
    ese chat durante unas horas.
</p>

<section class="panel">
    <?php if ($tickets === []): ?>
        <div class="panel__empty">
            <?= icon('sparkles') ?>
            <p><?= $status === 'open' ? 'No hay solicitudes abiertas.' : 'No hay solicitudes cerradas.' ?></p>
        </div>
    <?php else: ?>
        <ul class="content-list">
            <?php foreach ($tickets as $t): ?>
                <?php $tid = (int) $t['id']; ?>
                <li class="content-row" id="solicitud-<?= $tid ?>">
                    <div class="content-row__body">
                        <p class="content-row__author">
                            <?= avatar($t, 'xs') ?>
                            <a href="<?= e(url('admin/users.php', ['id' => $t['user_id']])) ?>"><strong><?= e($t['display_name']) ?></strong> (@<?= e($t['username']) ?>)</a>
                            <span class="chip chip--brand"><?= e(Support::CATEGORIES[$t['category']] ?? $t['category']) ?></span>
                            <span class="chip <?= e($priorityChip[$t['priority']] ?? 'chip--muted') ?>">Prioridad <?= e(mb_strtolower(Support::PRIORITIES[$t['priority']] ?? $t['priority'])) ?></span>
                            <?php if ((int) $t['needs_human'] === 1): ?><span class="chip chip--warning"><?= icon('user') ?> Necesita a una persona</span><?php endif; ?>
                            <?php if ($t['user_status'] !== 'active'): ?><span class="chip chip--danger">Cuenta no activa</span><?php endif; ?>
                        </p>
                        <?php if ($t['summary'] !== ''): ?>
                            <p class="content-row__text"><strong><?= e($t['summary']) ?></strong></p>
                        <?php endif; ?>
                        <?php if ($t['excerpt'] !== ''): ?>
                            <p class="content-row__text">«<?= e($t['excerpt']) ?>»</p>
                        <?php endif; ?>
                        <p class="content-row__muted">
                            Abierta <?= time_tag((string) $t['created_at']) ?> · último mensaje <?= time_tag((string) $t['updated_at']) ?>
                            <?php if ($t['closed_at'] !== null): ?>
                                · cerrada <?= time_tag((string) $t['closed_at']) ?><?= $t['closer_username'] !== null ? ' por @' . e($t['closer_username']) : '' ?>
                            <?php endif; ?>
                        </p>
                    </div>
                    <div class="content-row__actions">
                        <?php if ($account !== null && $t['user_status'] === 'active'): ?>
                            <details class="admin-menu">
                                <summary class="btn btn--primary btn--sm"><?= icon('send') ?> Responder</summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $tid ?>">
                                        <input type="hidden" name="action" value="reply">
                                        <label class="field__label" for="reply-<?= $tid ?>">Mensaje como @<?= e($account['username']) ?></label>
                                        <textarea class="input" id="reply-<?= $tid ?>" name="reply" rows="4" required minlength="2" maxlength="2000"></textarea>
                                        <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('send') ?> Enviar</button>
                                    </form>
                                </div>
                            </details>
                        <?php endif; ?>
                        <form method="post" action="<?= e($action) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $tid ?>">
                            <?php if ($t['status'] === 'open'): ?>
                                <input type="hidden" name="action" value="close">
                                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('circle-check') ?> Cerrar</button>
                            <?php else: ?>
                                <input type="hidden" name="action" value="reopen">
                                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('rotate-ccw') ?> Reabrir</button>
                            <?php endif; ?>
                        </form>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
