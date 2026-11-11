<?php

use Trevix\Core\Auth;
use Trevix\Models\AppSetting;

/**
 * Aviso general configurado en el panel y, para el equipo, recordatorio del modo mantenimiento.
 *
 * @var array|null $viewer
 * @var bool       $isPreview
 */
if ($isPreview) {
    return;
}
$announcement = AppSetting::get('site_announcement');
$maintenance = AppSetting::flag('maintenance_mode') && Auth::hasRole('moderator');
?>
<?php if ($maintenance): ?>
    <div class="alert alert--warning site-notice" role="status">
        <?= icon('wrench') ?>
        <p><strong><?= e(t('Modo mantenimiento activo.')) ?></strong> <?= e(t('Solo el equipo puede usar TREVIX.')) ?>
            <?php if (Auth::hasRole('admin')): ?><a href="<?= e(url('admin/settings.php')) ?>"><?= e(t('Desactivarlo')) ?></a><?php endif; ?></p>
    </div>
<?php endif; ?>
<?php if ($announcement !== ''): ?>
    <div class="alert alert--info site-notice" role="status">
        <?= icon('megaphone') ?>
        <p><?= e($announcement) ?></p>
    </div>
<?php endif; ?>
