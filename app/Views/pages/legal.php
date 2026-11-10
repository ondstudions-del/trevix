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
        <a class="lp-nav__brand" href="<?= e(url()) ?>" aria-label="TREVIX, inicio">
            <?php View::partial('logo', ['size' => 34, 'wordmark' => true]); ?>
        </a>
        <div class="lp-nav__actions lp-nav__actions--always">
            <a class="btn btn--ghost" href="<?= e(url('login.php')) ?>">Iniciar sesión</a>
            <a class="btn btn--primary" href="<?= e(url('register.php')) ?>">Crear cuenta</a>
        </div>
    </div>
</header>

<main id="main" class="legal container">
    <nav class="legal__tabs" aria-label="Documentos legales">
        <?php foreach ($documents as $key => $label): ?>
            <a class="<?= cx('legal__tab', ['is-active' => $doc === $key]) ?>" href="<?= e(url('legal.php', ['doc' => $key])) ?>"
                <?= $doc === $key ? 'aria-current="page"' : '' ?>><?= e($label) ?></a>
        <?php endforeach; ?>
    </nav>

    <article class="legal__doc">
        <p class="legal__status"><?= icon('file-text') ?> Vigente desde el <?= e($legal['updated']) ?></p>
        <h1><?= e($documents[$doc]) ?></h1>

        <?php View::partial('legal/' . $doc, ['legal' => $legal]); ?>
    </article>
</main>

<footer class="lp-footer lp-footer--compact">
    <div class="container lp-footer__bottom">
        <p>© <?= date('Y') ?> TREVIX. Todos los derechos reservados.</p>
        <a href="<?= e(url()) ?>">Volver al inicio</a>
    </div>
</footer>
