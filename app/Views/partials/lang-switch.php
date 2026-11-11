<?php

use Trevix\Core\Lang;

/**
 * Selector de idioma: un botón por idioma (el actual queda marcado).
 *
 * @var string|null $class
 */
?>
<form class="<?= e(cx('lang-switch', $class ?? '')) ?>" method="post" action="<?= e(url('lang.php')) ?>">
    <?= csrf_field() ?>
    <?= icon('globe') ?>
    <span class="sr-only"><?= e(t('Idioma')) ?></span>
    <?php foreach (Lang::SUPPORTED as $code => $label): ?>
        <button type="submit" name="locale" value="<?= e($code) ?>" lang="<?= e($code) ?>"
            class="<?= e(cx('lang-switch__option', ['is-active' => locale() === $code])) ?>"<?= locale() === $code ? ' aria-current="true"' : '' ?>><?= e($label) ?></button>
    <?php endforeach; ?>
</form>
