<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
?>
<p>La web de TREVIX usa solo las cookies y el almacenamiento del navegador estrictamente necesarios para funcionar. No
    usamos cookies publicitarias, de analítica ni de seguimiento de terceros, por lo que no necesitas aceptarlas para
    navegar. Más detalles sobre tus datos en la
    <a href="<?= e(url('legal.php', ['doc' => 'privacidad'])) ?>">Política de privacidad</a>.</p>

<h2>1. Cookie de sesión</h2>
<p><code>trevix_session</code> mantiene tu sesión iniciada y protege los formularios contra peticiones falsificadas
    (CSRF). Es una cookie propia, <code>HttpOnly</code> (no accesible desde JavaScript), segura en conexiones HTTPS y
    con <code>SameSite=Lax</code>. Se borra al cerrar el navegador o al cerrar sesión, y la sesión vence tras 2 horas sin
    actividad.</p>

<h2>2. Almacenamiento local</h2>
<p>Guardamos en tu navegador, sin enviarlo a nuestros servidores:</p>
<ul>
    <li><code>trevix.prefs</code>: tus preferencias de visualización y accesibilidad, como reducir animaciones o el
        tamaño del texto.</li>
    <li><code>trevix.appOpen</code>: recuerda que cerraste el aviso para abrir TREVIX en la app.</li>
    <li><code>trevix.previewBanner</code>: recuerda que cerraste el aviso de la vista previa.</li>
</ul>

<h2>3. Contenido de terceros</h2>
<p>Los GIF y stickers se cargan desde los servidores de GIPHY, que pueden recibir tu dirección IP y datos técnicos del
    navegador según su propia política. TREVIX no instala cookies de terceros.</p>

<h2>4. Cómo controlarlas</h2>
<p>Puedes borrar las cookies y el almacenamiento local desde la configuración de tu navegador. Si borras la cookie de
    sesión tendrás que volver a iniciar sesión. Para cualquier duda escríbenos a
    <a href="mailto:<?= e($legal['email']) ?>"><?= e($legal['email']) ?></a>.</p>
