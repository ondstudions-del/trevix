<?php

use Trevix\Core\View;

/** @var string $content */
?>
<!doctype html>
<html lang="es">
<head>
    <?php View::partial('head', ['title' => $title ?? 'TREVIX', 'styles' => ['auth']]); ?>
</head>
<body class="auth-body">
    <a class="skip-link" href="#main">Saltar al contenido</a>
    <div class="auth">
        <aside class="auth__visual" aria-hidden="true">
            <span class="orb orb--purple"></span>
            <span class="orb orb--blue"></span>
            <span class="auth__grid"></span>
            <div class="auth__visual-inner">
                <a class="auth__visual-brand" href="<?= e(url()) ?>" tabindex="-1">
                    <?php View::partial('logo', ['size' => 44, 'wordmark' => true]); ?>
                </a>
                <div class="auth__pitch">
                    <h2>Conecta. <span class="text-gradient">Comparte.</span> Descubre.</h2>
                    <p>Fotos, historias, hilos y comunidades en un solo lugar diseñado para ti.</p>
                </div>
                <div class="auth__cards">
                    <div class="glass-card glass-card--a">
                        <span class="glass-card__icon glass-card__icon--like"><?= icon('heart') ?></span>
                        <span><strong>Luciana</strong> y 128 personas más reaccionaron</span>
                    </div>
                    <div class="glass-card glass-card--b">
                        <span class="glass-card__icon glass-card__icon--tag"><?= icon('hash') ?></span>
                        <span><strong>#Fotografía</strong> es tendencia</span>
                    </div>
                    <div class="glass-card glass-card--c">
                        <span class="glass-card__icon glass-card__icon--group"><?= icon('users-round') ?></span>
                        <span>Únete a <strong>comunidades</strong> que te inspiran</span>
                    </div>
                </div>
            </div>
        </aside>

        <main class="auth__main" id="main" tabindex="-1">
            <a class="auth__brand-mobile" href="<?= e(url()) ?>" aria-label="TREVIX, volver al inicio">
                <?php View::partial('logo', ['size' => 36, 'wordmark' => true]); ?>
            </a>
            <div class="auth__content">
                <?php View::partial('flash'); ?>
                <?= $content ?>
            </div>
            <nav class="auth__legal" aria-label="Enlaces legales">
                <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>">Términos</a>
                <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>">Privacidad</a>
                <a href="<?= e(url('legal.php', ['doc' => 'cookies'])) ?>">Cookies</a>
                <span>© <?= date('Y') ?> TREVIX</span>
            </nav>
        </main>
    </div>
    <script src="<?= e(asset('js/auth.js')) ?>" defer></script>
</body>
</html>
