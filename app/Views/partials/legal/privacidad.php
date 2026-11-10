<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
$mail = '<a href="mailto:' . e($legal['email']) . '">' . e($legal['email']) . '</a>';
?>
<p>En TREVIX respetamos tu privacidad. Esta política explica qué datos personales tratamos cuando usas la web
    <a href="<?= e(url()) ?>"><?= e(parse_url(url(), PHP_URL_HOST) ?: 'trevix.ond-s.com') ?></a> y las apps de TREVIX para
    iPhone y Android, para qué los usamos, con quién los compartimos y cómo puedes ejercer tus derechos. Se rige por la
    Ley Estatutaria 1581 de 2012, el Decreto 1377 de 2013 (compilado en el Decreto 1074 de 2015) y demás normas de
    protección de datos personales de la República de <?= e($legal['country']) ?>.</p>

<nav class="legal__toc" aria-label="Contenido de la política">
    <ol>
        <li><a href="#responsable">Responsable del tratamiento</a></li>
        <li><a href="#datos">Datos que tratamos</a></li>
        <li><a href="#finalidades">Para qué los usamos</a></li>
        <li><a href="#autorizacion">Autorización</a></li>
        <li><a href="#mensajes">Mensajes, cifrado y visualización única</a></li>
        <li><a href="#visibilidad">Qué ven otras personas</a></li>
        <li><a href="#terceros">Con quién compartimos datos</a></li>
        <li><a href="#transferencias">Transferencias internacionales</a></li>
        <li><a href="#conservacion">Cuánto tiempo los conservamos</a></li>
        <li><a href="#derechos">Tus derechos</a></li>
        <li><a href="#procedimiento">Cómo ejercerlos</a></li>
        <li><a href="#menores">Menores de edad</a></li>
        <li><a href="#seguridad">Seguridad</a></li>
        <li><a href="#permisos">Permisos de la app</a></li>
        <li><a href="#cambios">Cambios y vigencia</a></li>
    </ol>
</nav>

<h2 id="responsable">1. Responsable del tratamiento</h2>
<ul class="legal__facts">
    <li><strong>Responsable:</strong> <?= e($legal['owner']) ?>, propietaria y operadora de TREVIX.</li>
    <li><strong>Fundador y propietario de <?= e($legal['owner']) ?>:</strong> <?= e($legal['founder']) ?>.</li>
    <li><strong>País:</strong> <?= e($legal['country']) ?>.</li>
    <li><strong>Correo para privacidad y soporte:</strong> <?= $mail ?>.</li>
</ul>

<h2 id="datos">2. Datos que tratamos</h2>
<p><strong>Los que nos das al registrarte:</strong> nombre visible, nombre de usuario, correo electrónico, fecha de
    nacimiento y contraseña. La contraseña nunca se guarda tal cual: solo almacenamos una huella cifrada (hash) que no
    permite recuperarla.</p>
<p><strong>Los de tu perfil, si decides agregarlos:</strong> foto de perfil y portada, biografía, ciudad actual y de
    origen, situación sentimental, género, enlaces a otras redes, datos de contacto y la canción de tu perfil. Tú eliges
    quién ve estos detalles (todos, seguidores, amistades o nadie) y si se muestra tu año de nacimiento.</p>
<p><strong>Lo que publicas y compartes:</strong> publicaciones, fotos, videos, Reels, hilos, comentarios, historias,
    notas, encuestas, menciones, eventos, comunidades, canciones que subas como artista y las ubicaciones que decidas
    agregar.</p>
<p><strong>Tu actividad en TREVIX:</strong> a quién sigues y quién te sigue, me gusta, reacciones, guardados,
    reportes, bloqueos, vistas de historias y notas, tu lista de mejores amigos y tus ajustes de privacidad.</p>
<p><strong>Tus mensajes:</strong> textos, fotos, videos, notas de voz, GIF, stickers, ubicaciones y reacciones que
    envías en chats y grupos, junto con el registro de entrega y lectura (ver la sección 5).</p>
<p><strong>Datos técnicos mínimos:</strong> la dirección IP desde la que te conectas y el nombre del dispositivo de
    cada sesión de la app, que usamos para la seguridad (limitar intentos de acceso, detectar abusos y mostrarte tus
    sesiones activas).</p>
<p><strong>Si pides el verificado:</strong> el nombre completo, la categoría y la nota que envías, y las cifras de tu
    cuenta con las que evaluamos la solicitud (seguidores y promedio de me gusta).</p>
<p><strong>Datos sensibles:</strong> no te pedimos datos sensibles (origen racial o étnico, orientación política,
    convicciones religiosas, salud, vida sexual o datos biométricos). Si decides incluirlos en tu contenido, lo haces de
    forma voluntaria y no estás obligado a hacerlo.</p>
<p>No subimos tu lista de contactos a nuestros servidores, no usamos reconocimiento facial y no rastreamos tu ubicación: solo guardamos
    una ubicación cuando tú la agregas a una publicación, una historia o un mensaje.</p>

<h2 id="finalidades">3. Para qué los usamos</h2>
<ul>
    <li>Crear y administrar tu cuenta, iniciar sesión y mantener tus sesiones abiertas.</li>
    <li>Mostrar tu perfil y tu contenido a las personas que elijas, armar tu inicio, Explorar y las sugerencias de
        personas, y entregar tus mensajes.</li>
    <li>Enviarte avisos sobre tu actividad (seguidores, me gusta, comentarios, mensajes) y correos sobre tu cuenta:
        verificación del correo, recuperación de la contraseña y cambios de seguridad. No enviamos publicidad.</li>
    <li>Mantener la seguridad: limitar intentos de acceso, prevenir el spam y las cuentas falsas, y revisar los
        reportes de contenido que incumple los <a href="<?= e(url('legal.php', ['doc' => 'terminos'])) ?>">Términos y
        condiciones</a>.</li>
    <li>Atender tus solicitudes, consultas y reclamos.</li>
    <li>Cumplir obligaciones legales y atender requerimientos de autoridades competentes.</li>
</ul>
<p><strong>No vendemos ni alquilamos tus datos personales, no mostramos publicidad y no usamos herramientas de
    rastreo ni de analítica de terceros.</strong></p>

<h2 id="autorizacion">4. Autorización</h2>
<p>Al crear tu cuenta y marcar la casilla de aceptación nos das tu autorización previa, expresa e informada para tratar
    tus datos según esta política. Puedes revocarla en cualquier momento eliminando tu cuenta desde Ajustes o
    escribiéndonos a <?= $mail ?>, salvo que exista un deber legal o contractual de conservarlos.</p>

<h2 id="mensajes">5. Mensajes, cifrado y visualización única</h2>
<ul>
    <li><strong>Cifrado de extremo a extremo:</strong> en la app, los chats y grupos se cifran cuando todas las personas
        tienen la app configurada. El contenido se cifra en tu teléfono y nuestros servidores solo guardan el mensaje
        cifrado y tu clave protegida con el PIN de 6 dígitos que tú eliges: no podemos leer esos mensajes ni recuperar
        tu PIN. Si alguien del chat solo usa la web, ese chat no se cifra.</li>
    <li><strong>Mensajes sin cifrar:</strong> se guardan en nuestros servidores para entregarlos. Solo el equipo de
        moderación puede revisar un mensaje cuando alguien lo reporta.</li>
    <li><strong>Visualización única:</strong> las fotos y videos de una vez se borran del servidor cuando todas las
        personas del chat los abrieron, o a los 14 días si no se abren. Mientras se ven, la app bloquea las capturas y la
        grabación de pantalla, pero no puede impedir que alguien los fotografíe con otro dispositivo.</li>
    <li><strong>Mensajes temporales:</strong> si los activas, se borran tras el tiempo elegido (24 horas, 7 o 90 días).</li>
    <li><strong>Entrega y lectura:</strong> registramos hasta qué mensaje le llegó y leyó cada persona del chat para
        mostrarlo en «Info». La «Confirmación de lectura» es recíproca: si la desactivas, nadie ve cuándo leíste y tú
        tampoco ves quién leyó lo tuyo.</li>
</ul>

<h2 id="visibilidad">6. Qué ven otras personas</h2>
<p>Tu nombre visible, nombre de usuario y foto de perfil son siempre visibles para que puedan encontrarte. Si tu cuenta
    es privada, solo tus seguidores aprobados ven tus publicaciones e historias. Puedes limitar quién te envía
    mensajes, quién ve tu actividad y quién ve los detalles de tu perfil, compartir historias y notas solo con tus
    mejores amigos, y bloquear a cualquier persona. Ten en cuenta que lo que publicas con tu cuenta pública puede verlo
    cualquier persona que use TREVIX, y que quien lo vea podría compartirlo fuera de la plataforma.</p>

<h2 id="terceros">7. Con quién compartimos datos</h2>
<p>Solo compartimos lo necesario con estos proveedores, que actúan como encargados o prestan un servicio técnico:</p>
<ul>
    <li><strong>Hostinger:</strong> aloja los servidores, la base de datos, los archivos y el correo de TREVIX.</li>
    <li><strong>GIPHY:</strong> buscamos los GIF y stickers desde nuestro servidor, pero las imágenes se cargan desde
        los servidores de GIPHY, que reciben tu dirección IP y datos técnicos de tu dispositivo.</li>
    <li><strong>Audius y Free To Use:</strong> catálogos de música libre. Las búsquedas se hacen desde nuestro servidor,
        sin enviar tu identidad; algunas canciones pueden cargarse desde sus servidores.</li>
    <li><strong>OpenStreetMap (Nominatim):</strong> cuando agregas una ubicación, enviamos solo las coordenadas desde
        nuestro servidor para obtener el nombre del lugar. Los enlaces de mapas abren OpenStreetMap o Google Maps, que
        tienen sus propias políticas.</li>
    <li><strong>Google Fonts:</strong> la app puede descargar tipografías desde los servidores de Google, que reciben
        tu dirección IP.</li>
    <li><strong>Apple App Store y Google Play:</strong> distribuyen las apps; lo que traten al descargarlas se rige por
        sus políticas.</li>
    <li><strong>Autoridades:</strong> solo cuando una orden judicial o una autoridad competente lo exija conforme a la
        ley, o para proteger la vida o la integridad de una persona.</li>
</ul>
<p>Las notificaciones de la app funcionan consultando nuestros propios servidores: no usamos Firebase ni servicios de
    notificaciones de terceros con fines publicitarios.</p>

<h2 id="transferencias">8. Transferencias internacionales</h2>
<p>Los servidores de nuestros proveedores pueden estar fuera de <?= e($legal['country']) ?>. Al aceptar esta política
    autorizas la transmisión de tus datos a esos servidores, que se hace únicamente para prestar el servicio y con
    proveedores que aplican medidas de seguridad adecuadas.</p>

<h2 id="conservacion">9. Cuánto tiempo los conservamos</h2>
<ul>
    <li><strong>Tu cuenta y tu contenido:</strong> mientras tengas la cuenta. Si la desactivas, se oculta hasta que
        vuelvas a iniciar sesión.</li>
    <li><strong>Al eliminar tu cuenta:</strong> borramos de inmediato y de forma permanente tu perfil, publicaciones,
        historias, comentarios, mensajes, archivos y canciones. Las copias de seguridad del alojamiento pueden conservar
        datos por un tiempo limitado hasta que se sobrescriben.</li>
    <li><strong>Historias:</strong> se borran con sus archivos a las 24 horas, salvo las que guardes en tus destacados.
        <strong>Notas:</strong> a las 6 horas.</li>
    <li><strong>Sesiones de la app:</strong> vencen tras 90 días sin uso o al cerrar sesión.</li>
    <li><strong>Enlaces enviados por correo:</strong> la verificación vence a las 48 horas, la recuperación de la
        contraseña a la hora y el cambio de correo a las 24 horas.</li>
    <li><strong>Registros de moderación:</strong> las decisiones del equipo se conservan para la seguridad de la
        plataforma y para atender reclamos.</li>
</ul>

<h2 id="derechos">10. Tus derechos</h2>
<p>Como titular de tus datos tienes derecho a:</p>
<ul>
    <li>Conocer, actualizar y rectificar tus datos. Puedes hacerlo directamente desde Ajustes y Editar perfil.</li>
    <li>Solicitar prueba de la autorización que nos diste.</li>
    <li>Ser informado sobre el uso que damos a tus datos.</li>
    <li>Revocar la autorización y pedir la supresión de tus datos cuando no se respeten los principios y garantías
        legales. Puedes eliminar tu cuenta en cualquier momento desde Ajustes.</li>
    <li>Acceder gratuitamente a tus datos personales.</li>
    <li>Presentar quejas ante la Superintendencia de Industria y Comercio (SIC), después de haber agotado el trámite de
        consulta o reclamo ante nosotros.</li>
</ul>

<h2 id="procedimiento">11. Cómo ejercerlos</h2>
<p>Escríbenos a <?= $mail ?> desde el correo de tu cuenta, indicando tu nombre de usuario y lo que solicitas.</p>
<ul>
    <li><strong>Consultas:</strong> las respondemos en un máximo de 10 días hábiles. Si no es posible, te avisaremos el
        motivo y la nueva fecha, que no superará 5 días hábiles más.</li>
    <li><strong>Reclamos</strong> (corrección, actualización, supresión o incumplimiento): deben incluir tu
        identificación, la descripción de los hechos y los documentos que quieras hacer valer. Los atendemos en un
        máximo de 15 días hábiles, prorrogables hasta 8 días hábiles más con aviso previo. Si el reclamo está incompleto
        te pediremos completarlo en 5 días; si pasan 2 meses sin respuesta, se entenderá que desististe.</li>
</ul>

<h2 id="menores">12. Menores de edad</h2>
<p>TREVIX no está dirigido a menores de 13 años y no permite crear cuentas a quienes declaren una edad menor. Las
    personas entre 13 y 17 años deben contar con la autorización de su padre, madre o representante legal. Tratamos
    los datos de niños, niñas y adolescentes respetando su interés superior y sus derechos fundamentales. Si eres
    representante legal y crees que un menor nos dio sus datos sin tu autorización, escríbenos a <?= $mail ?> y
    eliminaremos la cuenta.</p>

<h2 id="seguridad">13. Seguridad</h2>
<p>Usamos conexiones cifradas (HTTPS), contraseñas almacenadas con funciones de hash seguras, protección contra
    falsificación de peticiones (CSRF) y otros ataques comunes, límites de intentos de acceso, sesiones que vencen y
    almacenamiento seguro del dispositivo (llavero) para las sesiones y claves de la app. Ningún sistema es infalible:
    si detectamos un incidente que afecte tus datos, te informaremos y lo reportaremos a la autoridad cuando la ley lo
    exija.</p>

<h2 id="permisos">14. Permisos de la app</h2>
<p>La app solo pide permisos cuando usas la función que los necesita, y puedes retirarlos desde los ajustes del
    teléfono:</p>
<ul>
    <li><strong>Cámara y micrófono:</strong> para tomar fotos, grabar videos, historias y notas de voz.</li>
    <li><strong>Fotos y archivos:</strong> para elegir lo que quieres publicar o enviar.</li>
    <li><strong>Ubicación:</strong> solo cuando decides compartir dónde estás en un mensaje o agregarla a una
        publicación.</li>
    <li><strong>Contactos:</strong> solo si usas «Invitar contactos» en Ajustes, para elegir a quién enviar una invitación
        por SMS. La lista se lee en tu teléfono y nunca se envía a nuestros servidores.</li>
    <li><strong>Notificaciones:</strong> para avisarte de mensajes y actividad. En Android, si activas «Avisos al
        instante», la app mantiene un servicio en primer plano con un aviso fijo y silencioso que consulta nuestros
        servidores para entregarte los mensajes aunque la app esté cerrada. Puedes desactivarlo en Ajustes.</li>
</ul>

<h2 id="cambios">15. Cambios y vigencia</h2>
<p>Esta política rige desde el <?= e($legal['updated']) ?>. Si hacemos cambios importantes te avisaremos en la web o
    en la app antes de que entren en vigor. Tus datos se tratarán mientras mantengas tu cuenta y durante el tiempo
    necesario para cumplir las finalidades descritas y las obligaciones legales.</p>
