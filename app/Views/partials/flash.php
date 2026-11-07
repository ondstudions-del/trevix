<?php

use Trevix\Core\Session;

$icons = ['success' => 'circle-check', 'error' => 'triangle-alert', 'info' => 'info', 'warning' => 'triangle-alert'];
foreach (Session::pullFlash() as $flash):
    $type = array_key_exists($flash['type'], $icons) ? $flash['type'] : 'info';
?>
    <div class="alert alert--<?= e($type) ?>" role="<?= $type === 'error' ? 'alert' : 'status' ?>">
        <?= icon($icons[$type]) ?>
        <p><?= e($flash['message']) ?></p>
    </div>
<?php endforeach; ?>
