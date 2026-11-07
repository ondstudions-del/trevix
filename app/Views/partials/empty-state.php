<?php
/**
 * @var string      $icon
 * @var string      $heading
 * @var string      $text
 * @var string|null $actionHref
 * @var string|null $actionLabel
 */
?>
<div class="empty-state">
    <span class="empty-state__icon"><?= icon($icon ?? 'inbox') ?></span>
    <h2 class="empty-state__title"><?= e($heading) ?></h2>
    <p class="empty-state__text"><?= e($text) ?></p>
    <?php if (!empty($actionHref) && !empty($actionLabel)): ?>
        <a class="btn btn--secondary btn--sm" href="<?= e($actionHref) ?>"><?= e($actionLabel) ?></a>
    <?php endif; ?>
</div>
