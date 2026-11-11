<?php

use Trevix\Core\View;

/** @var string $previewUrl */
$features = [
    ['layers', t('Feed inteligente'), t('Cambia entre Para ti, Siguiendo, Amigos y Tendencias. Tú decides qué ves y en qué orden.'), 'wide'],
    ['messages-square', t('Hilos y debates'), t('Publica ideas, abre conversaciones y responde en hilos ordenados y fáciles de seguir.'), ''],
    ['clock', t('Historias de 24 horas'), t('Comparte momentos que desaparecen en un día, con fotos, videos o texto.'), ''],
    ['users-round', t('Comunidades'), t('Grupos públicos y privados alrededor de lo que te apasiona, con sus propios moderadores.'), ''],
    ['send', t('Mensajería privada'), t('Conversaciones uno a uno, rápidas y privadas, sin salir de la plataforma.'), ''],
    ['compass', t('Explorar y tendencias'), t('Descubre personas, hashtags y comunidades populares en tiempo real.'), 'wide'],
];
$benefits = [
    ['lock', t('Control total de tu privacidad'), t('Perfil público o privado, solicitudes de seguimiento y decisión sobre quién ve cada publicación.')],
    ['bell', t('Notificaciones relevantes'), t('Seguidores, me gusta, comentarios, respuestas y menciones, sin ruido innecesario.')],
    ['zap', t('Rápida y ligera'), t('Construida sin dependencias pesadas para cargar en segundos incluso con conexiones lentas.')],
    ['accessibility', t('Accesible para todos'), t('Navegación por teclado, contraste cuidado y opción para reducir animaciones.')],
    ['smartphone', t('Lista para cualquier pantalla'), t('Experiencia optimizada para móvil hoy; aplicaciones para Android e iOS en camino.')],
    ['shield-check', t('Moderación activa'), t('Reportes, revisión de contenido y roles de moderación para mantener la comunidad sana.')],
];
$topics = [t('Fotografía'), t('Tecnología'), t('DiseñoUI'), t('Viajes'), t('Música'), t('Ciencia'), t('Gaming'), t('Arte'), t('Deportes'), t('Cine'), t('Lectura'), t('Emprendimiento')];
?>
<header class="lp-nav" data-lp-nav>
    <div class="container lp-nav__inner">
        <a class="lp-nav__brand" href="<?= e(url()) ?>" aria-label="<?= e(t('TREVIX, inicio')) ?>">
            <?php View::partial('logo', ['size' => 36, 'wordmark' => true]); ?>
        </a>
        <nav class="lp-nav__menu" id="lp-menu" data-lp-menu aria-label="<?= e(t('Secciones')) ?>">
            <a href="#caracteristicas"><?= e(t('Características')) ?></a>
            <a href="#experiencia"><?= e(t('Experiencia')) ?></a>
            <a href="#beneficios"><?= e(t('Beneficios')) ?></a>
            <a href="#seguridad"><?= e(t('Seguridad')) ?></a>
            <div class="lp-nav__menu-cta">
                <a class="btn btn--glass btn--block" href="<?= e(url('login.php')) ?>"><?= e(t('Iniciar sesión')) ?></a>
                <a class="btn btn--primary btn--block" href="<?= e(url('register.php')) ?>"><?= e(t('Crear cuenta')) ?></a>
            </div>
        </nav>
        <div class="lp-nav__actions">
            <a class="btn btn--ghost" href="<?= e(url('login.php')) ?>"><?= e(t('Iniciar sesión')) ?></a>
            <a class="btn btn--primary" href="<?= e(url('register.php')) ?>"><?= e(t('Crear cuenta')) ?></a>
        </div>
        <button type="button" class="icon-btn lp-nav__toggle" data-lp-toggle aria-controls="lp-menu" aria-expanded="false" aria-label="<?= e(t('Abrir menú')) ?>">
            <?= icon('menu', 'lp-nav__icon-open') ?>
            <?= icon('x', 'lp-nav__icon-close') ?>
        </button>
    </div>
</header>

<main id="main">
    <section class="hero">
        <div class="hero__bg" aria-hidden="true">
            <span class="orb orb--purple"></span>
            <span class="orb orb--blue"></span>
            <span class="hero__grid"></span>
        </div>

        <div class="container hero__inner">
            <div class="hero__copy">
                <span class="pill" data-reveal><span class="pulse-dot"></span> <?= e(t('La red social de nueva generación')) ?></span>
                <h1 class="hero__title" data-reveal>
                    <span><?= e(t('Conecta.')) ?></span>
                    <span class="text-gradient"><?= e(t('Comparte.')) ?></span>
                    <span><?= e(t('Descubre.')) ?></span>
                </h1>
                <p class="hero__lead" data-reveal>
                    <?= e(t('TREVIX reúne fotos, videos, historias, hilos de conversación y comunidades en una sola experiencia.')) ?>
                    <?= e(t('Un espacio para expresarte a tu manera y encontrar a las personas que de verdad te importan.')) ?>
                </p>
                <div class="hero__cta" data-reveal>
                    <a class="btn btn--primary btn--lg" href="<?= e(url('register.php')) ?>"><?= e(t('Crear cuenta gratis')) ?> <?= icon('arrow-right') ?></a>
                    <a class="btn btn--glass btn--lg" href="<?= e($previewUrl) ?>"><?= icon('compass') ?> <?= e(t('Explorar la plataforma')) ?></a>
                </div>
                <ul class="hero__points" data-reveal>
                    <li><?= icon('check') ?> <?= e(t('Perfiles públicos o privados')) ?></li>
                    <li><?= icon('check') ?> <?= e(t('Historias de 24 horas')) ?></li>
                    <li><?= icon('check') ?> <?= e(t('Comunidades temáticas')) ?></li>
                </ul>
            </div>

            <div class="hero__visual" aria-hidden="true" data-reveal data-tilt>
                <div class="device">
                    <div class="device__notch"></div>
                    <div class="device__screen">
                        <div class="mk-top">
                            <?php View::partial('logo', ['size' => 22, 'wordmark' => true]); ?>
                            <span class="mk-top__icons"><?= icon('messages-square') ?><?= icon('send') ?></span>
                        </div>
                        <div class="mk-tabs"><span class="is-active"><?= e(t('Para ti')) ?></span><span><?= e(t('Siguiendo')) ?></span><span><?= e(t('Amigos')) ?></span></div>
                        <div class="mk-stories">
                            <?php foreach ([t('Tú') => 'valentina', 'Luciana' => 'luciana', 'Mateo' => 'mateo', 'Nico' => 'nico', 'Sofía' => 'sofia'] as $name => $seed): ?>
                                <span class="mk-story">
                                    <span class="mk-story__ring"><?= avatar(['username' => $seed, 'display_name' => $name], 'sm') ?></span>
                                    <span><?= e($name) ?></span>
                                </span>
                            <?php endforeach; ?>
                        </div>
                        <div class="mk-post">
                            <div class="mk-post__head">
                                <?= avatar(['username' => 'luciana.foto', 'display_name' => 'Luciana Paredes'], 'sm') ?>
                                <span><strong>Luciana Paredes</strong> <?= icon('badge-check', 'verified') ?><small>Patagonia · 38 min</small></span>
                            </div>
                            <img src="<?= e(url('assets/img/demo/aurora.svg')) ?>" alt="">
                            <div class="mk-post__actions">
                                <span class="is-liked"><?= icon('heart') ?> <?= e(t('4,8 mil')) ?></span>
                                <span><?= icon('message-circle') ?> 312</span>
                                <span><?= icon('repeat-2') ?> 140</span>
                                <span class="mk-post__save"><?= icon('bookmark') ?></span>
                            </div>
                            <p><?= e(t('Amanecer a 4.200 metros. Esperé tres noches por esta luz')) ?> <b><?= e(t('#Fotografía')) ?></b></p>
                        </div>
                        <div class="mk-nav">
                            <?= icon('house') ?><?= icon('compass') ?><span class="mk-nav__create"><?= icon('plus') ?></span><?= icon('bell') ?><?= icon('circle-user') ?>
                        </div>
                    </div>
                </div>

                <div class="float-card float-card--like">
                    <span class="float-card__icon float-card__icon--like"><?= icon('heart') ?></span>
                    <span><?= t('{name} le dio me gusta a tu foto', ['name' => '<strong>' . e('Mateo') . '</strong>']) ?></span>
                </div>
                <div class="float-card float-card--trend">
                    <span class="float-card__icon float-card__icon--trend"><?= icon('trending-up') ?></span>
                    <span><strong><?= e(t('#DiseñoUI')) ?></strong><small><?= e(t('8,7 mil publicaciones')) ?></small></span>
                </div>
                <div class="float-card float-card--msg">
                    <?= avatar(['username' => 'nico.design', 'display_name' => 'Nicolás Vega'], 'sm') ?>
                    <span><strong>Nicolás</strong><small><?= e(t('¿Vamos al evento de la comunidad?')) ?></small></span>
                </div>
            </div>
        </div>
    </section>

    <section class="marquee" aria-label="<?= e(t('Temas populares en TREVIX')) ?>">
        <div class="marquee__track">
            <?php for ($copy = 0; $copy < 2; $copy++): ?>
                <ul class="marquee__list" <?= $copy === 1 ? 'aria-hidden="true"' : '' ?>>
                    <?php foreach ($topics as $topic): ?>
                        <li><?= icon('hash') ?><?= e($topic) ?></li>
                    <?php endforeach; ?>
                </ul>
            <?php endfor; ?>
        </div>
    </section>

    <section class="section" id="caracteristicas">
        <div class="container">
            <header class="section__head" data-reveal>
                <span class="eyebrow"><?= e(t('Características')) ?></span>
                <h2 class="section__title"><?= e(t('Todo lo que te gusta de una red social,')) ?> <span class="text-gradient"><?= e(t('en un solo lugar')) ?></span></h2>
                <p class="section__lead"><?= e(t('Lo visual de una galería, lo conversacional de un foro y lo cercano de un grupo de amigos, con una identidad propia.')) ?></p>
            </header>

            <div class="bento">
                <?php foreach ($features as $i => [$iconName, $heading, $text, $variant]): ?>
                    <article class="<?= cx('feature', ['feature--wide' => $variant === 'wide']) ?>" data-reveal>
                        <span class="feature__icon"><?= icon($iconName) ?></span>
                        <h3 class="feature__title"><?= e($heading) ?></h3>
                        <p class="feature__text"><?= e($text) ?></p>
                        <?php if ($i === 0): ?>
                            <div class="feature__demo feature__demo--tabs" aria-hidden="true">
                                <span class="is-active"><?= e(t('Para ti')) ?></span><span><?= e(t('Siguiendo')) ?></span><span><?= e(t('Amigos')) ?></span><span><?= e(t('Tendencias')) ?></span>
                            </div>
                        <?php elseif ($i === 5): ?>
                            <ul class="feature__demo feature__demo--trends" aria-hidden="true">
                                <li><span><?= e(t('#IA')) ?></span><small><?= e(t('95,1 mil')) ?></small></li>
                                <li><span><?= e(t('#Fotografía')) ?></span><small><?= e(t('48,2 mil')) ?></small></li>
                                <li><span><?= e(t('#Viajes')) ?></span><small><?= e(t('31,4 mil')) ?></small></li>
                            </ul>
                        <?php endif; ?>
                    </article>
                <?php endforeach; ?>
            </div>
        </div>
    </section>

    <section class="section section--alt" id="experiencia">
        <div class="container">
            <header class="section__head" data-reveal>
                <span class="eyebrow"><?= e(t('Experiencia híbrida')) ?></span>
                <h2 class="section__title"><?= e(t('Una red,')) ?> <span class="text-gradient"><?= e(t('dos formas de expresarte')) ?></span></h2>
                <p class="section__lead"><?= e(t('Muestra tu mundo con imágenes y video, o participa en conversaciones con ideas y opiniones. En TREVIX conviven ambas.')) ?></p>
            </header>

            <div class="split">
                <article class="split__card" data-reveal>
                    <span class="feature__icon"><?= icon('image') ?></span>
                    <h3><?= e(t('Feed visual')) ?></h3>
                    <p><?= e(t('Fotografías, videos, publicaciones con varias imágenes e historias que duran 24 horas.')) ?></p>
                    <div class="split__gallery" aria-hidden="true">
                        <img src="<?= e(url('assets/img/demo/peaks.svg')) ?>" alt="" loading="lazy">
                        <img src="<?= e(url('assets/img/demo/orbs.svg')) ?>" alt="" loading="lazy">
                        <img src="<?= e(url('assets/img/demo/city.svg')) ?>" alt="" loading="lazy">
                    </div>
                </article>
                <article class="split__card" data-reveal>
                    <span class="feature__icon"><?= icon('quote') ?></span>
                    <h3><?= e(t('Feed conversacional')) ?></h3>
                    <p><?= e(t('Publicaciones de texto, debates y respuestas encadenadas para ideas que merecen conversación.')) ?></p>
                    <div class="split__thread" aria-hidden="true">
                        <div class="mini-thread">
                            <?= avatar(['username' => 'camila.lab', 'display_name' => 'Camila Torres'], 'sm') ?>
                            <div><strong>Camila Torres</strong><p><?= e(t('¿La IA en el aula ayuda a aprender o solo a entregar más rápido?')) ?></p></div>
                        </div>
                        <div class="mini-thread mini-thread--reply">
                            <?= avatar(['username' => 'isa.reads', 'display_name' => 'Isabella Gómez'], 'sm') ?>
                            <div><strong>Isabella Gómez</strong><p><?= e(t('Me ayuda cuando la uso para preguntar, no para copiar.')) ?></p></div>
                        </div>
                    </div>
                </article>
            </div>
        </div>
    </section>

    <section class="section" id="beneficios">
        <div class="container">
            <header class="section__head" data-reveal>
                <span class="eyebrow"><?= e(t('Beneficios')) ?></span>
                <h2 class="section__title"><?= e(t('Diseñada alrededor de')) ?> <span class="text-gradient"><?= e(t('las personas')) ?></span></h2>
                <p class="section__lead"><?= e(t('Cada decisión de TREVIX prioriza tu experiencia, tu tiempo y tu tranquilidad.')) ?></p>
            </header>
            <div class="benefits">
                <?php foreach ($benefits as [$iconName, $heading, $text]): ?>
                    <article class="benefit" data-reveal>
                        <span class="benefit__icon"><?= icon($iconName) ?></span>
                        <div>
                            <h3><?= e($heading) ?></h3>
                            <p><?= e($text) ?></p>
                        </div>
                    </article>
                <?php endforeach; ?>
            </div>
        </div>
    </section>

    <section class="section" id="seguridad">
        <div class="container security">
            <div class="security__copy" data-reveal>
                <span class="eyebrow"><?= e(t('Seguridad')) ?></span>
                <h2 class="section__title"><?= e(t('Tu seguridad')) ?> <span class="text-gradient"><?= e(t('no es opcional')) ?></span></h2>
                <p class="section__lead"><?= e(t('TREVIX se construye con seguridad desde la base, no como un añadido posterior.')) ?></p>
                <ul class="check-list">
                    <li><?= icon('circle-check') ?> <?= e(t('Contraseñas protegidas con hash moderno, nunca guardadas en texto plano.')) ?></li>
                    <li><?= icon('circle-check') ?> <?= e(t('Protección contra falsificación de solicitudes y ataques de inyección.')) ?></li>
                    <li><?= icon('circle-check') ?> <?= e(t('Límites de intentos de acceso para frenar ataques automatizados.')) ?></li>
                    <li><?= icon('circle-check') ?> <?= e(t('Verificación de archivos subidos por tipo, extensión y tamaño.')) ?></li>
                </ul>
            </div>
            <div class="security__visual" aria-hidden="true" data-reveal>
                <div class="shield">
                    <span class="shield__ring shield__ring--1"></span>
                    <span class="shield__ring shield__ring--2"></span>
                    <span class="shield__core"><?= icon('shield-check') ?></span>
                </div>
                <div class="security__chips">
                    <span><?= icon('lock-keyhole') ?> <?= e(t('Sesiones seguras')) ?></span>
                    <span><?= icon('key-round') ?> <?= e(t('Cifrado de contraseñas')) ?></span>
                    <span><?= icon('eye-off') ?> <?= e(t('Perfiles privados')) ?></span>
                </div>
            </div>
        </div>
    </section>

    <section class="section">
        <div class="container">
            <div class="cta-band" data-reveal>
                <span class="cta-band__glow" aria-hidden="true"></span>
                <?php View::partial('logo', ['size' => 64, 'wordmark' => false]); ?>
                <h2><?= e(t('Tu espacio te está esperando')) ?></h2>
                <p><?= e(t('Crea tu cuenta en segundos y empieza a conectar con personas que comparten lo que te apasiona.')) ?></p>
                <div class="cta-band__actions">
                    <a class="btn btn--light btn--lg" href="<?= e(url('register.php')) ?>"><?= e(t('Crear cuenta gratis')) ?></a>
                    <a class="btn btn--glass btn--lg" href="<?= e(url('login.php')) ?>"><?= e(t('Ya tengo cuenta')) ?></a>
                </div>
            </div>
        </div>
    </section>
</main>

<footer class="lp-footer">
    <div class="container lp-footer__grid">
        <div class="lp-footer__brand">
            <?php View::partial('logo', ['size' => 34, 'wordmark' => true]); ?>
            <p><?= e(t('Conecta. Comparte. Descubre. La red social que une lo visual y lo conversacional.')) ?></p>
        </div>
        <nav aria-labelledby="ft-product">
            <h2 id="ft-product"><?= e(t('Producto')) ?></h2>
            <a href="#caracteristicas"><?= e(t('Características')) ?></a>
            <a href="#experiencia"><?= e(t('Experiencia')) ?></a>
            <a href="#beneficios"><?= e(t('Beneficios')) ?></a>
        </nav>
        <nav aria-labelledby="ft-account">
            <h2 id="ft-account"><?= e(t('Cuenta')) ?></h2>
            <a href="<?= e(url('login.php')) ?>"><?= e(t('Iniciar sesión')) ?></a>
            <a href="<?= e(url('register.php')) ?>"><?= e(t('Crear cuenta')) ?></a>
            <a href="<?= e(url('forgot-password.php')) ?>"><?= e(t('Recuperar contraseña')) ?></a>
        </nav>
        <nav aria-labelledby="ft-legal">
            <h2 id="ft-legal"><?= e(t('Legal')) ?></h2>
            <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>"><?= e(t('Términos y condiciones')) ?></a>
            <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>"><?= e(t('Política de privacidad')) ?></a>
            <a href="<?= e(url('legal.php', ['doc' => 'cookies'])) ?>"><?= e(t('Política de cookies')) ?></a>
            <a href="<?= e(url('legal.php', ['doc' => 'reembolsos'])) ?>"><?= e(t('Política de reembolsos')) ?></a>
        </nav>
    </div>
    <div class="container lp-footer__bottom">
        <p>© <?= date('Y') ?> <?= e(t('TREVIX. Todos los derechos reservados.')) ?></p>
        <p><?= e(t('Hecho para conectar personas.')) ?></p>
        <?php View::partial('lang-switch'); ?>
    </div>
</footer>
