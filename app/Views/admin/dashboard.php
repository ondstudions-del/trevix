<?php

use Trevix\Core\View;

/**
 * @var array|null $stats
 * @var array      $reports  objetivos con reportes abiertos
 * @var array|null $audit    últimas acciones (solo administradores)
 */
$cards = [
    ['users', 'Usuarios', 'users', 'suspended_users', 'suspendidas'],
    ['file-text', 'Publicaciones', 'posts', 'hidden_posts', 'ocultas'],
    ['activity', 'Activos (24 h)', 'active_users', null, null],
    ['flag', 'Reportes pendientes', 'open_reports', 'reports_today', 'recibidos en 24 h'],
    ['music', 'Canciones por revisar', 'pending_songs', 'published_songs', 'en la biblioteca'],
];
$roles = [
    ['user', 'Usuario', 'Publica, comenta, sigue a otras personas y reporta contenido.'],
    ['shield', 'Moderador', 'Revisa reportes, oculta o elimina contenido y suspende cuentas de usuario hasta 30 días.'],
    ['shield-check', 'Administrador', 'Además gestiona roles, verificación, comunidades, la configuración y la auditoría.'],
];
?>
<section class="stat-grid" aria-label="Resumen">
    <?php foreach ($cards as [$iconName, $label, $key, $extraKey, $extraLabel]): ?>
        <article class="stat-card">
            <span class="stat-card__icon"><?= icon($iconName) ?></span>
            <p class="stat-card__label"><?= e($label) ?></p>
            <p class="stat-card__value"><?= $stats !== null ? e(number_format($stats[$key], 0, ',', '.')) : '—' ?></p>
            <p class="stat-card__hint">
                <?php if ($stats === null): ?>
                    Se calcula al conectar la base de datos
                <?php elseif ($extraKey !== null): ?>
                    <?= e(number_format($stats[$extraKey], 0, ',', '.')) ?> <?= e($extraLabel) ?>
                <?php else: ?>
                    Datos en tiempo real
                <?php endif; ?>
            </p>
        </article>
    <?php endforeach; ?>
</section>

<div class="admin-grid">
    <section class="panel" aria-labelledby="panel-reports">
        <header class="panel__head">
            <h2 id="panel-reports"><?= icon('flag') ?> Reportes pendientes</h2>
            <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/reports.php')) ?>">Ver todos <?= icon('arrow-right') ?></a>
        </header>
        <?php if ($reports === []): ?>
            <div class="panel__empty">
                <?= icon('inbox') ?>
                <p>No hay reportes pendientes de revisión.</p>
            </div>
        <?php else: ?>
            <ul class="report-list report-list--compact">
                <?php foreach ($reports as $target): ?>
                    <?php View::partial('admin-report-row', ['target' => $target]); ?>
                <?php endforeach; ?>
            </ul>
        <?php endif; ?>
    </section>

    <?php if ($audit !== null): ?>
        <section class="panel" aria-labelledby="panel-audit">
            <header class="panel__head">
                <h2 id="panel-audit"><?= icon('history') ?> Actividad del equipo</h2>
                <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/audit.php')) ?>">Auditoría <?= icon('arrow-right') ?></a>
            </header>
            <?php if ($audit === []): ?>
                <div class="panel__empty">
                    <?= icon('history') ?>
                    <p>Todavía no hay acciones registradas.</p>
                </div>
            <?php else: ?>
                <ul class="audit-list">
                    <?php foreach ($audit as $entry): ?>
                        <?php View::partial('admin-audit-entry', ['entry' => $entry]); ?>
                    <?php endforeach; ?>
                </ul>
            <?php endif; ?>
        </section>
    <?php else: ?>
        <section class="panel" aria-labelledby="panel-roles">
            <header class="panel__head">
                <h2 id="panel-roles"><?= icon('key-round') ?> Roles y permisos</h2>
            </header>
            <ul class="role-list">
                <?php foreach ($roles as [$iconName, $name, $text]): ?>
                    <li>
                        <span class="role-list__icon"><?= icon($iconName) ?></span>
                        <div>
                            <strong><?= e($name) ?></strong>
                            <p><?= e($text) ?></p>
                        </div>
                    </li>
                <?php endforeach; ?>
            </ul>
        </section>
    <?php endif; ?>
</div>
