<?php

use Trevix\Core\View;
use Trevix\Models\Support;
use Trevix\Services\Ix;

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
 * @var string|null $keyHint    últimos caracteres de la clave de Gemini
 * @var bool        $canConfigure solo administradores
 * @var array       $ix         replies, welcome, model, pause, instructions, perUser, daily
 * @var array       $activity   Support::activity()
 * @var bool        $isPreview
 * @var string|null $prevUrl
 * @var string|null $nextUrl
 */
$action = url('admin/support.php');
$priorityChip = ['alta' => 'chip--danger', 'media' => 'chip--warning', 'baja' => 'chip--muted'];
?>
<?php if ($account === null): ?>
    <div class="alert alert--error" role="alert">
        <?= icon('triangle-alert') ?>
        <p><?= e(t('No existe una cuenta activa @{username}. IX no puede responder ni dar la bienvenida hasta que exista.', ['username' => $username])) ?></p>
    </div>
<?php elseif (!$configured): ?>
    <div class="alert alert--info" role="status">
        <?= icon('info') ?>
        <p>
            <?= e(t('IX aún no tiene la clave de la API de Gemini (Google AI Studio). Mientras tanto avisa a quien escribe que el equipo revisará su mensaje, registra cada consulta aquí y envía bienvenidas con mensajes preparados.')) ?>
        </p>
    </div>
<?php endif; ?>

<details class="panel admin-settings"<?= $canConfigure && !$ix['replies'] ? ' open' : '' ?>>
    <summary class="panel__head">
        <h2><?= icon('sparkles') ?> <?= e(t('Configuración de IX')) ?></h2>
        <span class="<?= cx('chip', $ix['replies'] && $configured ? 'chip--success' : 'chip--warning') ?>">
            <?= !$ix['replies'] ? e(t('En pausa')) : ($configured ? e(t('Respondiendo con IA')) : e(t('Sin clave: avisos automáticos'))) ?>
        </span>
    </summary>
    <div class="admin-settings__body">
        <p class="content-row__muted">
            <?= e(t('Clave de Gemini:')) ?> <strong><?= $keyHint !== null ? e(t('configurada ({hint})', ['hint' => $keyHint])) : e(t('sin configurar')) ?></strong>
            · <?= t('se cambia solo en {file} del servidor ({key}), nunca desde el panel.', ['file' => '<code>config/local.php</code>', 'key' => '<code>app.ix.api_key</code>']) ?>
            <br>
            <?= e(t('Últimas 24 horas:')) ?> <?= tn((int) $activity['ix_today'], '{count} mensaje de IX', '{count} mensajes de IX', ['count' => '<strong>' . (int) $activity['ix_today'] . '</strong>']) ?> ·
            <?= tn((int) $activity['people_today'], '{count} persona escribió', '{count} personas escribieron', ['count' => '<strong>' . (int) $activity['people_today'] . '</strong>']) ?> ·
            <?= tn((int) $activity['chats'], '{count} chat con @{username} en total.', '{count} chats con @{username} en total.', ['count' => '<strong>' . (int) $activity['chats'] . '</strong>', 'username' => e($username)]) ?>
            <br>
            <?= e(t('Límites: {perUser} respuestas por hora a cada persona y {daily} al día en total.', ['perUser' => (int) $ix['perUser'], 'daily' => number_format($ix['daily'], 0, ',', '.')])) ?>
        </p>

        <?php if ($canConfigure): ?>
            <form method="post" action="<?= e($action) ?>">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="settings">
                <fieldset<?= $isPreview ? ' disabled' : '' ?>>
                    <legend class="sr-only"><?= e(t('Ajustes de IX')) ?></legend>
                    <div class="admin-setting">
                        <div>
                            <p class="admin-setting__title"><?= e(t('Respuestas automáticas')) ?></p>
                            <p class="admin-setting__text"><?= e(t('IX responde con IA a quien escribe a @{username}. En pausa, avisa una vez por hora que el equipo revisará el mensaje y registra la solicitud.', ['username' => $username])) ?></p>
                        </div>
                        <label class="switch">
                            <input type="checkbox" role="switch" name="ix_replies" value="1"<?= $ix['replies'] ? ' checked' : '' ?>>
                            <span class="switch__track" aria-hidden="true"></span>
                            <span class="sr-only"><?= e(t('Respuestas automáticas')) ?></span>
                        </label>
                    </div>
                    <div class="admin-setting">
                        <div>
                            <p class="admin-setting__title"><?= e(t('Bienvenida a cuentas nuevas')) ?></p>
                            <p class="admin-setting__text"><?= e(t('IX escribe un mensaje de bienvenida distinto a cada persona que crea su cuenta.')) ?></p>
                        </div>
                        <label class="switch">
                            <input type="checkbox" role="switch" name="ix_welcome" value="1"<?= $ix['welcome'] ? ' checked' : '' ?>>
                            <span class="switch__track" aria-hidden="true"></span>
                            <span class="sr-only"><?= e(t('Bienvenida a cuentas nuevas')) ?></span>
                        </label>
                    </div>
                    <div class="field admin-setting admin-setting--stack">
                        <label class="admin-setting__title" for="ix-model"><?= e(t('Modelo de Gemini')) ?></label>
                        <div class="select-wrap">
                            <select class="select" id="ix-model" name="ix_model">
                                <?php foreach (Ix::MODELS as $key => $label): ?>
                                    <option value="<?= e($key) ?>"<?= $ix['model'] === $key ? ' selected' : '' ?>><?= e(t($label)) ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>
                    <div class="field admin-setting admin-setting--stack">
                        <label class="admin-setting__title" for="ix-pause"><?= e(t('Pausa cuando responde el equipo (horas)')) ?></label>
                        <p class="admin-setting__text"><?= e(t('Si alguien del equipo escribe en un chat (desde aquí o desde @{username}), IX no responde en ese chat durante este tiempo. 0 = nunca se pausa.', ['username' => $username])) ?></p>
                        <input class="input" id="ix-pause" name="ix_pause_hours" type="number" min="0" max="72" step="1" value="<?= (int) $ix['pause'] ?>">
                    </div>
                    <div class="field admin-setting admin-setting--stack">
                        <label class="admin-setting__title" for="ix-instructions"><?= e(t('Indicaciones del equipo para IX')) ?></label>
                        <p class="admin-setting__text"><?= e(t('Novedades o avisos que IX debe tener en cuenta al responder (fallas conocidas, cambios recientes, campañas). No pueden cambiar sus reglas de seguridad.')) ?></p>
                        <textarea class="input" id="ix-instructions" name="ix_instructions" rows="4" maxlength="<?= Ix::MAX_INSTRUCTIONS ?>"
                            placeholder="<?= e(t('Ej.: Hoy hay demoras al subir videos largos; ya lo estamos solucionando. Pide disculpas y sugiere intentarlo más tarde.')) ?>"><?= e($ix['instructions']) ?></textarea>
                    </div>
                </fieldset>
                <footer class="admin-settings__footer">
                    <button type="submit" class="btn btn--primary"<?= $isPreview ? ' disabled' : '' ?>><?= icon('check') ?> <?= e(t('Guardar configuración')) ?></button>
                </footer>
            </form>
            <form method="post" action="<?= e($action) ?>" class="admin-settings__footer">
                <?= csrf_field() ?>
                <input type="hidden" name="action" value="test">
                <button type="submit" class="btn btn--secondary"<?= $isPreview || !$configured ? ' disabled' : '' ?>><?= icon('sparkles') ?> <?= e(t('Probar conexión con Gemini')) ?></button>
            </form>
        <?php else: ?>
            <p class="content-row__muted"><?= e(t('Solo los administradores pueden cambiar la configuración de IX.')) ?></p>
        <?php endif; ?>
    </div>
</details>

<nav class="admin-tabs" aria-label="<?= e(t('Estado de las solicitudes')) ?>">
    <?php foreach (Support::STATUSES as $key => $label): ?>
        <a class="<?= cx('admin-tabs__item', ['is-active' => $status === $key]) ?>" href="<?= e(url('admin/support.php', ['status' => $key === 'open' ? null : $key, 'category' => $category])) ?>"
            <?= $status === $key ? 'aria-current="page"' : '' ?>>
            <?= e(t($label)) ?>
            <?php if (($counts[$key] ?? 0) > 0): ?><span class="admin-tabs__count"><?= (int) $counts[$key] ?></span><?php endif; ?>
        </a>
    <?php endforeach; ?>
</nav>

<form class="admin-search" method="get" action="<?= e($action) ?>">
    <?php if ($status !== 'open'): ?><input type="hidden" name="status" value="<?= e($status) ?>"><?php endif; ?>
    <div class="select-wrap">
        <select class="select" name="category" aria-label="<?= e(t('Categoría')) ?>">
            <option value=""><?= e(t('Todas las categorías')) ?></option>
            <?php foreach (Support::CATEGORIES as $key => $label): ?>
                <option value="<?= e($key) ?>"<?= $category === $key ? ' selected' : '' ?>><?= e(t($label)) ?></option>
            <?php endforeach; ?>
        </select>
    </div>
    <button type="submit" class="btn btn--secondary"><?= e(t('Filtrar')) ?></button>
</form>

<p class="content-row__muted">
    <?= e(t('IX responde en el chat de @{username} y registra aquí los errores, sugerencias, reportes, quejas, reclamos, peticiones y lo que necesita a una persona.', ['username' => $username])) ?>
    <?= e(t('Si respondes desde aquí (o desde la cuenta de soporte), IX se pausa en ese chat durante unas horas.')) ?>
</p>

<section class="panel">
    <?php if ($tickets === []): ?>
        <div class="panel__empty">
            <?= icon('sparkles') ?>
            <p><?= $status === 'open' ? e(t('No hay solicitudes abiertas.')) : e(t('No hay solicitudes cerradas.')) ?></p>
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
                            <span class="chip chip--brand"><?= e(t(Support::CATEGORIES[$t['category']] ?? $t['category'])) ?></span>
                            <span class="chip <?= e($priorityChip[$t['priority']] ?? 'chip--muted') ?>"><?= e(t('Prioridad ' . mb_strtolower(Support::PRIORITIES[$t['priority']] ?? $t['priority']))) ?></span>
                            <?php if ((int) $t['needs_human'] === 1): ?><span class="chip chip--warning"><?= icon('user') ?> <?= e(t('Necesita a una persona')) ?></span><?php endif; ?>
                            <?php if ($t['user_status'] !== 'active'): ?><span class="chip chip--danger"><?= e(t('Cuenta no activa')) ?></span><?php endif; ?>
                        </p>
                        <?php if ($t['summary'] !== ''): ?>
                            <p class="content-row__text"><strong><?= e($t['summary']) ?></strong></p>
                        <?php endif; ?>
                        <?php if ($t['excerpt'] !== ''): ?>
                            <p class="content-row__text">«<?= e($t['excerpt']) ?>»</p>
                        <?php endif; ?>
                        <p class="content-row__muted">
                            <?= e(t('Abierta')) ?> <?= time_tag((string) $t['created_at']) ?> · <?= e(t('último mensaje')) ?> <?= time_tag((string) $t['updated_at']) ?>
                            <?php if ($t['closed_at'] !== null): ?>
                                · <?= e(t('cerrada')) ?> <?= time_tag((string) $t['closed_at']) ?><?= $t['closer_username'] !== null ? ' ' . e(t('por @{username}', ['username' => $t['closer_username']])) : '' ?>
                            <?php endif; ?>
                        </p>
                    </div>
                    <div class="content-row__actions">
                        <?php if ($account !== null && $t['user_status'] === 'active'): ?>
                            <details class="admin-menu">
                                <summary class="btn btn--primary btn--sm"><?= icon('send') ?> <?= e(t('Responder')) ?></summary>
                                <div class="admin-menu__panel">
                                    <form method="post" action="<?= e($action) ?>">
                                        <?= csrf_field() ?>
                                        <input type="hidden" name="id" value="<?= $tid ?>">
                                        <input type="hidden" name="action" value="reply">
                                        <label class="field__label" for="reply-<?= $tid ?>"><?= e(t('Mensaje como @{username}', ['username' => $account['username']])) ?></label>
                                        <textarea class="input" id="reply-<?= $tid ?>" name="reply" rows="4" required minlength="2" maxlength="2000"></textarea>
                                        <button type="submit" class="btn btn--primary btn--sm btn--block"><?= icon('send') ?> <?= e(t('Enviar')) ?></button>
                                    </form>
                                </div>
                            </details>
                        <?php endif; ?>
                        <form method="post" action="<?= e($action) ?>">
                            <?= csrf_field() ?>
                            <input type="hidden" name="id" value="<?= $tid ?>">
                            <?php if ($t['status'] === 'open'): ?>
                                <input type="hidden" name="action" value="close">
                                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('circle-check') ?> <?= e(t('Cerrar')) ?></button>
                            <?php else: ?>
                                <input type="hidden" name="action" value="reopen">
                                <button type="submit" class="btn btn--ghost btn--sm"><?= icon('rotate-ccw') ?> <?= e(t('Reabrir')) ?></button>
                            <?php endif; ?>
                        </form>
                    </div>
                </li>
            <?php endforeach; ?>
        </ul>
    <?php endif; ?>
</section>

<?php View::partial('admin-pager', ['prevUrl' => $prevUrl, 'nextUrl' => $nextUrl]); ?>
