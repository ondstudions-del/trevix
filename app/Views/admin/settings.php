<?php
/**
 * @var array $settings  valores actuales de AppSetting
 * @var array $flags     clave => [label, hint]
 * @var int   $maxAnnouncement
 * @var bool  $isPreview
 */
?>
<form class="panel admin-settings" method="post" action="<?= e(url('admin/settings.php')) ?>">
    <?= csrf_field() ?>
    <header class="panel__head">
        <h2><?= icon('sliders-horizontal') ?> Funcionamiento de TREVIX</h2>
    </header>
    <fieldset class="admin-settings__body"<?= $isPreview ? ' disabled' : '' ?>>
        <legend class="sr-only">Opciones generales</legend>
        <?php foreach ($flags as $key => $flag): ?>
            <div class="admin-setting">
                <div>
                    <p class="admin-setting__title"><?= e($flag['label']) ?></p>
                    <p class="admin-setting__text"><?= e($flag['hint']) ?></p>
                </div>
                <label class="switch">
                    <input type="checkbox" role="switch" name="<?= e($key) ?>" value="1"<?= $settings[$key] === '1' ? ' checked' : '' ?>>
                    <span class="switch__track" aria-hidden="true"></span>
                    <span class="sr-only"><?= e($flag['label']) ?></span>
                </label>
            </div>
        <?php endforeach; ?>

        <div class="field admin-setting admin-setting--stack">
            <label class="admin-setting__title" for="site-announcement"><?= icon('megaphone') ?> Aviso para todos</label>
            <p class="admin-setting__text">Se muestra arriba en todas las páginas de la aplicación. Déjalo vacío para quitarlo.</p>
            <input class="input" id="site-announcement" name="site_announcement" maxlength="<?= $maxAnnouncement ?>"
                value="<?= e($settings['site_announcement']) ?>" placeholder="Ej.: Esta noche haremos tareas de mantenimiento de 23:00 a 23:30.">
        </div>
    </fieldset>
    <footer class="admin-settings__footer">
        <button type="submit" class="btn btn--primary"<?= $isPreview ? ' disabled' : '' ?>><?= icon('check') ?> Guardar cambios</button>
    </footer>
</form>
