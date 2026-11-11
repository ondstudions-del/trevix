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
    <h2 class="empty-state__title"><?= e(t((string) $heading)) ?></h2>
    <p class="empty-state__text"><?= e(t((string) $text)) ?></p>
    <?php if (!empty($actionHref) && !empty($actionLabel)): ?>
        <a class="btn btn--secondary btn--sm" href="<?= e($actionHref) ?>"><?= e(t((string) $actionLabel)) ?></a>
    <?php endif; ?>
</div>
