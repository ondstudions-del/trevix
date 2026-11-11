<?php

use Trevix\Core\View;

/** @var string $content */
?>
<!doctype html>
<html lang="<?= e(locale()) ?>">
<head>
    <?php View::partial('head', ['title' => $title ?? 'TREVIX', 'styles' => ['auth']]); ?>
</head>
<body class="auth-body">
    <a class="skip-link" href="#main"><?= e(t('Saltar al contenido')) ?></a>
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
                    <h2><?= e(t('Conecta.')) ?> <span class="text-gradient"><?= e(t('Comparte.')) ?></span> <?= e(t('Descubre.')) ?></h2>
                    <p><?= e(t('Fotos, historias, hilos y comunidades en un solo lugar diseñado para ti.')) ?></p>
                </div>
                <div class="auth__cards">
                    <div class="glass-card glass-card--a">
                        <span class="glass-card__icon glass-card__icon--like"><?= icon('heart') ?></span>
                        <span><?= t('{name} y 128 personas más reaccionaron', ['name' => '<strong>' . e('Luciana') . '</strong>']) ?></span>
                    </div>
                    <div class="glass-card glass-card--b">
                        <span class="glass-card__icon glass-card__icon--tag"><?= icon('hash') ?></span>
                        <span><?= t('{tag} es tendencia', ['tag' => '<strong>' . e(t('#Fotografía')) . '</strong>']) ?></span>
                    </div>
                    <div class="glass-card glass-card--c">
                        <span class="glass-card__icon glass-card__icon--group"><?= icon('users-round') ?></span>
                        <span><?= t('Únete a {communities} que te inspiran', ['communities' => '<strong>' . e(t('comunidades')) . '</strong>']) ?></span>
                    </div>
                </div>
            </div>
        </aside>

        <main class="auth__main" id="main" tabindex="-1">
            <a class="auth__brand-mobile" href="<?= e(url()) ?>" aria-label="<?= e(t('TREVIX, volver al inicio')) ?>">
                <?php View::partial('logo', ['size' => 36, 'wordmark' => true]); ?>
            </a>
            <div class="auth__content">
                <?php View::partial('flash'); ?>
                <?= $content ?>
            </div>
            <nav class="auth__legal" aria-label="<?= e(t('Enlaces legales')) ?>">
                <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>"><?= e(t('Términos')) ?></a>
                <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>"><?= e(t('Privacidad')) ?></a>
                <a href="<?= e(url('legal.php', ['doc' => 'cookies'])) ?>"><?= e(t('Cookies')) ?></a>
                <span>© <?= date('Y') ?> TREVIX</span>
            </nav>
            <?php View::partial('lang-switch', ['class' => 'auth__lang']); ?>
        </main>
    </div>
    <script src="<?= e(asset('js/auth.js')) ?>" defer></script>
</body>
</html>
