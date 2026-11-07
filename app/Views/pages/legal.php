<?php

use Trevix\Core\View;

/**
 * @var string $doc
 * @var array  $documents
 */
$updated = 'noviembre de 2026';
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
        <p class="legal__status"><?= icon('file-text') ?> Borrador · Última actualización: <?= e($updated) ?></p>
        <h1><?= e($documents[$doc]) ?></h1>

        <?php if ($doc === 'terminos'): ?>
            <p>Estos términos regulan el uso de TREVIX. Al crear una cuenta aceptas cumplirlos. Este documento es un borrador y debe ser revisado por asesoría legal antes del lanzamiento público.</p>
            <h2>1. Cuenta</h2>
            <p>Debes tener al menos 13 años, proporcionar información veraz y mantener la confidencialidad de tu contraseña. Eres responsable de la actividad realizada desde tu cuenta.</p>
            <h2>2. Contenido</h2>
            <p>Conservas los derechos sobre lo que publicas. Nos concedes una licencia limitada para alojarlo, mostrarlo y distribuirlo dentro de la plataforma según la configuración de privacidad que elijas.</p>
            <h2>3. Conducta</h2>
            <p>No está permitido publicar contenido ilegal, acosar, suplantar identidades, difundir spam ni intentar vulnerar la seguridad de la plataforma. Podemos suspender cuentas que incumplan estas normas.</p>
            <h2>4. Moderación</h2>
            <p>Cualquier usuario puede reportar contenido. Nuestro equipo de moderación revisa los reportes y puede eliminar contenido o limitar cuentas.</p>
        <?php elseif ($doc === 'privacidad'): ?>
            <p>Explicamos qué datos tratamos, para qué y qué control tienes sobre ellos. Este documento es un borrador sujeto a revisión legal.</p>
            <h2>1. Datos que recopilamos</h2>
            <p>Datos de registro (nombre, usuario, correo y fecha de nacimiento), el contenido que publicas, tus interacciones y datos técnicos mínimos como la dirección IP para seguridad.</p>
            <h2>2. Uso de los datos</h2>
            <p>Para prestar el servicio, personalizar tu feed, mantener la seguridad (por ejemplo, limitar intentos de acceso) y comunicarnos contigo sobre tu cuenta.</p>
            <h2>3. Tus derechos</h2>
            <p>Puedes acceder, corregir o eliminar tus datos, cambiar tu perfil a privado y solicitar la eliminación de tu cuenta desde la configuración.</p>
            <h2>4. Seguridad</h2>
            <p>Las contraseñas se almacenan con funciones de hash seguras y nunca en texto plano. Aplicamos medidas técnicas para proteger tu información.</p>
        <?php else: ?>
            <p>TREVIX utiliza solo las cookies estrictamente necesarias para funcionar.</p>
            <h2>1. Cookie de sesión</h2>
            <p><code>trevix_session</code> mantiene tu sesión iniciada de forma segura. Es una cookie HttpOnly que no es accesible desde JavaScript y se elimina al cerrar sesión.</p>
            <h2>2. Almacenamiento local</h2>
            <p>Guardamos en tu navegador preferencias de accesibilidad (como reducir animaciones o el tamaño del texto). No se envían a nuestros servidores.</p>
            <h2>3. Sin rastreo de terceros</h2>
            <p>No usamos cookies publicitarias ni de seguimiento de terceros.</p>
        <?php endif; ?>
    </article>
</main>

<footer class="lp-footer lp-footer--compact">
    <div class="container lp-footer__bottom">
        <p>© <?= date('Y') ?> TREVIX. Todos los derechos reservados.</p>
        <a href="<?= e(url()) ?>">Volver al inicio</a>
    </div>
</footer>
