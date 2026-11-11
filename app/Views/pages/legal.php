<?php

use Trevix\Core\View;

/**
 * @var string $doc
 * @var array  $documents
 * @var array  $legal
 */
?>
<header class="lp-nav is-scrolled">
    <div class="container lp-nav__inner">
        <a class="lp-nav__brand" href="<?= e(url()) ?>" aria-label="<?= e(t('TREVIX, inicio')) ?>">
            <?php View::partial('logo', ['size' => 34, 'wordmark' => true]); ?>
        </a>
        <div class="lp-nav__actions lp-nav__actions--always">
            <a class="btn btn--ghost" href="<?= e(url('login.php')) ?>"><?= e(t('Iniciar sesión')) ?></a>
            <a class="btn btn--primary" href="<?= e(url('register.php')) ?>"><?= e(t('Crear cuenta')) ?></a>
        </div>
    </div>
</header>

<main id="main" class="legal container">
    <nav class="legal__tabs" aria-label="<?= e(t('Documentos legales')) ?>">
        <?php foreach ($documents as $key => $label): ?>
            <a class="<?= cx('legal__tab', ['is-active' => $doc === $key]) ?>" href="<?= e(url('legal.php', ['doc' => $key])) ?>"
                <?= $doc === $key ? 'aria-current="page"' : '' ?>><?= e(t($label)) ?></a>
        <?php endforeach; ?>
    </nav>

    <article class="legal__doc">
        <p class="legal__status"><?= icon('file-text') ?> <?= e(t('Vigente desde el {date}', ['date' => t($legal['updated'])])) ?></p>
        <h1><?= e(t($documents[$doc])) ?></h1>

        <?php View::partial((locale() === 'en' ? 'legal/en/' : 'legal/') . $doc, ['legal' => $legal]); ?>
    </article>
</main>

<footer class="lp-footer lp-footer--compact">
    <div class="container lp-footer__bottom">
        <p>© <?= date('Y') ?> TREVIX. <?= e(t('Todos los derechos reservados.')) ?></p>
        <a href="<?= e(url()) ?>"><?= e(t('Volver al inicio')) ?></a>
        <?php View::partial('lang-switch'); ?>
    </div>
</footer>
