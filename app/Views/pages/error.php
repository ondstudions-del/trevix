<?php
/**
 * @var int         $code
 * @var string      $message
 * @var string|null $detail
 */
?>
<section class="auth-card auth-card--center">
    <p class="error-code text-gradient"><?= (int) $code ?></p>
    <h1><?= e($title ?? t('Error')) ?></h1>
    <p class="auth-card__lead"><?= e($message) ?></p>
    <?php if (!empty($detail)): ?>
        <pre class="error-detail"><?= e($detail) ?></pre>
    <?php endif; ?>
    <div class="auth-card__actions">
        <a class="btn btn--primary" href="<?= e(url()) ?>"><?= icon('house') ?> <?= e(t('Ir al inicio')) ?></a>
    </div>
</section>
