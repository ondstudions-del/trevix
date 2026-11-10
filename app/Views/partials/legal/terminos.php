<?php
/** @var array{owner:string, founder:string, country:string, email:string, updated:string} $legal */
$mail = '<a href="mailto:' . e($legal['email']) . '">' . e($legal['email']) . '</a>';
$privacy = '<a href="' . e(url('legal.php', ['doc' => 'privacidad'])) . '">Política de privacidad</a>';
?>
<p>Bienvenido a TREVIX. Estos Términos y condiciones regulan el uso de la red social TREVIX, disponible en la web y en
    las apps para iPhone y Android, operada por <?= e($legal['owner']) ?>, empresa de <?= e($legal['country']) ?> cuyo
    fundador y propietario es <?= e($legal['founder']) ?>. Al crear una cuenta o usar TREVIX aceptas estos términos y
    la <?= $privacy ?>. Si no estás de acuerdo, no uses el servicio.</p>

<nav class="legal__toc" aria-label="Contenido de los términos">
    <ol>
        <li><a href="#requisitos">Quién puede usar TREVIX</a></li>
        <li><a href="#cuenta">Tu cuenta</a></li>
        <li><a href="#servicio">El servicio</a></li>
        <li><a href="#contenido">Tu contenido</a></li>
        <li><a href="#normas">Normas de la comunidad</a></li>
        <li><a href="#mensajes">Mensajes y visualización única</a></li>
        <li><a href="#musica">Música y propiedad intelectual</a></li>
        <li><a href="#verificado">Cuentas verificadas</a></li>
        <li><a href="#comunidades">Comunidades, grupos y eventos</a></li>
        <li><a href="#moderacion">Reportes, moderación y sanciones</a></li>
        <li><a href="#terminacion">Desactivar o eliminar tu cuenta</a></li>
        <li><a href="#propiedad">Propiedad de TREVIX</a></li>
        <li><a href="#terceros">Servicios de terceros</a></li>
        <li><a href="#responsabilidad">Garantías y responsabilidad</a></li>
        <li><a href="#cambios">Cambios en los términos</a></li>
        <li><a href="#ley">Ley aplicable</a></li>
        <li><a href="#contacto">Contacto</a></li>
    </ol>
</nav>

<h2 id="requisitos">1. Quién puede usar TREVIX</h2>
<ul>
    <li>Debes tener al menos 13 años. Si tienes entre 13 y 17 años necesitas la autorización de tu padre, madre o
        representante legal, que acepta estos términos en tu nombre.</li>
    <li>Debes dar información veraz al registrarte, en especial tu fecha de nacimiento y tu correo.</li>
    <li>No puedes usar TREVIX si te lo prohíbe la ley o si suspendimos tu cuenta de forma definitiva, salvo que te
        autoricemos expresamente.</li>
</ul>

<h2 id="cuenta">2. Tu cuenta</h2>
<ul>
    <li>Eres responsable de la actividad que se realice desde tu cuenta y de mantener tu contraseña en secreto. Si crees
        que alguien entró sin permiso, cambia la contraseña, cierra las demás sesiones desde Ajustes y escríbenos.</li>
    <li>Tu nombre de usuario no puede suplantar a otra persona, marca u organización ni inducir a error. Algunos nombres
        están reservados.</li>
    <li>En la app puedes mantener abiertas hasta 5 cuentas y cambiar entre ellas. Cada cuenta debe cumplir estos
        términos por separado.</li>
    <li>Si activas el cifrado de los mensajes, guarda bien tu PIN: no lo conocemos y, si lo olvidas, los mensajes
        cifrados anteriores no se pueden recuperar.</li>
    <li>No puedes vender, alquilar ni ceder tu cuenta.</li>
</ul>

<h2 id="servicio">3. El servicio</h2>
<p>TREVIX te permite publicar fotos, videos, Reels e hilos; compartir historias que duran 24 horas y notas que duran 6
    horas; seguir a otras personas; enviar mensajes y crear grupos; unirte a comunidades; crear eventos; escuchar y
    subir música; y pedir el verificado. El uso de TREVIX es gratuito.</p>
<p>Trabajamos para que el servicio esté disponible y funcione bien, pero podemos cambiar, agregar o retirar funciones,
    y suspenderlo temporalmente por mantenimiento, seguridad o causas ajenas a nosotros. Cuando un cambio te afecte de
    forma importante, te avisaremos.</p>

<h2 id="contenido">4. Tu contenido</h2>
<ul>
    <li>Lo que publicas sigue siendo tuyo. Para poder mostrarlo nos concedes una licencia no exclusiva, gratuita,
        mundial y limitada para alojarlo, reproducirlo, adaptarlo (por ejemplo, reducir el tamaño de una foto o crear la
        miniatura de un video) y mostrarlo dentro de TREVIX según la privacidad que elijas.</li>
    <li>La licencia termina cuando eliminas el contenido o tu cuenta, salvo para lo que otras personas ya compartieron
        contigo de forma permitida y para las copias de seguridad, que se sobrescriben con el tiempo.</li>
    <li>Solo publica contenido sobre el que tengas los derechos necesarios. Si apareces con otras personas, respeta su
        imagen y su intimidad.</li>
    <li>No usamos tu contenido para publicidad.</li>
</ul>

<h2 id="normas">5. Normas de la comunidad</h2>
<p>Para que TREVIX sea un lugar seguro, no está permitido:</p>
<ul>
    <li>Publicar o enviar contenido ilegal, o promover actividades ilegales.</li>
    <li>Cualquier contenido que sexualice o explote a menores de edad. Tenemos tolerancia cero: eliminamos la cuenta y
        lo reportamos a las autoridades competentes.</li>
    <li>Contenido sexual explícito o desnudos, y compartir imágenes íntimas de otra persona sin su consentimiento.</li>
    <li>Acosar, amenazar, intimidar o extorsionar a otras personas, o incitar a hacerlo.</li>
    <li>Discursos de odio o discriminación por raza, etnia, nacionalidad, religión, género, orientación sexual,
        discapacidad u otra condición.</li>
    <li>Contenido violento o gráfico gratuito, la promoción del terrorismo, las autolesiones o los trastornos
        alimentarios.</li>
    <li>Suplantar a otra persona, crear cuentas falsas o engañar sobre tu identidad.</li>
    <li>Spam, estafas, cadenas, la venta de seguidores o me gusta, y la manipulación de la plataforma.</li>
    <li>Publicar datos personales de otras personas (teléfono, dirección, documentos) sin su autorización.</li>
    <li>Infringir derechos de autor, marcas u otros derechos de propiedad intelectual.</li>
    <li>Usar bots, scripts o herramientas automáticas para crear cuentas, publicar, seguir o extraer datos de TREVIX.</li>
    <li>Intentar vulnerar la seguridad, saltarse los límites del servicio, acceder a cuentas ajenas, distribuir
        software malicioso o afectar el funcionamiento de TREVIX.</li>
    <li>Evadir una sanción creando otra cuenta.</li>
</ul>

<h2 id="mensajes">6. Mensajes y visualización única</h2>
<ul>
    <li>Tus mensajes son privados entre las personas del chat o del grupo. Cualquier participante puede reportar un
        mensaje que incumpla estos términos.</li>
    <li>Las fotos y videos de visualización única se pueden abrir una sola vez por persona. La app bloquea las capturas
        y la grabación de pantalla mientras se ven, pero no puede impedir que alguien los fotografíe con otro
        dispositivo. Guardar o difundir ese contenido sin el consentimiento de quien lo envió es una falta grave.</li>
    <li>La «Confirmación de lectura» es recíproca: si la desactivas, tampoco verás quién leyó tus mensajes.</li>
    <li>Respeta la decisión de quien no quiere recibir tus mensajes o te bloquea.</li>
    <li>La cuenta oficial @soport responde con IX, un asistente de inteligencia artificial que orienta sobre TREVIX y
        registra tus consultas para el equipo. IX puede equivocarse, no puede actuar sobre tu cuenta ni tomar decisiones
        de moderación, y sus respuestas no sustituyen los reclamos formales, que puedes enviar a <?= $mail ?>. Nunca te
        pediremos tu contraseña ni tu PIN por chat.</li>
</ul>

<h2 id="musica">7. Música y propiedad intelectual</h2>
<ul>
    <li>Si subes canciones como artista, declaras que eres titular de los derechos o que tienes autorización para
        publicarlas, y nos concedes la licencia de la sección 4 para reproducirlas y permitir que otras personas usen
        fragmentos en sus publicaciones, historias, notas y perfiles. Las canciones pasan por una revisión del equipo
        antes de aparecer en la biblioteca.</li>
    <li>Las canciones de los catálogos libres integrados (Audius y Free To Use) se rigen por las licencias de esos
        catálogos.</li>
    <li>Si crees que un contenido infringe tus derechos de autor o de marca, escríbenos a <?= $mail ?> con tus datos,
        el enlace al contenido y la prueba de tus derechos. Lo revisaremos y, si corresponde, lo retiraremos. Las
        cuentas que infrinjan derechos de forma reiterada pueden ser suspendidas.</li>
</ul>

<h2 id="verificado">8. Cuentas verificadas</h2>
<p>El verificado distingue a creadores, artistas, figuras públicas, marcas y otras cuentas que lo solicitaron,
    cumplen los requisitos publicados en la solicitud (seguidores, actividad y ausencia de advertencias recientes) y
    fueron aprobadas por el equipo. Al pedirlo declaras que la información que envías es verdadera. El verificado no
    implica que respaldemos las opiniones de la cuenta.
    Podemos rechazar una solicitud o retirar el verificado si la cuenta deja de cumplir los requisitos o incumple estos
    términos.</p>

<h2 id="comunidades">9. Comunidades, grupos y eventos</h2>
<p>Quien crea o administra una comunidad o un grupo puede fijar reglas adicionales, aceptar o retirar miembros y
    moderar su contenido, siempre dentro de estos términos. Quien organiza un evento es el único responsable de su
    realización, de la información que publica y de lo que ocurra en él; TREVIX solo facilita su difusión.</p>

<h2 id="moderacion">10. Reportes, moderación y sanciones</h2>
<ul>
    <li>Puedes reportar publicaciones, comentarios, historias, mensajes, perfiles y comunidades. El equipo de moderación
        revisa los reportes.</li>
    <li>Según la gravedad, podemos eliminar el contenido, darte una advertencia, suspender tu cuenta temporalmente o
        de forma indefinida, o eliminarla. En los casos más graves podemos actuar sin aviso previo.</li>
    <li>Cuando suspendemos una cuenta, te mostramos el motivo y la fecha de fin, si la hay, al iniciar sesión.</li>
    <li>Si crees que nos equivocamos, escríbenos a <?= $mail ?> desde el correo de tu cuenta y revisaremos la
        decisión.</li>
</ul>

<h2 id="terminacion">11. Desactivar o eliminar tu cuenta</h2>
<p>Puedes desactivar tu cuenta desde Ajustes: tu perfil y tu contenido se ocultan hasta que vuelvas a iniciar sesión.
    También puedes eliminarla: se borran de forma permanente tu cuenta, tu contenido y tus mensajes, y no se puede
    deshacer. Las secciones de estos términos que por su naturaleza deban seguir vigentes (por ejemplo, las de
    responsabilidad y ley aplicable) continúan aplicándose.</p>

<h2 id="propiedad">12. Propiedad de TREVIX</h2>
<p>El nombre y el logotipo de TREVIX, el diseño, el software y los demás elementos del servicio pertenecen a
    <?= e($legal['owner']) ?> y están protegidos por las normas de propiedad intelectual. No puedes copiarlos,
    modificarlos ni usarlos sin nuestra autorización escrita, salvo lo que la ley permita.</p>

<h2 id="terceros">13. Servicios de terceros</h2>
<p>TREVIX integra servicios de terceros, como los GIF y stickers de GIPHY, los catálogos de música libre, los mapas de
    OpenStreetMap y la API de Gemini de Google (para IX), y puede mostrar enlaces a otros sitios. Esos servicios tienen sus propios términos y no somos
    responsables de su contenido ni de su disponibilidad.</p>

<h2 id="responsabilidad">14. Garantías y responsabilidad</h2>
<ul>
    <li>Cada persona es responsable del contenido que publica y envía. No revisamos todo el contenido antes de que se
        publique y no respondemos por las opiniones ni por los actos de los usuarios.</li>
    <li>Prestamos el servicio con diligencia, pero no garantizamos que funcione sin interrupciones ni errores. En la
        medida en que la ley lo permita, no respondemos por daños indirectos, lucro cesante o pérdida de datos derivados
        del uso o la imposibilidad de usar TREVIX.</li>
    <li>Nada de lo anterior limita los derechos que te reconocen la Ley 1480 de 2011 (Estatuto del Consumidor) y demás
        normas imperativas de <?= e($legal['country']) ?>.</li>
    <li>Si incumples estos términos y eso causa reclamaciones de terceros contra <?= e($legal['owner']) ?>, responderás
        por los perjuicios que se deriven, según la ley.</li>
</ul>

<h2 id="cambios">15. Cambios en los términos</h2>
<p>Podemos actualizar estos términos para reflejar cambios en el servicio o en la ley. Si el cambio es importante te
    avisaremos en la web o en la app antes de que entre en vigor. Si sigues usando TREVIX después de esa fecha,
    entenderemos que aceptas la nueva versión; si no estás de acuerdo, puedes eliminar tu cuenta.</p>

<h2 id="ley">16. Ley aplicable</h2>
<p>Estos términos se rigen por las leyes de la República de <?= e($legal['country']) ?>. Cualquier controversia se
    intentará resolver primero de forma directa escribiéndonos; si no es posible, la conocerán los jueces competentes
    de <?= e($legal['country']) ?>, sin perjuicio de tu derecho a acudir a la Superintendencia de Industria y Comercio.
    Si alguna cláusula resulta inválida, las demás siguen vigentes.</p>

<h2 id="contacto">17. Contacto</h2>
<p>Para preguntas sobre estos términos, reportar un problema o revisar una decisión, escríbenos a <?= $mail ?>.
    Versión vigente desde el <?= e($legal['updated']) ?>.</p>
