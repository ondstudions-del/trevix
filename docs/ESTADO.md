# TREVIX · Estado del proyecto

Última actualización: Fases 1 a 7 completadas, API REST v1 para las apps (primera parte de la Fase 8) y creadores de
contenido con biblioteca de música (Threads fusionado con el inicio) en producción. App de iOS en Flutter
(`mobile/`) escrita y compilando en GitHub Actions (`TREVIX.ipa` sin firmar publicado como Release).
Integraciones en producción: catálogos de música Audius y Free To Use, GIF y stickers de GIPHY en comentarios y
mensajes, notas de voz en los chats (la música ya no se envía por chat), correo por SMTP con `no-reply@ond-s.com`
y permisos del iPhone (notificaciones, ubicación, contactos, fotos y micrófono) conectados a funciones reales.
La web y la app están en español e inglés y traducen publicaciones con IA; el panel edita cuentas, banea y resuelve
apelaciones. La app tiene navegador integrado y enlaces tocables en los chats.
Siguiente: probar la app de iOS instalada con ESign, después Android; resto de la Fase 8 (optimización, PWA, push).

## Producción

- URL: `https://trevix.ond-s.com` (Hostinger, PHP 8.3, MariaDB 11.8). El esquema es compatible con MySQL 8.0+ y MariaDB 10.6+.
- Credenciales en `config/local.php` del servidor (fuera del repositorio): `env = production`, sin modo vista previa,
  `debug` forzado a `false`, base de datos por `127.0.0.1:3306`.
- No se suben al servidor: `router.php`, `database/`, `docs/`, `README.md`, `.gitignore`, `config/local.example.php`,
  `mobile/` y `.github/`.
- Correo: driver `smtp` con el buzón `no-reply@ond-s.com` creado en Hostinger (`smtp.hostinger.com:465`, SSL). La
  contraseña del buzón solo está en `config/local.php` del servidor; se puede cambiar en hPanel → Correos (y
  después en ese archivo).
- GIPHY: la clave está en `config/local.php` del servidor (`app.services.giphy.api_key`), nunca en el repositorio.
  En desarrollo se puede pasar con la variable de entorno `TREVIX_GIPHY_KEY`.
- IX (Gemini): la clave de Google AI Studio va solo en `config/local.php` del servidor (`app.ix.api_key`) o en la
  variable `TREVIX_GEMINI_KEY`. Ya instalada en producción (el panel solo muestra los 4 últimos caracteres); sin
  ella IX funciona con avisos y bienvenidas preparadas.
- Cuenta inicial: `superadmin` (rol `admin`). Verificado en vivo: login, feed, panel de administración, logout,
  recuperación de contraseña (envío aceptado por `mail()`) y respuestas 403 en carpetas internas.
- El sitio pasa por el CDN de Hostinger (`hcdn`). Los recursos de `assets/` llevan `?v=<mtime>`, así que cada
  despliegue invalida su caché. Los archivos de `uploads/` se sirven con `Cache-Control: private` para que el CDN no
  conserve imágenes de publicaciones borradas; si hace falta, la caché se purga desde hPanel.
- PHP del servidor: `upload_max_filesize` y `post_max_size` de 2048 MB, GD con WEBP; los límites efectivos son los de
  `config/app.php`.
- Migraciones: una base creada antes de la Fase 5 necesita `database/migrations/005_mensajes_notificaciones.sql`,
  una anterior a la Fase 6, `006_historias_comunidades.sql`, una anterior a la Fase 7, `007_administracion.sql`, y
  una anterior a la API, `008_api_tokens.sql`, una anterior a la música, `009_creadores_musica.sql`, y una anterior
  a los catálogos externos, `010_catalogos_gif_voz.sql`, y una anterior a eventos y destacados,
  `011_eventos_destacados_historias.sql`, y una anterior a la nueva versión de la app, `012_app_nueva_version.sql`
  y `013_verificado_advertencias.sql`, y una anterior al nuevo chat, `014_chat.sql`, y una anterior a las notas,
  `015_notas_reacciones.sql`, y una anterior a los avisos de Android, `016_avisos_android.sql`, y una anterior a
  Reels, `017_reels.sql`, y una anterior a los grupos y el cifrado, `018_grupos_cifrado.sql`, y una anterior a los videos en chats, la info de los mensajes y las notas con me gusta, `019_videos_entregas_notas.sql`, y una anterior a IX, `020_ix_soporte.sql`, y una anterior al fondo compartido y la bandeja con fijados, `021_bandeja_escribiendo.sql`, y una anterior a los idiomas y las apelaciones, `022_idiomas_apelaciones_telefono.sql` (todas ya aplicadas en producción). `database/trevix_db.sql` incluye todos los cambios para instalaciones nuevas.
- API para las apps: `https://trevix.ond-s.com/api/v1/` (referencia completa en [`docs/API.md`](API.md)). El
  `.htaccess` raíz pasa la cabecera `Authorization` a PHP y envía `api/v1/*` a `api/v1/index.php`.

## App de Android

- Es el mismo código Flutter que la de iOS (`mobile/`), con el mismo diseño y funciones. GitHub Actions solo compila
  iOS; Android se compila en Windows con `mobile/android_overrides/build-android.ps1` (APK y AAB firmados). Detalles
  en [`mobile/README.md`](../mobile/README.md).
- Adaptado para Android:
  - Avisos con canal propio e icono de barra de estado. Se pide el permiso de Android 13+.
  - Avisos al instante sin Firebase (compilación 8): `PushService` (servicio en primer plano de mensajería, en
    Kotlin) consulta `GET me/push` (`Api/Controllers/PushController.php`, `Models/Push.php`, migración
    `016_avisos_android.sql`) cada 20 s con la pantalla encendida y cada minuto apagada. Muestra mensajes (uno por
    chat, con «Responder» y «Marcar como leído»), reacciones a tus mensajes, me gusta, comentarios, menciones,
    seguidores, solicitudes y avisos de TREVIX, con la foto de la persona; tocarlos abre la pantalla. Respeta
    los chats silenciados, lo leído y los bloqueos. Ajustes › Notificaciones: «Avisos al instante», «Uso de
    batería» y «Sonido y estilo». Prueba E2E en producción: 20 comprobaciones. No se probó en un teléfono.
  - Revisión en segundo plano con WorkManager (solo si se desactivan los avisos al instante).
  - Ajustes de la app para reactivar permisos.
  - Textos «iPhone» o «teléfono» según el sistema.
  - Nombre del dispositivo en Sesiones.
  - Barras del sistema transparentes y botón «atrás».
- Enlaces:
  - `trevix://open/...` abre la app.
  - Los enlaces `https://trevix.ond-s.com/...` se verifican con `/.well-known/assetlinks.json` (`asset-links.php`).
  - En Android, el botón «Abrir en la app» de la web usa un `intent://`.
- La clave de firma no está en el repositorio: va en los secretos de GitHub. Se conserva una copia fuera del
  proyecto, en el almacén del agente. Si se pierde, los APK nuevos no se podrán instalar encima de los anteriores.
- Corregido gracias al emulador, que corre sin animaciones del sistema: con «Quitar animaciones» (Android) o
  «Reducir movimiento» (iOS), Flutter acelera 20 veces las animaciones y las historias pasaban en milisegundos.
  El temporizador de cada historia usa ahora `AnimationBehavior.preserve`.
- Publicación en Google Play: `flutter build appbundle` genera el AAB firmado con la misma clave (clave de subida).
  Si Google firma la app con su propia clave, hay que añadir su huella SHA-256 a `config/app.php` (`app.android.sha256`).
- El repositorio es público desde el 8 de noviembre de 2026 (GitHub Actions gratis, también en Mac). Antes se revisó
  todo el historial: no contiene contraseñas, claves ni `config/local.php`.

## Idiomas (español e inglés), traducción con IA, panel de usuarios y apelaciones (web en producción)

### Idiomas
- `Core/Lang.php` + ayudantes `t()`, `tn()` (plurales con `{n}`) y `locale()` en PHP; `Trevix.t()` y `Trevix.tn()`
  en `assets/js/core.js`. El texto en español es la clave: los diccionarios en inglés están en `app/Lang/en/*.php`
  (`admin`, `content`, `controllers`, `js`, `layout`, `legal`, `messages`, `pages`; se fusionan y gana el primero en
  orden alfabético). Lo que falte sale en español. El JavaScript recibe solo `js.php` (`config.i18n`).
- Idioma de la web: el de la cuenta (`users.locale`), si no la cookie `trevix_lang`, si no `Accept-Language`, y por
  defecto español. Selector (`partials/lang-switch.php`, POST a `lang.php` con CSRF) en el inicio de sesión y el
  registro, la portada, las páginas legales, el panel derecho y Ajustes › Cuenta › Idioma.
- La API usa `Accept-Language` (por defecto español); `PUT me/locale` guarda el idioma de la cuenta.
- Se traducen centralmente los avisos (`Session::flash`), `Response::json`, `Response::abort`, `Reply` de la API y
  `field_error()`; fechas relativas, meses y números compactos según el idioma.
- Textos legales en inglés: `partials/legal/en/` (términos, privacidad y cookies).
- No se traducen: contenido de las personas, nombres de marca y las indicaciones internas de IX.
- La app también está en español e inglés (ver «App: inglés, traducción, enlaces y navegador»).

### Traducción de publicaciones con IA
- Botón «Traducir» en cada publicación con texto (sesión iniciada; `api/translate.php`) y `POST
  posts/{id}/translation` en la API. `Services/Translator.php` usa Gemini con salida JSON
  (`{translation, source_language}`), guarda el resultado en `post_translations` (clave publicación + idioma, se
  rehace si cambia el texto: `source_hash`), y avisa si ya está en ese idioma. Límites: 60 por hora por persona y
  2.000 al día en todo el sitio.

### Panel › Usuarios
- Editar nombre, usuario, correo, teléfono y contraseña, y marcar el correo como verificado (`Moderation::updateAccount`,
  solo `admin` y sobre rangos menores). Validación del servidor (las mismas reglas del registro), auditoría
  `user.edit` (campos, sin la contraseña) y aviso de seguridad al correo anterior. Una contraseña nueva cierra todas
  las sesiones (web y app).
- Banear (suspensión permanente, `user.ban`, cierra sus sesiones).
- «Faltas, reportes y apelaciones»: faltas (advertencias vigentes + suspensiones/baneos no anulados por una apelación
  + contenido retirado por moderación), reportes recibidos y hechos, y sus apelaciones con botones para resolverlas.
- Teléfono (`users.phone`, `+` y 7–15 dígitos) también en Ajustes › Cuenta y en `PATCH me/account`.

### Apelaciones
- La persona suspendida apela desde el login («Apelar la suspensión», `appeal.php`, con usuario y contraseña); las
  advertencias se apelan en `appeals.php` (Ajustes › Advertencias y apelaciones). Una pendiente por sanción, nueva
  apelación 7 días después de un rechazo, 3 al día.
- Panel › Apelaciones (`admin/appeals.php`, moderadores, con insignia de pendientes): aceptar (levanta la suspensión
  o retira la advertencia) o rechazar con nota obligatoria. Aviso `appeal_accepted`/`appeal_rejected`, correo y
  auditoría `appeal.*`.
- IX conoce el historial de moderación de quien le escribe (`Services/UserRecord.php`, confidencial) y su idioma.
- Migración `022_idiomas_apelaciones_telefono.sql` (aplicada en producción).

## App: inglés, traducción, enlaces, navegador y visor de fotos y videos del chat

- Idioma: `core/i18n.dart` (`Lang` y `tr()`), diccionarios en `mobile/lib/l10n/en_*.dart` con el texto en español
  como clave. Ajustes › Apariencia › Idioma: del sistema, Español o English; se guarda en el teléfono y en la cuenta
  (`PUT me/locale`) y, si el teléfono no tiene uno elegido, se usa el de la cuenta. Cambia al instante sin perder
  las pantallas abiertas. La API recibe `Accept-Language`, así que sus mensajes llegan en el mismo idioma. Fechas,
  meses y números compactos en los dos idiomas. Las tareas en segundo plano cargan el idioma antes de avisar.
  iOS declara `CFBundleLocalizations` (es, en). Los textos de permisos del sistema (`Info.plist`) siguen en español.
- Traducción de publicaciones con IX (`POST posts/{id}/translation`): «Ver traducción» / «Ver original» con «Traducido
  del … con IX». En el feed solo aparece si el texto parece de otro idioma; en el detalle y en el menú «…» siempre.
- Enlaces en los chats: «https://…», «www.…» y «dominio.com/…» se ven subrayados y se pueden tocar (también en
  publicaciones, comentarios y biografías).
- Navegador integrado (`screens/browser/`, paquete `webview_flutter`): todos los enlaces web se abren dentro de la
  app; los de TREVIX abren su pantalla. Barra de dirección o búsqueda, atrás/adelante, recargar, compartir, copiar y
  abrir fuera. Acceso: globo en Explorar, o escribir una dirección en el buscador («Abrir …» / «Buscar … en la web»).
  En iOS las páginas `http://` solo se permiten dentro del WebView (`NSAllowsArbitraryLoadsInWebContent`).
- Visor de fotos y videos del chat (iOS): las vistas previas al enviar ya no encogen ni suben la foto o el video
  cuando aparece el teclado del comentario (solo sube la barra inferior, `KeyboardLift`); los visores cierran el
  teclado al abrirse, ignoran su espacio y el video se ajusta con `FittedVideo`; arrastrar para cerrar solo actúa con
  un dedo, en vertical y sin zoom, y al soltar sin zoom la imagen vuelve al centro.
- Visores a pantalla completa del chat (fotos, videos y «ver una vez», iOS y Android): el `Stack` del cuerpo va en
  `SizedBox.expand`. Sin él medía lo que la barra superior y la foto o el video salían pequeños y pegados arriba,
  sobre la barra de estado. Prueba de regresión: `mobile/test/media_viewer_test.dart`.

## IX · Atención al cliente con IA (en producción)

- IX responde desde la cuenta `@soport` (`app.ix.username`) en su chat directo, con la API de Gemini de Google AI
  Studio (`Services/Gemini.php`: `generateContent` con salida JSON por esquema, solo HTTPS, clave en cabecera).
- `Services/Ix.php`:
  - Después de entregar la respuesta (`Core/Deferred.php`, con `litespeed_finish_request`), responde al último
    mensaje de una ráfaga con los 20 últimos del chat y la última foto normal, y la base de conocimiento
    `app/Data/ix-conocimiento.md` (bloqueada por `.htaccess`).
  - Clasifica cada consulta (pregunta, saludo, error, sugerencia, reporte, queja, reclamo, petición u otro) con
    prioridad y resumen, y abre o actualiza una solicitud en `support_tickets` para errores, sugerencias,
    reportes, quejas, reclamos, peticiones y lo que necesita a una persona.
  - Bienvenida por mensaje a cada cuenta nueva (`AccountService::register`): con Gemini, variada según la hora,
    el día, web o app, el cumpleaños y un estilo y tema al azar, sin enviar el nombre (se usa `{nombre}`); sin
    clave, una de ocho bienvenidas preparadas.
  - Límites: 30 respuestas por hora por persona, 1.500 al día en total; sin clave o si Gemini falla, un aviso por
    hora («tu mensaje quedó registrado») y la solicitud para el equipo.
  - Si alguien del equipo escribe desde `@soport` (o responde en el panel), IX calla 12 horas en ese chat.
- Se puede escribir a `@soport` sin haber verificado el correo y aunque cambie su privacidad de mensajes; nunca
  usa cifrado de extremo a extremo (`E2eeService` rechaza su clave y la rotación de sus chats).
- Panel › Soporte IX (`admin/support.php`, moderadores): solicitudes abiertas y cerradas, filtro por categoría,
  responder como `@soport`, cerrar y reabrir (con auditoría `support.*`). Insignia con las abiertas.
- Política de privacidad y términos actualizados (Google Gemini como encargado, IX es una IA y puede equivocarse).
- Configuración de IX en Panel › Soporte IX (solo `admin`, guardada en `app_settings` con auditoría
  `settings.update`): pausar las respuestas (IX deja un aviso y la solicitud para el equipo), activar la
  bienvenida, modelo (`Ix::MODELS`, por defecto `gemini-3.5-flash`), horas de silencio tras una respuesta del
  equipo (0 a 72) e indicaciones del equipo (hasta 1.500 caracteres, se añaden al prompt). Muestra la clave
  enmascarada, la actividad de 24 horas y los límites, y un botón «Probar conexión con Gemini».
- Robustez: tiempo de espera de 20 s, hasta tres intentos (modelo elegido, `gemini-flash-lite-latest` y de nuevo el
  elegido, con pausa ante 429/5xx, máximo ~40 s) y `Database::ensureAlive()` después de llamar a Gemini, porque
  MySQL cierra la conexión inactiva durante esperas largas.
- Con esta clave (nivel gratuito): `gemini-flash-latest` puede tardar más de 30 s, `gemini-2.5-*` no existe,
  `gemini-pro-latest` da 429 y hay 503 ocasionales; Flash-Lite responde en 1–2,5 s y 3.5 Flash en 3–4 s.
- Prueba E2E en producción sin clave: 12 comprobaciones (bienvenida, aviso, un solo aviso por hora, panel y borrado
  con la cuenta). Con clave: 11 comprobaciones (panel y configuración, prueba de conexión, modelo inválido,
  bienvenida con IA, respuesta sobre cifrado con los menús correctos, reporte de error clasificado y borrado).

## Chats de la app: visor, «escribiendo…», fondo compartido y bandeja (en producción)

- Visor de fotos (`widgets/media.dart`: `ZoomImage` y `MediaViewer`, también `MediaViewer.file` para las fotos
  cifradas ya descifradas): cada foto ocupa la pantalla ajustada (`BoxFit.contain`) y no se mueve con el teclado
  (`resizeToAvoidBottomInset: false`). Se acerca con pellizco (hasta 5×) o doble toque (2,5× donde se toca). Sin
  ampliar se cierra deslizando hacia arriba o abajo; ampliada, el arrastre mueve la foto y no se cambia de foto ni se
  cierra. Antes el gesto de cerrar competía con el zoom y movía la foto. El reproductor de videos del chat y la
  visualización única también ignoran el teclado y ajustan el video a la pantalla; el video se puede acercar.
- «Escribiendo…» (`conversation_participants.typing_at`):
  - La app envía `POST conversations/{id}/typing` como mucho cada 3 s mientras hay texto, y `false` al borrarlo,
    al salir del chat o al pasar la app a segundo plano.
  - El sondeo trae `meta.typing` con los nombres. Se muestra en la cabecera (en los grupos, «Ana está escribiendo…»)
    y con una burbuja de tres puntos animados. Mientras alguien escribe, el chat consulta cada 2 s.
  - La bandeja muestra «escribiendo…» en lugar del último mensaje y se actualiza cada 6 s.
- Fondo del chat compartido: pasó de cada participante a `conversations.wallpaper`, igual que el estilo. Lo ven los
  dos (o todo el grupo) y deja el aviso «cambió el fondo del chat». En los grupos solo lo cambian los administradores.
  La migración conserva el fondo que alguien ya había elegido.
- Bandeja: mantener pulsado un chat activa la selección (con «Todos» o «Ninguno»). La barra de acciones permite
  fijar o desfijar (máx. 3, `app.chat.max_pinned_chats`), silenciar, marcar como leído, agregar o quitar de
  favoritos, vaciar y eliminar, con confirmación para las dos últimas. Todo pasa por `POST conversations/bulk`
  (`MessageService::bulk`).
  - Los fijados van arriba con un alfiler; los favoritos llevan una estrella y tienen su filtro «Favoritos».
  - Vaciar (`cleared_until_id`): quien lo hace deja de ver los mensajes actuales; el chat sigue en su bandeja.
  - Eliminar (`hidden_at`): además sale de la bandeja, sin fijar ni favorito, hasta que llegue un mensaje nuevo. En
    los grupos sigue siendo miembro.
  - Ninguna de las dos borra nada para los demás.
- Prueba E2E en producción con dos cuentas temporales: 44 comprobaciones. Una falló porque la prueba esperaba otra
  cosa: un chat vaciado devuelve `preview: null` y la app muestra «Empieza la conversación». No se probó en un iPhone.

## Nueva versión de la app (en curso)

Funciones solo para la app (la web solo recibe lo mínimo de moderación: solicitudes de verificado y advertencias).

- Hecho · Apariencia y accesibilidad (Ajustes → Apariencia): tema del sistema, claro u oscuro, tamaño de texto (del
  sistema o cuatro tamaños), texto en negrita, reducir movimiento (sin escalas ni animaciones de fondo; los
  temporizadores de historias no cambian) y aumentar contraste. Se guarda en el teléfono y se aplica al instante
  sin perder la pantalla abierta. Historias, bienvenida y visor de fotos siguen siempre en oscuro.
- Hecho y en producción · Datos personales y música del perfil (migración `012_app_nueva_version.sql`, aplicada):
  Editar perfil → «Datos personales» (ciudad actual, ciudad natal, fecha de nacimiento y si se muestra el año,
  situación sentimental, género, intereses, enlaces y contactos) y «Música del perfil» (fragmento de 30 s que suena
  al tocarlo en el perfil). Quién ve los datos: todos, seguidores, amigos (seguimiento mutuo) o solo yo; intereses,
  enlaces y canción son públicos. El perfil muestra la canción, las ciudades y los enlaces, y «Información» abre el
  resto. Prueba E2E en producción: 30 comprobaciones (validaciones, públicos, cumpleaños con y sin año, canción).
- Hecho y en producción · Búsqueda de personas y sugerencias de amigos (`Models/People.php`; la tabla
  `suggestion_dismissals` va en la migración 012). Sugerencias por cercanía: te sigue, amigos en común, misma
  ciudad o ciudad natal (solo si la otra persona muestra sus datos a todos), interacciones de 90 días e intereses,
  con el motivo y «No me interesa» (90 días). Explorar las muestra arriba («Personas que quizá conozcas» → «Ver
  todas», paginado) y la búsqueda encuentra por nombre, usuario, ciudad e intereses, con el motivo. Las cuentas
  abiertas desde la búsqueda quedan en «Recientes» (solo en el teléfono; se borran al cerrar sesión). La web usa
  las mismas sugerencias y búsqueda. Prueba E2E en producción: 32 comprobaciones (te sigue, interacciones,
  intereses, ciudad oculta si no es pública, amigos en común, orden, paginación, «No me interesa»).
- Hecho y en producción · Advertencias y verificado (migración `013_verificado_advertencias.sql`, aplicada;
  `Services/VerificationService.php`, `Models/Warning.php`, `Models/VerificationRequest.php`). Ajustes →
  «Verificación» muestra los requisitos con el avance de cada uno (1.000 seguidores, promedio de 100 «Me gusta» en
  las últimas 10 publicaciones con un mínimo de 5, sin advertencias en 30 días) y deja pedirlo (categoría, nombre y
  nota) o cancelarlo; tras un rechazo hay que esperar 30 días. «Estado de la cuenta» lista las advertencias
  (vigentes, antiguas o retiradas). El equipo advierte desde el perfil («Advertir (equipo)»), desde la ficha del
  panel web o al resolver un reporte («Advertir al autor»), y puede retirarlas. Los administradores revisan las
  solicitudes en la app (Moderación → Verificado) o en `admin/verification.php`, con los números al pedirlo y los
  de ahora. Avisos del sistema como «TREVIX» (advertencia con motivo, verificado aprobado o rechazado con motivo).
  Prueba E2E en producción: 37 comprobaciones (requisitos, bloqueo sin cumplirlos, permisos, advertir, aviso,
  retirar, advertir desde un reporte, auditoría) y 9 del panel web. Aprobar o rechazar una solicitud real no se
  probó de punta a punta porque ninguna cuenta de prueba llega a 1.000 seguidores; sí sus controles (404, motivo,
  solo administradores).
- Hecho y en producción · Chat (migración `014_chat.sql`, aplicada). En la app: mantener pulsado un mensaje abre
  las reacciones (6 rápidas o cualquier emoji) y Responder, Reenviar (hasta 5 personas; la imagen o la nota de voz
  se copian), Copiar, Fijar (hasta 3, para los dos, con banner arriba), Eliminar para mí, Eliminar para todos y
  Reportar; doble toque reacciona con ❤️. Adjuntar ubicación exacta (se abre en Apple Maps o Google Maps), buscar
  dentro del chat (salta al mensaje) y buscar chats por nombre, apodo o texto en la bandeja. Menú del chat: apodo
  (solo lo ves tú), estilo del chat (12 fondos, solo para ti), mensajes temporales (24 h, 7 o 90 días, para los
  dos, con aviso en el chat; al caducar se borra el contenido), silenciar, bloquear o desbloquear y reportar.
  Las reacciones y los fijados se sincronizan con el sondeo (`meta.updated`, `meta.pinned`). La web muestra los
  avisos, respuestas, reenviados, ubicaciones, reacciones y fijados. Prueba E2E en producción: 40 comprobaciones
  (incluida la nota de voz: subida, recepción y descarga completa y por rangos con tipo `audio/*`).
- Hecho y en producción · Notas, reacciones a historias y editor de historias (migración
  `015_notas_reacciones.sql`, aplicada; `Models/Note.php`, `Services/NoteService.php`,
  `Api/Controllers/NoteController.php`). Notas: una nube de hasta 60 caracteres encima del avatar que dura 6 horas,
  para seguidores, amigos (seguimiento mutuo) o mejores amigos (Ajustes → «Mejores amigos», hasta 200 entre
  seguidores y seguidos). Se ven en la barra de historias del inicio (la propia primero, con «Publicar una nota»),
  en el perfil y en el visor de historias del autor; tocarla deja responder por mensaje privado. Reacciones a
  historias: corazón junto a la respuesta y 8 emojis rápidos; la reacción llega al autor por mensaje, que la ve en
  «Vistas» (con el emoji y primero quienes reaccionaron) y en el contador. Editor de historias: tocar una capa la
  selecciona con un marco y un tirador en la esquina para agrandar y girar con un dedo, una barra lateral de
  tamaño, pellizcar y girar con dos dedos (encaja en horizontal), y la barra «Editar · Original · Quitar · Listo».
  La web muestra las respuestas a notas y las reacciones en el chat. Prueba E2E en producción: 47 comprobaciones.
  Sin reportes de notas (caducan en 6 horas).
- Hecho y en producción · Reels, videos de 5 minutos con miniatura e hilos solo con texto e imágenes (migración
  `017_reels.sql`, aplicada: columna `post_media.poster_path`; `Services/VideoProbe.php`). `GET reels` devuelve
  todas las publicaciones con video que puede ver el usuario, ordenadas por interacción, novedad y cuentas que
  sigue, barajadas con una semilla por sesión (paginación estable). La app tiene la pantalla Reels a pantalla
  completa (`screens/reels/`), que se abre desde el inicio, al tocar cualquier video (empieza por ese) y desde
  «Crear → Reel». El servidor lee la duración y el tamaño del propio archivo (MP4/MOV/WEBM, sin ffmpeg) y rechaza
  los videos de más de 5 minutos; la app lo comprueba antes de subir y envía la miniatura (`poster`), que se ve en
  las publicaciones, Explorar, el perfil web y Reels (los videos antiguos muestran su primer fotograma). Los hilos
  no admiten video, canción, GIF, ubicación, acontecimiento ni evento (servidor, web y app). También: en Ajustes,
  el valor y la flecha de cada fila quedan a la derecha, y «Subir canción» solo aparece a los artistas. La app de
  iOS pide ahora iOS 14. Prueba E2E en producción: 26 comprobaciones (póster, duración, límite de 5 minutos con un
  MP4 modificado, hilos, orden por semilla, video inicial, privacidad, borrado del póster); la página 2 de Reels no
  se probó porque aún hay menos de 8 videos. En Android desde la compilación 9 (la miniatura se crea con
  `MediaMetadataRetriever`; grabar video usa la cámara del sistema, sin permiso nuevo). No se probó en un teléfono.
- Hecho · Emojis en Reels: comentarios de Reels en su propia hoja (`screens/reels/reel_comments.dart`) con selector
  de emojis (recientes y categorías, `widgets/emoji_picker.dart`) y emojis que se ven completos en la descripción,
  los comentarios y las publicaciones (`widgets/emoji_text.dart`, también los mensajes de solo emojis en grande).
- Hecho · Mensajería estilo Messenger, grupos, visualización única y cifrado de extremo a extremo (migración
  `018_grupos_cifrado.sql`, aplicada; servidor: `Services/GroupService.php`, `Services/E2eeService.php`,
  `Services/ChatStorage.php`, `Models/Group.php`, `Models/E2ee.php`, `Api/Controllers/GroupController.php`,
  `Api/Controllers/E2eeController.php`, página `g.php` para los enlaces de invitación). Prueba E2E en producción:
  79 comprobaciones (grupos, permisos de administrador, enlaces, solicitudes, visualización única con 410 al
  repetir, claves y épocas con 409, archivos cifrados, almacenamiento y limpieza 30/90 días). En la app:
  - Bandeja con «Chats» en grande, personas activas, filtros Todos / No leídos / Grupos, crear grupo y buscar
    grupos públicos. Chat con burbujas agrupadas, colores del estilo del grupo, «Visto» con los avatares de quienes
    leyeron, deslizar para responder, reacciones con cualquier emoji, responder, reenviar, destacar (grupos) o
    fijar, eliminar y mensajes temporales.
  - Editor de foto antes de enviar: texto con 8 fuentes y 10 colores, dibujo con deshacer, emojis y stickers de
    GIPHY (mover, agrandar y girar; arrastrar a la papelera para quitar), pie de foto y visualización única
    (1 vez, 3, 5 o 10 s; no se guarda en el teléfono).
  - Grupos privados o públicos con enlace de invitación (`trevix.ond-s.com/g.php?c=…`, abre la app). El creador y
    los administradores cambian nombre, foto, portada, descripción, estilo, visibilidad y mensajes temporales,
    ven miembros, invitan, eliminan, aceptan solicitudes y restablecen el enlace. Contenido enviado (fotos y
    enlaces) y almacenamiento del grupo (por tipo y por persona).
  - Ajustes › Chats › «Eliminar almacenamiento del chat»: lo guardado en el teléfono por chat y tus archivos
    enviados de más de 30 o 90 días en el servidor (el mensaje queda como «Archivo eliminado»).
  - Cifrado de extremo a extremo en chats y grupos: clave X25519 en el llavero con copia protegida por un PIN de 6
    dígitos (se pide al abrir Mensajes; «Olvidé mi PIN» crea una clave nueva y los mensajes viejos quedan sin
    leer). Se cifra cuando todos tienen la app configurada; con alguien que solo usa la web, el chat sigue sin
    cifrar y la web muestra «Ábrelo en la app» en los mensajes cifrados. Código de seguridad para comprobarlo.
  - Sin probar en un iPhone; las primitivas de cifrado se probaron con una prueba temporal (ida y vuelta, PIN
    incorrecto, envoltura para otra persona).
  - Android (compilación 10): las mismas funciones y diseño. Los enlaces `https://trevix.ond-s.com/g.php?c=…`
    abren la app (manifiesto) y el botón «Abrir en la app» de la invitación usa `intent://`. Revisado en el
    emulador: bandeja nueva y código de seguridad de un chat cifrado.
  - Notificaciones de chats cifrados en Android (compilación 13): muestran el mensaje descifrado (y el de las
    reacciones a tus mensajes) y tienen «Responder», que envía la respuesta cifrada (crea una época nueva si hace
    falta, como la app). `lib/core/e2ee.dart` entrega la clave privada al cargarla con el PIN (canal
    `trevix/push`, `e2eeKey`/`e2eeForget`); `E2ee.kt` la guarda en las preferencias privadas cifrada con una
    clave AES-GCM del Android Keystore y la borra al cerrar sesión, al cambiar de cuenta o si la clave de la
    cuenta cambia; solo la usa si `meta.uid` de `me/push` es esa cuenta. `E2eeCrypto.kt` repite X25519,
    HKDF-SHA256 y AES-256-GCM de la app: probado con los vectores del RFC 7748 y en ambos sentidos contra el
    paquete `cryptography` de la app (Kotlin descifra lo de Dart y Dart lee la respuesta y la época nueva de
    Kotlin). Sin clave en el teléfono (PIN sin configurar) el aviso sigue diciendo «Mensaje cifrado» y no ofrece
    «Responder».
- Hecho · Videos en chats, «Info» del mensaje, confirmación de lectura, notas con me gusta y varias cuentas
  (migración `019_videos_entregas_notas.sql`):
  - Videos en chats y grupos (normales o de visualización única): «Grabar video» y «Video de la galería» en el
    clip, hasta 64 MB y 3 minutos (servidor y app), con vista previa, pie y «1 vez / 3, 5 o 10 s». Los normales
    llevan portada (`messages.media_poster`) y tamaño; en los cifrados la portada va dentro del mensaje (`th`,
    miniatura pequeña). Se reenvían (servidor y cifrados) y la web los reproduce.
  - Visualización única: el editor y el visor se ven siempre en oscuro (antes, en modo claro, los iconos salían en
    blanco sobre blanco); la foto se centra y se ajusta a la pantalla, y el video se reproduce y se cierra al
    terminar. Cada persona del chat o del grupo la abre una vez. Protección de pantalla mientras se ve
    (`screen_protector`: en iOS las capturas y grabaciones salen en negro; en Android `FLAG_SECURE`).
  - «Info» al mantener pulsado un mensaje propio (`GET messages/{id}/info`): leído, entregado y sin entregar, con
    las personas de cada lista, y quiénes abrieron la foto o el video de una vez. «Entregado» se registra cuando la
    app o la web de esa persona consulta sus chats (`conversation_participants.last_delivered_message_id`).
  - Ajustes › Chats (app) y Ajustes › Privacidad (web) › «Confirmación de lectura» (`users.read_receipts`),
    recíproca y aplicada en el servidor: quien la desactiva no muestra cuándo leyó ni abrió algo y tampoco ve quién
    leyó lo suyo.
  - Notas: sticker de GIPHY y fragmento de 30 s de una canción (suena al abrir la nota), me gusta y, en la propia,
    cuántas personas la vieron, cuántas son amistades (seguimiento mutuo), los me gusta y la lista (`note_views`,
    `note_likes`). Responder en privado ya existía.
  - Cambiar de cuenta y agregar cuentas como en Facebook (solo la app; `core/accounts.dart`,
    `widgets/account_switcher.dart`): hasta 5 cuentas con la sesión abierta en el teléfono (tokens en el llavero),
    desde Ajustes o manteniendo pulsada la pestaña del perfil, con los avisos pendientes de cada una. Al cambiar se
    descarta lo que había en memoria de la otra (cifrado, búsquedas) y los avisos en segundo plano pasan a la nueva.
    Al cerrar sesión o si el servidor cierra la sesión, pasa a otra cuenta guardada.
  - Migración aplicada en producción. Prueba E2E en producción: 45 comprobaciones (video con portada y tamaño,
    límite de 3 minutos con un MP4 modificado, video de una vez con 410 al repetir, Info sin entregar → entregado
    → leído, confirmación de lectura recíproca en ambos sentidos, foto de una vez en un grupo de 3 que abre cada
    miembro y se borra al verla todos, reenviar video con portada, notas con sticker, vistas, me gusta, amistades y
    actividad, borrado del video y la portada con la cuenta) y 12 más de notas con canción (fragmento desde 0:07,
    suma un uso, canción inexistente → 422, la vista propia no cuenta). Sin probar en un teléfono: la protección de
    pantalla, el reproductor y el cambio de cuenta.
  - Android (compilación 11) e iOS (compilación 28) con todo lo anterior.
  - Menú inferior adaptado a la barra de navegación de Android (`home_shell.dart`): con los tres botones del
    sistema la barra queda pegada al borde y su fondo de cristal llega detrás de los botones; con gestos, la
    pastilla flota justo encima de la zona del gesto. Etiquetas de accesibilidad en cada pestaña. Las barras del
    sistema son transparentes con iconos según el tema (`Tx.overlay`, `Tx.immersive`): antes los estilos de
    Flutter pintaban de negro la barra de navegación en Android 14 o anterior, también en el tema claro.
    Android compilación 12.
- Pendiente: preferencias de contenido y algoritmo del inicio; Trexis (24 h, solo cámara, se ven una vez).

## Catálogo único, compartir, enlaces a la app, destacados, eventos y extras al publicar (en producción)

### Hecho y verificado en producción (prueba E2E por la API: 35 comprobaciones)

- **Catálogo de música único:**
  - TREVIX, Audius y Free To Use salen en una sola lista (`MusicService::browse`, `GET music/browse`).
  - Se usa en el selector de la web y de la app.
- **Compartir:**
  - Opciones: X, WhatsApp, Facebook, Telegram, correo y copiar enlace (`partials/share-dialog.php`, `assets/js/share.js`).
  - TikTok no admite compartir enlaces por URL: en la web se copia el enlace y se abre TikTok para pegarlo; en la app
    se usa la hoja de compartir de iOS.
- **Enlaces que abren la app:**
  - Los enlaces `https://trevix.ond-s.com/...` muestran el botón «Abrir en la app» (`trevix://open/...`) en el iPhone.
  - La app abre la pantalla que corresponde (`mobile/lib/core/deeplinks.dart`): publicación, perfil, comunidad,
    canción, etiqueta, evento, Eventos y Destacados.
  - `/.well-known/apple-app-site-association` está preparado. Responde 404 hasta configurar un Team ID de Apple
    (Universal Links necesita una cuenta de desarrollador).
- **Destacados** (solo admin):
  - Se destaca desde el panel (Contenido → Destacar), desde el menú de la publicación en la web o desde la app.
  - Las 3 más recientes salen arriba en «Para ti» con la etiqueta «Destacado».
  - También están en la sección Destacados de Explorar (`explore.php?type=featured`).
  - Solo publicaciones públicas fuera de comunidades privadas. Avisa al autor y queda en la auditoría.
- **Extras al publicar** (web y app):
  - **Ubicación:** la del dispositivo («Barrio, Ciudad, País», coordenadas redondeadas a ~100 m) o un lugar escrito a mano.
  - **@menciones:** con sugerencias.
  - **Hilos con fondo de color.**
  - **GIF de GIPHY.**
  - **Acontecimiento importante:** trabajo, graduación, mudanza, relación, familia, viaje, logro, proyecto,
    cumpleaños u otro.
  - **Música.**
- **Eventos:**
  - Se crean con portada, nombre, inicio y fin, lugar y descripción.
  - Salen en el inicio y en la sección Eventos (`events.php`, con pestañas Próximos y Pasados; en la app, Explorar → Eventos).
  - Botones Asistiré y Me interesa (excluyentes, con contadores) que avisan al organizador.
  - Al borrar la publicación se borran el evento y su portada. Al eliminar una cuenta se descuentan sus respuestas
    y se borran las portadas de sus eventos.
- **Avisos en segundo plano (app):**
  - `workmanager` y `BGAppRefreshTask` consultan los avisos nuevos y los muestran como notificación local.
  - Es lo que permite iOS sin cuenta de Apple: sin APNs, iOS decide cada cuánto se ejecuta.
- **Cierre de la app al salir de una historia:**
  - La prueba en el simulador mostró la causa: `just_audio` en iOS lanza `NSRangeException` (observador «status»)
    al desmontar el reproductor con `stop()`.
  - El reproductor compartido ahora solo se pausa y carga cada canción en una sola operación.
  - Las pruebas de integración del visor de historias (`mobile/integration_test/story_viewer_test.dart`) se ejecutan
    en cada compilación.

### Editor de historias con foto o video (verificado en producción: 21 comprobaciones)

- **App** (`screens/stories/story_create_screen.dart`, `story_editor_tools.dart`, `widgets/story_layers.dart`):
  - Herramientas a la derecha: Texto (color, estilo normal/fondo/neón), Stickers, Música, Filtros, Mencionar y Enlace.
  - La hoja de Stickers tiene arriba Ubicación (la actual del dispositivo o escrita), Encuesta de 2 respuestas,
    Mención y Enlace, y debajo el buscador de stickers de GIPHY.
  - Cada capa se arrastra, se gira y se escala con dos dedos. Se edita con un toque y se quita arrastrándola a la
    papelera o con una pulsación larga.
  - Filtros: Vívido, Cálido, Frío, Blanco y negro, Vintage, Suave y Dramático, con vista previa.
- **Visor (app y web):** dibuja el filtro y las capas.
  - La encuesta se vota con un toque y muestra los porcentajes.
  - La mención abre el perfil, el enlace abre la página y la ubicación abre el mapa.
  - En la app, la historia se pausa mientras se abre algo.
- **Servidor:**
  - `Services/StoryOverlays.php` valida cada capa y sus límites.
  - `POST stories/{id}/poll` y la acción `poll` de `api/stories.php` registran el voto.
  - Las menciones avisan con `story_mention`.
- **Queda sin probar:** votar desde una segunda cuenta (no hay otra cuenta de prueba en producción). Sí está
  comprobado que no se puede votar la propia encuesta ni enviar una opción inválida.

## Catálogos de música, GIPHY, notas de voz, SMTP y permisos de la app (completada)

### Música de Audius y Free To Use

- `Services/MusicCatalog.php` busca en `api.audius.co/v1` y `api.freetouse.com/v3` desde el servidor (con caché de
  10 minutos en `storage/cache` y el límite `catalog_search`), y normaliza cada pista con título, artista, género,
  duración, audio de vista previa, portada y página original.
- Al elegir una pista se guarda una sola vez en `songs` (`source` + `external_id` únicos, `artist_id` NULL,
  `external_artist`, `external_url`), ya publicada, y desde ahí funciona como cualquier canción: publicaciones,
  historias, usos y ficha. El servidor vuelve a pedir la pista al catálogo, así que no se puede importar un audio
  inventado. Las fichas muestran el crédito «vía Audius / Free To Use» y el enlace a la página original.
- Web: pestañas TREVIX · Audius · Free To Use en `music.php` y en el selector de canciones. App: las mismas pestañas
  en la biblioteca y en el selector.

### GIF y stickers de GIPHY

- `Services/Giphy.php` busca GIF y stickers (o tendencias sin búsqueda) desde el servidor; la clave nunca llega al
  navegador ni a la app. Al comentar o enviar un mensaje solo se manda el `gif_id`: el servidor lo vuelve a pedir a
  GIPHY y guarda su URL, medidas y título. Un id falso responde 422.
- Comentarios: texto, GIF/sticker o ambos. Mensajes: GIF/sticker como mensaje propio (los stickers sin burbuja).
  La bandeja muestra «GIF» o «Sticker» como vista previa. El panel de contenido y los reportes muestran el GIF.
- Sin clave configurada, `app/config` devuelve `features.gifs = false` y los botones no aparecen.

### Notas de voz (los chats ya no envían música)

- Web: se graba con el micrófono en WAV (sin dependencias) y se envía como campo `voice`. App: M4A/AAC.
- `Services/VoiceUpload.php` identifica el formato por su contenido (WAV PCM, M4A/AAC o MP3), mide la duración en el
  servidor (1 a 120 s, 6 MB como máximo) y lo guarda en `uploads/messages/`. Un archivo falso o demasiado corto
  responde 422.
- Se quitó el envío de canciones por chat (web, API y app); los mensajes antiguos con canción se siguen mostrando.

### Correo por SMTP

- Buzón `no-reply@ond-s.com` creado en Hostinger. `Services/Mailer.php` envía por SMTP con SSL: verificación de
  correo, recuperación de contraseña y avisos de la cuenta.

### Permisos de la app de iOS

- Pantalla Ajustes → Dispositivo → Permisos (y una presentación única después de iniciar sesión) con el estado de
  cada permiso, un botón «Permitir» y «Ajustes» cuando se rechazó. Cada permiso tiene una función real:
  - Notificaciones: avisos locales cuando suben los mensajes sin leer o las notificaciones, mientras la app está
    abierta o en segundo plano reciente. Los avisos con la app cerrada necesitan push de Apple (APNs) y una cuenta
    de Apple Developer; ver «Notas para fases siguientes».
  - Micrófono: notas de voz en los chats.
  - Fotos: guardar en la galería las imágenes del visor.
  - Ubicación (solo en uso): «Detectar mi país» en Editar perfil.
  - Contactos: Ajustes → Invitar contactos, que abre Mensajes con una invitación. Los contactos no salen del
    teléfono.
- Las descripciones de cada permiso se añaden al `Info.plist` en `.github/workflows/ios.yml`, y el
  `AppDelegate.swift` generado se ajusta para mostrar avisos con la app en primer plano.

### Verificación realizada

- Lint de PHP sin errores. Migración 010 aplicada en producción.
- Pruebas de extremo a extremo contra producción: búsqueda y paginación en Audius y Free To Use; importación
  (repetida sin duplicar) y publicación con una canción externa; búsqueda de GIF y stickers; comentarios con solo
  sticker y con texto + GIF; id de GIF falso → 422; nota de voz WAV de 2 s servida como `audio/wav`; nota falsa o
  corta → 422; mensaje con sticker y vista previa «Tú: Sticker». Los datos de prueba se borraron.
- Envío SMTP aceptado por `smtp.hostinger.com`.

## Creadores de contenido y música (completada)

### Threads dentro del inicio

- Se quitó la sección Threads: los hilos salen mezclados con las publicaciones en todas las pestañas del inicio
  (Para ti, Siguiendo, Amigos, Tendencias). `threads.php` redirige (301) a `feed.php`, el menú ya no la muestra y la
  ruta `threads` de la API se retiró (404). El perfil conserva la pestaña «Hilos».

### Tipo de cuenta

- Editar perfil → «Tipo de cuenta»: **Cuenta normal** o **Creador de contenido**. Un creador elige una categoría:
  Artista musical, Influencer, Blogger u Otro (validado en el servidor; volver a cuenta normal borra la categoría).
  Columnas `users.account_type` y `users.creator_category`; la API lo cambia con `PATCH me`.
- El perfil muestra la insignia del creador. Solo **Artista musical** activa la sección **Artista** (`artist.php`,
  en el menú lateral) para publicar música.

### Envío y revisión de canciones

- `artist.php`: formulario (título, artistas invitados, género, contenido explícito, audio MP3/M4A de 15 s a
  15 min y 20 MB, portada opcional, confirmación de derechos), con barra de progreso y respaldo sin JavaScript.
  `Services/AudioUpload.php` identifica el formato por el contenido (tramas MPEG capa III o contenedor MP4 con pista
  de sonido y sin video) y calcula la duración en el servidor; el nombre del archivo es aleatorio.
- El panel del artista muestra contadores y pestañas: Todas, Publicadas, En revisión, Rechazadas (con el motivo),
  Retiradas, Retiradas por moderación, Canceladas y Utilizadas, con los usos en publicaciones, historias y mensajes.
  Acciones: cancelar el envío, retirar, volver a publicar y eliminar (rechazadas, canceladas o retiradas).
- Panel de administración → **Música** (moderadores y administradores): escuchar, aprobar (nota opcional),
  rechazar o retirar (motivo obligatorio) y restaurar. Distintivo con las pendientes, tarjeta en el dashboard,
  auditoría y avisos al artista (`song_approved`, `song_rejected`, `song_removed`).
- `Services/MusicService.php` (compartido por la web y la API) y `Models/Song.php`. Límite de 10 envíos al día.

### Biblioteca y usos

- `music.php`: biblioteca con búsqueda (título, invitados o artista), género y orden (recientes o más usadas); ficha
  de cada canción (`music.php?id=`) con reproductor, «Usar en publicación», «Usar en historia», más canciones del
  artista y las publicaciones que la usan. El perfil de un artista tiene la pestaña **Música**.
- Selector de música (`partials/music-picker`, `assets/js/music.js`) en el compositor, la edición de publicaciones,
  la creación de historias y los mensajes. En publicaciones e historias se elige un fragmento de hasta 30 s; en la
  biblioteca, la ficha, el perfil y los mensajes suena la canción completa. Un mensaje lleva imagen o canción, no
  ambas. Una foto o texto con música dura 15 s en historias.
- Al editar una publicación se puede añadir, cambiar o quitar la canción, o mover el fragmento.
- Si el artista retira la canción, moderación la retira o la cuenta deja de estar activa, donde se usó aparece
  «Canción no disponible». `uses_count` suma cada uso y nunca baja.
- Eliminar la cuenta de un artista borra sus canciones y sus archivos.

### Verificación realizada

- 111 comprobaciones de extremo a extremo contra la base real (dos cuentas nuevas y el superadmin), por la web y por
  la API: cambio de tipo de cuenta y sus validaciones; envío con archivo falso, demasiado corto, sin derechos, sin
  CSRF y por una cuenta que no es de artista; MP3 real generado para la prueba; aprobar, rechazar, retirar y
  restaurar con avisos y auditoría; biblioteca, filtros, ficha y buscador; canción en publicaciones (crear y editar),
  hilos, historias y mensajes; «Canción no disponible» al retirar; panel del artista con los usos; y regresión de
  las páginas (inicio, Threads, biblioteca, ficha, perfil, historias, mensajes, artista, avisos, panel).
  La única falla fue del guion: esperaba el fragmento en el segundo 20 de una canción de 45 s, y el servidor lo
  ajustó correctamente a 15 para que quepan los 30 s; se confirmó aparte con un fragmento válido.
- Limpieza: las cuentas de prueba se eliminaron con el flujo real y sus canciones y archivos se borraron con ellas.
- Producción: migración 009 aplicada; smoke test de 27 comprobaciones (biblioteca, panel del artista, panel de
  música, `app/config`, `threads` retirada, redirecciones sin sesión, `uploads/songs` sin listado, CSS y JS) y
  recorrido con sesión de las páginas principales, todas con 200. Las únicas entradas del registro de errores son de
  los minutos de la subida (código nuevo con configuración antigua) y no se repiten.

## Fase 8 (parte 1) · API REST v1 para las apps móviles (completada)

### Diseño

- JSON con token Bearer, versionada en `/api/v1`, sin sesión ni CSRF. Cubre todo lo que hace un usuario en la web
  (cuenta, perfil, ajustes, feed, publicaciones, comentarios, explorar, avisos, mensajes, historias, comunidades y
  reportes) y el panel de moderación y administración. 121 rutas en `app/Api/routes.php` (135 tras añadir la música
  y retirar `threads`).
- Formato único: `{ok, data, meta}` o `{ok: false, error: {code, message, fields}}`; fechas ISO 8601, archivos como
  URL absoluta, `Cache-Control: no-store`, `Retry-After` en los 429 y 405 con la cabecera `Allow`.
- Tokens (`Models/ApiToken.php`, tabla `api_tokens`): `trx_` + 64 hex; solo se guarda su SHA-256. Vencimiento
  deslizante de 90 días (renovado como mucho cada 2 minutos junto con la última actividad), 20 por cuenta. Cada token
  guarda la huella del hash de la contraseña, igual que la sesión web: cambiar la contraseña o «cerrar las demás
  sesiones» (desde la web o la app) invalida los tokens de los otros dispositivos. Suspender, desactivar o eliminar
  la cuenta los revoca. Lista de sesiones de la app con nombre del dispositivo, última IP y uso.
- Mantenimiento: 503 para cuentas normales en las rutas con token; `app/config` y el login siguen respondiendo.

### Lógica compartida con la web

Para no duplicar validaciones, permisos ni límites, la lógica de escritura de los controladores web pasó a servicios
que usan la web y la API, y que señalan los errores con `Core/ActionError` (estado HTTP, campos y `Retry-After`):

| Servicio | Contenido |
|----------|-----------|
| `Services/Guard.php` | Correo verificado obligatorio, rate limit con 429 y limpieza de textos |
| `Services/AccountService.php` | Login (suspensión, mantenimiento, límites), registro y enlace de recuperación |
| `Services/SettingsService.php` | Usuario y correo, privacidad, avisos, verificación, contraseña, sesiones, desactivar y eliminar |
| `Services/ProfileService.php` | Perfil e imágenes de perfil |
| `Services/PostService.php`, `Services/CommentService.php` | Publicar, editar, borrar, me gusta / guardar y comentarios |
| `Services/RelationshipService.php` | Seguir, solicitudes, quitar seguidores y bloqueos |
| `Services/MessageService.php`, `Services/StoryService.php` | Mensajes, respuestas a historias e historias |
| `Services/CommunityService.php` | Crear, unirse, moderar, ajustes, transferir y eliminar comunidades |
| `Services/ReportService.php`, `Services/ReportDecision.php` | Reportes y decisiones del panel |

Los controladores web conservan su comportamiento (JSON con `fetch`, redirección con aviso sin JavaScript) y
convierten `ActionError` con `Controller::attempt()`. `Core/Auth::actingAs()` fija la cuenta del token en la API,
`app/bootstrap.php` no abre sesión cuando se define `TREVIX_API`, y `Response::abort()` y el manejador de errores
responden en el formato de la API.

### Fase 8 (parte 1) · Verificación realizada

- 176 comprobaciones automáticas de extremo a extremo contra la base real con dos cuentas nuevas y el superadmin.
  Se probaron:
  - errores 400 / 401 / 404 / 405 / 422 / 503 y OPTIONS;
  - registro, verificación por el enlace real, login por usuario y por correo, hash del token en la base;
  - perfil e imágenes multipart, privacidad y preferencias;
  - publicar en JSON y con imagen, validaciones, feed y paginación, me gusta idempotente, guardados, comentarios y
    respuestas, edición, permisos sobre publicaciones ajenas, compartir, hashtags, búsquedas, Explorar y sugerencias;
  - seguir, perfil privado con solicitud, aceptar, bloqueo (404) y desbloqueo, avisos y lectura;
  - mensajes: bandeja, historial, lectura, imagen, sondeo con borrados y «Visto», silenciar, conversación ajena (404);
  - historias: barra, vistas únicas, espectadores, respuesta con la historia adjunta y borrado;
  - comunidades: crear, unirse, roles, publicar y quitar, editar, vetos y eliminar con confirmación;
  - reportes y panel: tomar, descartar, resolver, ficha de usuario, verificación, suspensión que revoca los tokens,
    ocultar y restaurar, borrar comentario, ajustes, mantenimiento (503 para usuarios, el equipo sigue) y auditoría;
  - sesiones: cerrar una sesión concreta, cambiar la contraseña (cierra los otros dispositivos y conserva este),
    cerrar las demás, logout;
  - regresión de la web con los controladores reconectados: login, publicar, me gusta, guardar, comentar, mensaje,
    dejar de seguir, historia, comunidad, privacidad, borrar y las seis secciones del panel.
- Las dos fallas de la primera pasada eran del propio guion de prueba y se confirmaron con una repetición corregida:
  la mención esperada se buscó en la cuenta equivocada (y el bloqueo posterior borra los avisos entre ambas, como
  corresponde), y se intentó reportar un comentario propio, lo que la API rechaza.
- Producción (smoke test, 15 comprobaciones): `login.php`, `app/config`, 401 sin token, 404 en JSON, login del
  superadmin, la cabecera `Authorization` llega a PHP en LiteSpeed, feed, Explorar, bandeja, dashboard, sesiones,
  logout con token revocado y `app/` protegida. El registro de errores de producción no tiene entradas nuevas.
- Limpieza: las cuentas de prueba (y la comunidad creada desde la web) se eliminaron por la API con el flujo real;
  se borraron la auditoría de prueba, los `rate_limits` y el hashtag vacío de prueba; `api_tokens` quedó vacía y la
  configuración, igual que antes.

## Fase 7 · Administración, moderación, reportes y auditoría (completada)

### Reportes

- `Models/Report.php`: reportes de publicaciones, comentarios, cuentas, comunidades, mensajes e historias con 9
  motivos de una lista cerrada («Otro motivo» exige detalles de al menos 5 caracteres; detalles de hasta 1000).
  Cada persona tiene un solo reporte por objetivo: repetirlo mientras sigue abierto no lo duplica y reportar algo ya
  cerrado lo reabre (transacción con `FOR UPDATE`).
- `ReportController` (`report.php?type=&id=`, `api/reports.php`): sesión, CSRF y rate limit de 20 reportes por hora.
  Solo se reporta lo que uno puede ver y nunca lo propio (404 en otro caso); un mensaje solo lo reportan los
  participantes de la conversación. Responde JSON con `fetch` o redirige con aviso sin JavaScript. Reportar no exige
  correo verificado.
- Enlace «Reportar» real en el menú de cada publicación, en los comentarios ajenos, en el menú del perfil, en la
  cabecera de una comunidad (si no eres el dueño), en los mensajes recibidos y en el visor de historias (el enlace
  sigue a la historia que se está viendo). `report.js` abre un diálogo con los motivos; sin JavaScript, el enlace
  lleva a la página `report.php` con el mismo formulario.

### Panel (`admin/`)

- `Controllers/Admin/AdminController.php`: base común con las secciones y el rol mínimo de cada una, la navegación
  filtrada por rol con el número de reportes pendientes, y `beginAction()` (CSRF, sesión, rol y rate limit
  `admin_action` de 120 acciones cada 10 min) para todo `POST`.
- Dashboard: métricas reales (cuentas y suspendidas, publicaciones y ocultas, activos en 24 h, reportes pendientes y
  recibidos en 24 h), los 5 objetivos con más reportes abiertos y, para administradores, la actividad del equipo.
- Reportes: pestañas Pendientes, Resueltos, Descartados y Todos, filtro por tipo y reportes agrupados por objetivo
  (número de reportes, motivo principal, vista previa). La ficha muestra el contenido reportado, quién lo reportó y
  por qué, el historial de auditoría del objetivo y la decisión: «Marcar como en revisión», descartar o resolver con
  una medida (ocultar o eliminar la publicación, eliminar el comentario, mensaje o historia, suspender al autor, o
  suspender o eliminar la comunidad). Solo se ofrecen las medidas que el revisor puede aplicar.
- Contenido: publicaciones (todas, visibles u ocultas, búsqueda por texto o `@usuario`) para ocultar, restaurar o
  eliminar, y comentarios para eliminar. Ocultar saca la publicación de todos los listados y del enlace directo
  (404) y ajusta los contadores; restaurarla los devuelve.
- Usuarios: listado con búsqueda y filtros por rol y estado, y ficha con estadísticas, reportes abiertos e historial.
  Acciones: suspender (1, 3, 7, 14, 30 o 90 días, 1 año o sin fecha de fin, con motivo obligatorio), levantar la
  suspensión, cambiar el rol y añadir o quitar la insignia de verificación. La suspensión cierra las sesiones abiertas
  y el login muestra el motivo y la fecha de fin; al vencer, la cuenta vuelve a entrar sola.
- Comunidades (solo administradores): listado con búsqueda y estado; suspender (deja de verse y responde 404),
  reactivar o eliminar, siempre con motivo.
- Configuración (solo administradores): registro abierto, exigir correo verificado, modo mantenimiento y un aviso
  general de hasta 200 caracteres. Cada cambio queda en la auditoría con el valor anterior y el nuevo.
- Auditoría (solo administradores): todas las acciones del equipo con filtro por tipo y por responsable, objetivo,
  nota, IP y fecha.

### Permisos (`Services/Moderation.php`)

- Moderadores: ven Dashboard, Reportes, Contenido y Usuarios; moderan contenido de usuarios y suspenden cuentas de
  usuario como máximo 30 días (`app.limits.moderator_suspension_days`), nunca sin fecha de fin.
- Administradores: todo lo anterior sin límite, más comunidades, roles, verificación, configuración y auditoría.
- Nadie actúa sobre sí mismo ni sobre una cuenta de rango igual o superior; siempre debe quedar al menos un
  administrador activo. Cada medida cierra como resueltos los reportes abiertos del objetivo y se registra en
  `admin_audit_log` (`Models/AuditLog.php`) con el responsable, la nota y la IP.

### Configuración aplicada en toda la app

- Registro cerrado: la página muestra el aviso en lugar del formulario y el servidor rechaza el envío.
- Mantenimiento (`Middleware/MaintenanceMode.php`): con sesión, solo moderadores y administradores usan la app; el
  resto recibe 503 (página propia o JSON) con la opción de cerrar sesión. El login de cuentas normales y el registro
  se bloquean, y el equipo ve un recordatorio de que el modo está activo.
- Correo verificado obligatorio (`Controller::requireVerifiedEmail`): sin confirmar el correo no se puede publicar,
  comentar, enviar mensajes, crear historias, responderlas ni crear comunidades (403 con el motivo).
- Aviso general: banner en todas las páginas de la aplicación (`partials/site-notices.php`).
- `require_email_verification` existía desde la Fase 1 con valor `1` pero no se aplicaba; la migración 007 lo deja
  en `0` para no bloquear de golpe a las cuentas sin confirmar. Se activa desde el panel.

### Fase 7 · Verificación realizada

- 91 comprobaciones automáticas contra la base real con tres cuentas (el moderador se nombró desde el panel):
  reportes de los seis tipos, formulario sin JavaScript, objetivo propio o ajeno a la conversación (404), motivo
  inválido y «Otro» sin detalles (422), duplicado sin repetir, sin CSRF (419) e invitado (login); permisos (usuario y
  moderador sin rol → 403, moderador → 403 en Configuración, Comunidades y Auditoría, sin medidas de comunidad, sin
  cambiar roles ni suspender a un administrador, máximo 30 días, motivo obligatorio); tomar, ocultar (404 para los
  usuarios y contadores), restaurar, eliminar publicación, comentario, mensaje e historia, descartar; suspensión que
  cierra la sesión y muestra el motivo al entrar; verificar, roles, suspensión sin fecha; suspender (404), reactivar
  y eliminar una comunidad; registro cerrado, aviso, mantenimiento (503 en página y JSON, el equipo sigue entrando,
  login bloqueado), correo obligatorio (403) y restauración de la configuración; auditoría con filtros y dashboard.
- Navegador: dashboard, cola y ficha de reportes (el campo de duración y la nota obligatoria aparecen al elegir
  «Suspender»), auditoría, configuración y el diálogo «Reportar» con envío sin recargar. Se corrigieron el pie del
  diálogo, que quedaba fuera de pantalla en ventanas bajas, el enlace «Ver en TREVIX» partido en dos líneas y la
  auditoría de configuración y roles, que mostraba claves internas en lugar de textos («Registro: abierto → cerrado»,
  «Usuario → Moderador»).
- Producción: todas las secciones del panel con sesión de administrador, `report.php` (404 sobre uno mismo o un
  objetivo inexistente), API sin sesión o sin CSRF → 419, `GET` → 405, motivo inválido → mensaje de validación,
  acción inválida → 400, cambiar el propio rol rechazado, `config/local.php` y `app/` → 403. Las cuentas de prueba se
  eliminaron con el flujo real y la base quedó sin reportes ni entradas de auditoría de prueba, con la configuración
  original.

## Fase 6 · Historias y comunidades (completada)

### Historias

- `Models/Story.php`: historias de 24 h (`app.story_ttl`) de tipo foto, video o texto. Las ve el autor y, si la
  cuenta está activa y no hay bloqueo, cualquiera cuando la cuenta es pública o sus seguidores cuando es privada.
  La barra del inicio muestra primero las propias, luego las cuentas seguidas con historias sin ver y al final las
  vistas; el perfil muestra un anillo (visto o sin ver) que abre `stories.php?u=usuario`.
- Subida (`StoryController`, `api/stories.php`): imágenes reprocesadas con GD hasta 1920 px y videos MP4, WEBM o
  MOV de hasta 30 MB y 30 s, con la misma validación por firma que las publicaciones, en `uploads/stories/`.
  Texto de hasta 300 caracteres con 6 fondos de una lista cerrada (un valor ajeno vuelve a Violeta) y descripción
  opcional de 200. Rate limit: 20 historias por hora.
- Visor (`stories.js`): barras de progreso, 6 s por foto o texto, duración real del video, pausa, sonido,
  teclado y gestos. Cada vista se registra una sola vez y el autor no cuenta; el autor ve «Vistas» con la lista
  de personas, crea otra o borra la actual (se borra el archivo).
- Crear historia (`stories.php?new=1`, `story-create.js`): pestañas Foto o video / Texto que funcionan también sin
  JavaScript (`:has()`), vista previa 9:16 y fondo en vivo.
- Responder: abre o crea la conversación y envía un mensaje con `messages.story_id`; el chat muestra «Respondió a tu
  historia» con miniatura, o un aviso si la historia ya caducó. No se responde a la propia ni a una que no se ve,
  y se respeta la privacidad de mensajes.
- Caducidad sin cron: `Story::purgeExpired()` borra por lotes las filas vencidas y sus archivos al publicar y al
  abrir el visor; las consultas filtran `expires_at > NOW()`, así que una historia vencida nunca se muestra.

### Comunidades

- `Models/Community.php`: comunidades públicas (cualquiera ve y se une al instante) o privadas (solo los miembros
  ven las publicaciones; administrador y moderadores aprueban cada solicitud). 14 categorías, dirección fija
  generada del nombre sin acentos (`fotografos-de-prueba`, con `-2`, `-3`… si se repite), búsqueda `FULLTEXT` con
  respaldo `LIKE`, filtro por categoría, «Mis comunidades» y sugerencias en el panel derecho y en Explorar.
- Roles: administrador (dueño, uno solo), moderador y miembro. El administrador nombra y retira moderadores, edita
  la información, la foto y la portada (GD, `uploads/communities/`), cambia la visibilidad (pasar a pública acepta
  las solicitudes pendientes), transfiere la comunidad a otro miembro y la elimina (escribiendo la dirección y con
  su contraseña). Moderadores y administrador aprueban o rechazan solicitudes, vetan y levantan vetos, y quitan
  publicaciones; un moderador no puede actuar sobre el administrador ni sus publicaciones. El administrador no
  puede salir sin transferir; una cuenta que administra comunidades no se puede eliminar hasta transferirlas o
  borrarlas.
- Publicaciones de comunidad (`posts.community_id`): solo los miembros activos publican, siempre como públicas
  dentro de la comunidad y sin compartir otras publicaciones. `Post::visibleTo` aplica la regla en todas las
  consultas: las de comunidades privadas solo las ven sus miembros (también en perfiles, búsquedas, feeds y
  enlaces directos), no se pueden compartir y quedan fuera de Tendencias. «Siguiendo» incluye las comunidades de
  las que se es miembro. Quitar una publicación la saca de la comunidad pero la conserva en el perfil del autor
  (privada si venía de una comunidad privada).
- Avisos: «solicitó unirse a…» para administrador y moderadores (se retira al resolverse) y «te aceptó en…» al ser
  aprobado; abrirlos lleva a la comunidad o a su pestaña de solicitudes. Se controlan con la preferencia
  «Seguidores y comunidades».
- Página de la comunidad (`community.php?c=dirección`): portada, estadísticas, unirse / solicitar / pendiente /
  salir, pestañas Publicaciones (con editor propio), Populares, Miembros (activos y vetados), Solicitudes y Ajustes
  con zona de riesgo. `communities.js` une y sale sin recargar desde las tarjetas; todo funciona con formularios
  sin JavaScript. Rate limit: 3 comunidades al día y 60 acciones cada 10 min; transferir y eliminar exigen la
  contraseña (rate limit `password_confirm`).
- Eliminar la cuenta borra también sus historias (y archivos) y libera los contadores de comunidades y vistas.

### Fase 6 · Verificación realizada

- 119 comprobaciones automáticas contra la base real con tres cuentas: historias de texto, imagen y video,
  validaciones (texto largo o vacío, archivo falso, sin archivo, sin CSRF → 419, sin sesión → 401), visor, vistas
  únicas, lista de espectadores, barra y anillo del perfil, respuesta como mensaje, privacidad de cuentas privadas,
  borrado con archivo, caducidad y limpieza; comunidades públicas y privadas, dirección sin acentos y repetida,
  unirse sin duplicar, publicar y su contador, no miembros y vetados sin publicar, visibilidad de publicaciones
  privadas en feed, perfil, enlace directo y Tendencias, solicitudes con aviso, aprobación, roles, moderación,
  vetos, ajustes con imágenes, cambio de visibilidad, transferencia con contraseña, búsqueda, filtro, eliminación
  con imágenes y códigos 404 / 400 / 405 / 419.
- Errores corregidos durante las pruebas: `Post::create` leía `lastInsertId()` después de actualizar el contador
  de la comunidad (devolvía 0); ahora lo lee justo tras el `INSERT`.
- Navegador: visor de historias, crear historia de texto con fondo, crear comunidad, página de la comunidad,
  publicar desde su editor (visibilidad bloqueada en Público), miembros, ajustes y listado. Se corrigieron el
  desborde de la zona de archivo en «Nueva historia», el ancho del filtro de categoría, la altura de la portada en
  móvil y los plurales («1 miembro», «1 publicación»).
- Producción: páginas de historias, comunidades, Explorar y administración con sesión; API sin sesión → 401 / 419,
  `GET` → 405, sin CSRF → 419, comunidad inexistente → 404, historia vacía → mensaje de validación;
  `uploads/stories/`, `uploads/communities/` y `config/local.php` → 403. Las cuentas y comunidades de prueba se
  eliminaron con el flujo real y sus archivos se borraron del disco.

## Fase 5 · Notificaciones y mensajes (completada)

- Esquema: `users` gana `show_activity`, `message_privacy` (`everyone` | `following` | `nobody`) y las preferencias
  `notify_follows`, `notify_likes`, `notify_comments` y `notify_mentions`.
- `Models/Notification.php`: `notify()` no avisa a uno mismo, a cuentas inactivas, a quien desactivó ese tipo ni
  entre cuentas bloqueadas, y reemplaza el aviso idéntico anterior en vez de duplicarlo (dar y quitar me gusta varias
  veces deja un solo aviso). Tipos: seguir, solicitud aceptada, me gusta, comentar, responder, mencionar y compartir.
  Deshacer la acción (quitar el me gusta, dejar de seguir, quitar un seguidor, bloquear) borra el aviso.
- `Services/Mentions.php`: extrae `@usuario` (máx. 10 por texto). Solo se avisa a las cuentas que pueden ver la
  publicación; editar una publicación avisa únicamente a las menciones nuevas. Un comentario avisa al autor del
  comentario respondido, al dueño de la publicación y a los mencionados, sin repetir a nadie.
- Página de Notificaciones real: pestañas Todas, Menciones (menciones, respuestas y comentarios) y Solicitudes,
  agrupadas en Hoy, Esta semana y Anteriores, con miniatura de la publicación, paginación por cursor, botón Seguir en
  los avisos de nuevos seguidores y «Marcar todo como leído» (con `fetch` o sin JavaScript). Abrir un aviso lo marca
  como leído y lleva a la publicación (al comentario con `#comentario-ID`) o al perfil.
- `Models/Conversation.php` y `Models/Message.php`: conversaciones directas únicas por pareja (`direct_key`), bandeja
  con el último mensaje, no leídos y silenciados, «Visto» según la última lectura de la otra persona y presencia
  «En línea» (actividad en los últimos 4 minutos, solo si ambas cuentas muestran su actividad).
- Privacidad de mensajes, comprobada en el servidor: nadie puede escribir a una cuenta bloqueada o inactiva;
  «Nadie» y «Personas que sigo» impiden iniciar conversaciones, pero quien ya te escribió puede seguir recibiendo
  respuesta. El botón «Mensaje» del perfil se deshabilita con el motivo cuando no se puede escribir.
- `MessageController` (`messages.php`, `api/messages.php`): enviar texto (2000 caracteres) y una imagen (procesada
  con GD a 1600 px en `uploads/messages/`), rate limit de 40 mensajes cada 5 min, sondeo cada 4 s (mensajes nuevos,
  borrados, «Visto», presencia), borrar los propios (queda «Mensaje eliminado» y se borra el archivo) y silenciar.
  Sin JavaScript el chat funciona con formularios y enlaces «Ver mensajes anteriores».
- Nuevo mensaje: búsqueda de personas (sin cuentas bloqueadas) o lista de las que sigues; `messages.php?to=usuario`
  abre la conversación existente o un borrador que se crea al enviar el primer mensaje.
- Contadores en vivo (`live.js` + `api/notifications.php?action=counts`, cada 45 s con la pestaña visible): avisos sin
  leer + solicitudes, y conversaciones con mensajes sin leer (las silenciadas no cuentan). La actividad se registra
  como mucho cada 2 minutos.
- Configuración → Privacidad guarda «Mostrar estado de actividad» y «¿Quién puede enviarte mensajes?»;
  Configuración → Notificaciones guarda los cuatro tipos de aviso. Eliminar la cuenta borra sus mensajes, sus
  imágenes y las conversaciones que se quedan sin participantes.

### Fase 5 · Verificación realizada

- 81 comprobaciones automáticas contra la base real con tres cuentas: avisos de seguir, solicitud aceptada, me gusta
  (sin duplicar al repetir y borrado al quitarlo), comentario, respuesta, mención y compartido; preferencias
  desactivadas; contadores; abrir un aviso y marcar todo como leído; enviar texto e imagen, sondeo, «Visto»,
  presencia y `show_activity`; borrar un mensaje (archivo eliminado); silenciar; privacidad Todos / Nadie / Personas
  que sigo y la excepción de respuesta; bloqueo; conversación ajena → 404, sin sesión → 401, acción inválida → 400,
  privacidad o mensaje vacío → 422 y sin CSRF → 419.
- Navegador: avisos con icono y contador, bandeja en escritorio y móvil, envío sin recargar, búsqueda de «Nuevo
  mensaje» sin la cuenta bloqueada.
- Producción: páginas de mensajes, notificaciones y ajustes con la sesión de administrador; API sin sesión → 401,
  sin CSRF → 419, chat ajeno → 404, escribirse a sí mismo rechazado; `uploads/messages/` y `config/local.php` → 403.
  Las cuentas de prueba se eliminaron con el flujo real (sus imágenes de mensajes se borraron del disco) y la base
  quedó sin conversaciones, mensajes ni avisos huérfanos.

## Fase 4 · Relaciones y descubrimiento (completada)

- `Models/Follow.php`: seguir, dejar de seguir, solicitudes para cuentas privadas (cancelar, aceptar, rechazar),
  quitar seguidores y aceptar todas las pendientes al volver pública la cuenta. Los contadores `followers_count` y
  `following_count` solo cambian cuando la fila se insertó o borró de verdad, y nunca bajan de cero. Una solicitud
  aceptada o rechazada se elimina (la columna `status` queda para el historial futuro).
- `Models/Block.php`: bloquear rompe en una transacción los seguimientos y solicitudes en ambos sentidos. Quien
  bloquea ve el perfil con la opción de desbloquear; la cuenta bloqueada recibe 404 en el perfil, no aparece en
  búsquedas ni sugerencias y no puede seguir. Lista de cuentas bloqueadas en Configuración → Privacidad.
- `RelationshipController` (`api/follows.php`, `api/blocks.php`): CSRF, sesión, rate limit (seguir 60 y bloquear 20
  cada 10 min), 404 si la cuenta no existe o hay bloqueo, 422 sobre la cuenta propia, 409 si la solicitud ya no está
  pendiente. Responde JSON con `fetch` y redirige con mensaje sin JavaScript.
- Perfiles privados: sin seguir, solo se ven la cabecera y los contadores; publicaciones, hilos, multimedia,
  seguidores y seguidos quedan ocultos (también en búsquedas y feeds, que ya filtraban por `follows`).
- Búsqueda (`User::search`, `Post::search`): personas por prefijo del usuario, nombre y `FULLTEXT` en usuario, nombre
  y biografía, ordenadas por coincidencia exacta, prefijo, relevancia y seguidores; publicaciones con `FULLTEXT` en
  modo booleano (prefijos `palabra*`) y respaldo `LIKE` para términos cortos o números. Explorar tiene las pestañas
  Todo, Personas, Publicaciones y Hashtags; Comunidades avisa que llega en la Fase 6.
- Sugerencias (`Follow::suggestions`): amigos de amigos, quienes te siguen, cuentas populares y nuevas, excluyendo
  las que ya sigues, las solicitudes pendientes y los bloqueos; con motivo («Te sigue», «Seguido por…», «Nuevo en
  TREVIX», «Popular en TREVIX»). Se muestran en el panel derecho y en Explorar sin búsqueda.
- Notificaciones: la pestaña Solicitudes (y Todas) lista las solicitudes reales con Aceptar y Rechazar; el aviso del
  menú cuenta las pendientes hasta que la Fase 5 añada el resto de notificaciones.
- `partials/follow-button.php` + `assets/js/follows.js`: botón Seguir / Siguiendo / Solicitud enviada como formulario
  real; con JavaScript se envía con `fetch`, actualiza todos los botones de la misma persona en la página (perfil,
  listas, panel, menú de la publicación), el contador de seguidores, y pide confirmación antes de dejar de seguir una
  cuenta privada. El menú «⋯» de cada publicación permite seguir o dejar de seguir al autor.
- Corrección: `posts.js` y `composer.js` leen la URL con `getAttribute('action')`, porque un campo `name="action"`
  oculta la propiedad `form.action` del formulario.

### Fase 4 · Verificación realizada

- 70 comprobaciones automáticas contra la base real con tres cuentas: seguir una cuenta pública (sin duplicar al
  repetir), solicitar a una privada, perfil y pestañas ocultos sin seguir, solicitudes y aviso en Notificaciones,
  aceptar (por JSON y sin JavaScript), aceptar dos veces → 409, rechazar, cancelar, volver pública aprueba las
  pendientes, «No hiciste cambios», dejar de seguir dos veces, quitar seguidor, bloquear (rompe seguimientos, 404
  para el bloqueado, oculto en búsqueda, lista en Privacidad) y desbloquear; búsqueda de personas (con `@` y por
  prefijo corto) y de publicaciones (`FULLTEXT` y respaldo `LIKE`); publicación de cuenta privada oculta a quien no
  sigue (404 y fuera de la búsqueda); sugerencias con motivo; CSRF inválido (419), sin sesión (401), cuenta propia
  (422), inexistente (404), acción inválida (400) y `GET` (405). Contadores finales verificados en la base.
- Navegador: sugerencias en Explorar, «Solicitar» → «Solicitado» sin recargar, perfil privado con solicitud
  pendiente, aceptar desde Notificaciones (el aviso del menú desaparece), Privacidad, y sincronización del botón en
  la lista de seguidores y el panel derecho.
- Producción: páginas de la fase con sesión de administrador, `follows.js` e iconos servidos, API por `GET` → 405,
  sin CSRF → 419, cuenta propia → 422 y `config/local.php` → 403. Las cuentas de prueba se eliminaron con el flujo
  real; la base quedó sin seguimientos, solicitudes ni bloqueos huérfanos.

## Fase 3 · Publicaciones (completada)

- `Services/MediaUpload.php`: hasta 10 archivos por publicación y un solo video. JPG, PNG y WEBP se reprocesan con
  GD (orientación EXIF, lado mayor de 2048 px, WEBP calidad 82 sin metadatos); los GIF se conservan para no perder la
  animación tras comprobar que son GIF reales. Videos MP4, WEBM y MOV hasta 60 MB, validados por la firma del
  contenedor (EBML / `ftyp` con marcas permitidas); HEIC y AVIF disfrazados se rechazan. Nombres aleatorios en
  `uploads/posts/`; si falla un archivo se borran los que ya se habían guardado.
- `Models/Post.php`: formatos `post` y `thread`; visibilidad Público, Seguidores y Solo yo, aplicada en todas las
  consultas (`Post::visibleTo`) junto con bloqueos y cuentas inactivas. Feed con cursor (`?before=id`) para el orden
  reciente y página para los órdenes por relevancia y guardados. Crear, editar y eliminar en transacciones que
  mantienen los contadores (`posts_count`, compartidos, hashtags) y borran los archivos.
- `Models/Hashtag.php`: extracción `#etiqueta` (letras con acentos, números y `_`, máx. 10 por publicación),
  sincronización al crear y editar, tendencias de los últimos 7 días y búsqueda sin distinguir mayúsculas ni acentos.
- `Models/Interaction.php`: me gusta y guardar como alternancia idempotente (el contador solo cambia si la fila se
  insertó o borró de verdad). `Models/Comment.php`: comentarios y un nivel de respuestas (responder a una respuesta
  cuelga del comentario principal), paginados, ocultando a usuarios bloqueados.
- Compartir: crea una publicación que enlaza a la original (con texto opcional, sin archivos). Compartir algo
  compartido apunta a la original; solo se pueden compartir publicaciones públicas.
- `PostController` (`api/posts.php`, `post.php`, `edit-post.php`), `CommentController` (`api/comments.php`),
  `api/likes.php` y `api/saves.php`. Todo `POST` valida CSRF, sesión y rate limit: publicar 10 cada 10 min,
  comentar 30 cada 10 min, me gusta y guardar 300 cada 10 min. Una petición más grande que `post_max_size`
  responde 413 antes de validar el CSRF.
- Feed real: Para ti, Siguiendo, Amigos (seguimiento mutuo), Tendencias (públicas de 7 días con interacción,
  ordenadas por relevancia) y Threads (populares y recientes). Perfil: Publicaciones, Hilos, Multimedia y Guardados
  (solo visible para el dueño). Explorar: `#etiqueta` lleva al listado paginado de esa etiqueta; texto busca etiquetas.
- Mejora progresiva: los formularios funcionan sin JavaScript. `posts.js` los envía con `fetch` (me gusta y guardar
  optimistas, sincronizando tarjetas repetidas), carga más con `IntersectionObserver` y usa un diálogo propio para
  confirmar borrados. `composer.js` sube con barra de progreso y coloca la nueva publicación al inicio del feed.
- Eliminar la cuenta libera en una transacción los contadores que la cuenta aportaba (me gusta, guardados,
  comentarios, compartidos, hashtags) y después borra sus archivos.

### Fase 3 · Verificación realizada

- 66 comprobaciones automáticas contra la base real con dos cuentas: publicar con 3 imágenes (reescalado a 2048 px
  en WEBP, GIF conservado), hilo, solo seguidores, solo yo y video; rechazo de HEIC disfrazado, PNG falso, dos videos,
  publicación vacía, texto de más de 2000 caracteres, visibilidad inválida, CSRF inválido (419) y sin sesión (401);
  reglas de visibilidad entre cuentas; me gusta y guardar por JSON y sin JavaScript; privacidad de Guardados;
  comentarios, respuestas y aplanado de niveles; compartir y compartir lo compartido; contadores de hashtags,
  exploración por etiqueta y tendencias; edición con resincronización de hashtags y control de dueño; borrado de
  hilos de comentarios por el autor de la publicación; borrado que ajusta compartidos y elimina archivos; límite 429;
  paginación sin duplicados.
- Navegador: feed real, detalle con imágenes, me gusta y guardar, compartir desde el editor, publicar sin recargar,
  aviso del límite de publicaciones en el editor, scroll infinito hasta «Estás al día» y diálogo de confirmación.
- Producción: publicación privada con imagen, me gusta, guardar, comentario, pestaña Guardados, exploración por
  etiqueta y borrado (archivo eliminado del servidor). Las cuentas y datos de prueba se borraron con el flujo real de
  eliminación de cuenta, dejando los contadores en cero.

## Fase 2 · Cuentas (completada)

- `Core/Password.php`: argon2id (bcrypt como respaldo), política de contraseñas, rehash automático, verificación
  con tiempo constante aunque el usuario no exista.
- `Models/RateLimit.php`: login 5/15 min por IP+usuario y 20/15 min por IP; registro 3/h y 15 intentos/15 min;
  recuperación 3/h por IP+correo y 10/h por IP; contraseña actual incorrecta 5/15 min; reenvío de verificación
  y cambio de correo 3/h por usuario.
- `Core/Auth.php`: huella del hash de la contraseña en la sesión. Cambiar o restablecer la contraseña, o pedir
  «cerrar las demás sesiones» (que vuelve a generar el hash), invalida las sesiones de los otros dispositivos.
- `Models/UserToken.php`: enlaces de un solo uso (solo se guarda su SHA-256), con vencimiento configurable
  (`app.security.token_ttl`): verificación 48 h, recuperación 1 h, cambio de correo 24 h.
- `Services/Mailer.php`: correos texto + HTML por `mail()`, SMTP propio (SSL o STARTTLS, sin dependencias) o
  `storage/logs/mail.log` en desarrollo. `Services/AccountMail.php`: plantillas de cada correo.
- `Services/AccountRules.php`: validación compartida de nombre, usuario, correo, fecha, biografía y sitio web.
- `Services/ImageUpload.php`: MIME real con `finfo`, `getimagesize`, límite de resolución, orientación EXIF,
  recorte al centro con GD (avatar 400×400, portada 1500×500), WEBP con nombre aleatorio; nunca se guarda el original.
- `AuthController`: registro (envía verificación), login, logout, recuperación con respuesta genérica,
  `reset-password.php` y `verify-email.php` (verificación y confirmación de cambio de correo, con aviso al correo anterior).
- `ProfileController::edit`: guarda nombre, usuario, biografía, sitio web (solo http/https), país, fecha, cuenta
  privada, foto y portada (reemplazo o eliminación, borrando el archivo anterior).
- `SettingsController`: cambiar usuario y correo (este último exige contraseña y confirmación por enlace),
  reenviar verificación, cambiar contraseña (con aviso por correo), cerrar las demás sesiones, desactivar y
  eliminar la cuenta (contraseña + escribir el usuario). Las cuentas `admin` no pueden darse de baja desde aquí.
- Aviso en la app para correos sin confirmar; botón «Cerrar sesión» también en Configuración (móvil).

### Fase 2 · Verificación realizada

Pruebas de extremo a extremo contra la base real, con los correos capturados en `mail.log`:
registro → verificación (y enlace reutilizado rechazado), cambio de usuario y de correo con aviso de seguridad,
contraseña actual incorrecta, débil o repetida rechazada, cambio de contraseña que cierra la otra sesión,
«cerrar las demás sesiones», recuperación con respuesta genérica, confirmación distinta rechazada, enlace usado
inválido, restablecer cierra todas las sesiones, perfil con imágenes (archivo PHP disfrazado de PNG rechazado,
dimensiones finales correctas, reemplazo y eliminación borran el archivo anterior), `javascript:` rechazado en el
sitio web, biografía escapada, desactivar y reactivar al iniciar sesión, eliminación definitiva con borrado de
imágenes, `POST` sin CSRF → 419 y bloqueo de baja para administradores.

## Fase 1 · Verificación realizada

- `php -l` sin errores en los 90 archivos PHP.
- Todas las páginas responden 200 en el servidor integrado (incluidas todas las pestañas y filtros);
  perfil inexistente → 404, ruta inexistente → 404, `api/posts.php` por `GET` → 405.
- Carpetas internas (`app/`, `config/`, `database/`, `storage/`, `docs/`), archivos ocultos, `.sql` y `router.php` → 403.
- `POST` sin token CSRF → 419; con token a funciones pendientes → 503 con el número de fase.
- Cabeceras CSP, `X-Frame-Options` y cookie de sesión `HttpOnly; SameSite=Lax` comprobadas.
- Revisión visual en escritorio, tableta y móvil: sin desbordamiento horizontal; editor, menús, visor de imágenes,
  «Ver más», historias y medidor de contraseñas funcionando.

## Archivos creados

### Raíz y servidor

| Archivo | Función |
|---------|---------|
| `index.php` | Landing (redirige al feed si hay sesión) |
| `login.php`, `register.php`, `forgot-password.php`, `reset-password.php`, `verify-email.php`, `logout.php` | Acceso a la cuenta |
| `feed.php`, `explore.php`, `profile.php`, `edit-profile.php` | Vistas principales |
| `threads.php` | Redirección 301 al inicio (los hilos se mezclan en el feed) |
| `music.php`, `artist.php` | Biblioteca de música y ficha de canción (`?id=`) · panel del artista |
| `admin/music.php` | Revisión de canciones (moderador o superior) |
| `api/music.php` | Buscador del selector (`GET action=search`, también en Audius y Free To Use con `source=`), importación de pistas externas y envío y gestión de canciones (`POST`, CSRF) |
| `api/gifs.php` | Búsqueda de GIF y stickers de GIPHY para la web (`GET type=&q=&offset=`) |
| `post.php`, `edit-post.php` | Detalle de una publicación con comentarios y edición (solo el autor) |
| `notifications.php`, `messages.php`, `settings.php` | Vistas principales |
| `stories.php` | Visor de historias (`?u=usuario`, `?id=`) y creación (`?new=1`) |
| `communities.php`, `community.php` | Listado, creación (`?new=1`) y página de cada comunidad (`?c=dirección&tab=`) |
| `legal.php` | Términos y condiciones, Política de privacidad (Ley 1581 de 2012) y cookies (`?doc=`); textos en `Views/partials/legal/`, responsable y correo en `config/app.php` › `legal` |
| `report.php` | Formulario de reporte sin JavaScript (`?type=&id=`) |
| `admin/index.php` | Dashboard de administración |
| `admin/reports.php`, `admin/content.php`, `admin/users.php` | Reportes, contenido y cuentas, con advertencias (moderador o superior) |
| `admin/communities.php`, `admin/settings.php`, `admin/audit.php` | Comunidades, configuración y auditoría (solo administradores) |
| `admin/verification.php` | Solicitudes de verificado: aprobar o rechazar con motivo (solo administradores) |
| `api/reports.php` | Crear reportes (`POST`, CSRF, sesión, rate limit) |
| `api/posts.php` | Crear y eliminar publicaciones (`POST`, CSRF, sesión) |
| `api/likes.php`, `api/saves.php` | Alternar me gusta y guardado |
| `api/comments.php` | Crear y eliminar comentarios y respuestas |
| `api/follows.php` | Seguir, dejar de seguir, cancelar, aceptar, rechazar y quitar seguidores |
| `api/blocks.php` | Bloquear y desbloquear cuentas |
| `api/notifications.php` | Contadores en vivo y marcar todo como leído |
| `api/messages.php` | Enviar, sondear, borrar y silenciar mensajes |
| `api/stories.php` | Crear, ver, listar espectadores, responder y borrar historias |
| `api/communities.php` | Crear, unirse, salir, solicitudes, roles, vetos, quitar publicaciones, ajustes, transferir y eliminar |
| `api/v1/index.php` | Punto de entrada de la API REST para las apps (token Bearer, sin sesión) |
| `.htaccess`, `uploads/.htaccess`, `*/.htaccess` | Protección de Apache; la raíz además reescribe `api/v1/*` y pasa `Authorization` |
| `router.php` | Router del servidor integrado de PHP (incluye `/api/v1`) |
| `.gitignore`, `README.md`, `docs/ESTADO.md`, `docs/API.md` | Proyecto y documentación (`API.md`: referencia de la API para Flutter) |
| `mobile/` | App de iOS en Flutter: `pubspec.yaml`, `lib/` (núcleo, modelos, widgets y pantallas), icono en `assets/icon/`, `README.md` |
| `.github/workflows/ios.yml` | Compila la app en un Mac de GitHub y publica `TREVIX.ipa` sin firmar (artefacto y Release) |

### Configuración y base de datos

| Archivo | Función |
|---------|---------|
| `config/app.php` | Aplicación, sesión, seguridad, límites de subida y de texto |
| `config/database.php` | Conexión MySQL (variables de entorno) |
| `config/local.example.php` | Plantilla de configuración local |
| `database/trevix_db.sql` | Esquema completo (26 tablas) |
| `database/migrations/005_mensajes_notificaciones.sql` | Columnas de privacidad y preferencias para bases anteriores a la Fase 5 |
| `database/migrations/006_historias_comunidades.sql` | Tipos de aviso de comunidades y `messages.story_id` para bases anteriores a la Fase 6 |
| `database/migrations/007_administracion.sql` | Reportes de historias, índices de reportes y auditoría, aviso general y `require_email_verification = 0` |
| `database/migrations/008_api_tokens.sql` | Tabla `api_tokens` para las sesiones de las apps |
| `database/migrations/009_creadores_musica.sql` | Tipo de cuenta, tabla `songs`, `song_id` en publicaciones, historias y mensajes, avisos de música |
| `database/migrations/010_catalogos_gif_voz.sql` | Canciones externas en `songs`, GIF en comentarios y mensajes, duración de notas de voz |
| `database/migrations/020_ix_soporte.sql` | `messages.sent_by_ix`, tabla `support_tickets` y sin clave de cifrado para `@soport` |
| `database/migrations/021_bandeja_escribiendo.sql` | `conversations.wallpaper` (fondo compartido) y en los participantes `pinned_at`, `is_favorite`, `cleared_until_id`, `hidden_at` y `typing_at` |

Tablas: `users`, `user_tokens`, `api_tokens`, `rate_limits`, `blocks`, `communities`, `community_members`, `posts`, `post_media`,
`likes`, `comments`, `saved_posts`, `hashtags`, `post_hashtags`, `follows`, `follow_requests`, `notifications`,
`conversations`, `conversation_participants`, `messages`, `stories`, `story_views`, `songs`, `reports`,
`admin_audit_log`, `app_settings`.

### Núcleo (`app/`)

| Archivo | Función |
|---------|---------|
| `bootstrap.php` | Arranque de la aplicación |
| `Core/Config.php` | Lectura de configuración con notación de puntos |
| `Core/Database.php` | PDO perezoso (solo conecta cuando se usa) y transacciones |
| `Core/Request.php` | Método, entrada, IP, HTTPS, detección de JSON, listas blancas de parámetros |
| `Core/Response.php` | Cabeceras de seguridad, redirecciones, JSON y páginas de error |
| `Core/Session.php` | Sesión segura, mensajes flash |
| `Core/Csrf.php` | Generación y verificación de tokens |
| `Core/Auth.php` | Usuario actual, login/logout, jerarquía de roles |
| `Core/View.php` | Renderizado de vistas con variables aisladas |
| `Core/ErrorHandler.php` | Registro de errores y páginas de error |
| `Core/Password.php` | Hash, verificación y política de contraseñas |
| `Core/ActionError.php` | Error de una acción con estado HTTP, campos y `Retry-After` (lo usan la web y la API) |
| `Core/Lang.php`, `Lang/en/*.php` | Idioma actual (cuenta, cookie, `Accept-Language`), traducción `t()`/`tn()` y diccionarios en inglés |
| `Models/Appeal.php`, `Services/AppealService.php` | Apelaciones de suspensiones y advertencias: crear, listar y resolver |
| `Models/PostTranslation.php`, `Services/Translator.php` | Traducción de publicaciones con Gemini y su caché |
| `Services/UserRecord.php` | Historial de moderación de una cuenta (faltas, reportes, apelaciones) para el panel e IX |
| `Controllers/LangController.php`, `Controllers/AppealController.php`, `Controllers/Admin/AppealsController.php` | Cambio de idioma, apelaciones de la persona y sección Apelaciones del panel |
| `Api/Kernel.php`, `Api/Router.php`, `Api/routes.php` | Arranque, autenticación por token, mantenimiento y tabla de rutas de la API |
| `Api/Input.php`, `Api/Reply.php`, `Api/Present.php` | Entrada JSON / formulario / multipart, respuestas JSON y representación de cada objeto |
| `Api/Controllers/*.php` | `ApiController` (base), `App`, `Auth`, `Me`, `User`, `Post`, `Explore`, `Notification`, `Message`, `Story`, `Music`, `Community`, `Report`, `Moderation` y `Admin` |
| `Models/Song.php` | Canciones: biblioteca, fichas, panel del artista, usos, revisión y disponibilidad donde se usaron |
| `Services/MusicService.php`, `Services/AudioUpload.php` | Envío y gestión de canciones y elección para publicar · validación de MP3/M4A y duración |
| `Services/HttpClient.php`, `Services/MusicCatalog.php`, `Services/Giphy.php` | Cliente HTTPS con caché · catálogos Audius y Free To Use (búsqueda e importación) · GIF y stickers de GIPHY |
| `Services/VoiceUpload.php` | Validación de notas de voz (WAV, M4A/AAC, MP3) con duración medida en el servidor |
| `Controllers/GifController.php`, `Api/Controllers/GifController.php` | Búsqueda de GIF y stickers para la web y para la API |
| `Models/ApiToken.php` | Emisión, validación, renovación, listado y revocación de tokens de las apps |
| `Services/Guard.php`, `Services/AccountService.php`, `Services/SettingsService.php`, `Services/ProfileService.php` | Reglas comunes, acceso, ajustes y perfil compartidos por la web y la API |
| `Services/PostService.php`, `Services/CommentService.php`, `Services/RelationshipService.php` | Publicaciones, comentarios y relaciones compartidos por la web y la API |
| `Services/MessageService.php`, `Services/StoryService.php`, `Services/CommunityService.php` | Mensajes, historias y comunidades compartidos por la web y la API |
| `Services/ReportService.php`, `Services/ReportDecision.php` | Reportes y decisiones del panel compartidos por la web y la API |
| `Models/Model.php`, `Models/User.php`, `Models/AdminStats.php`, `Models/RateLimit.php`, `Models/UserToken.php` | Acceso a datos |
| `Models/Post.php`, `Models/Hashtag.php`, `Models/Interaction.php`, `Models/Comment.php` | Publicaciones, hashtags, me gusta/guardados y comentarios |
| `Models/Follow.php`, `Models/Block.php` | Seguimientos, solicitudes, listas, sugerencias y bloqueos |
| `Models/Notification.php` | Creación, preferencias, listado agrupable y lectura de avisos |
| `Models/Conversation.php`, `Models/Message.php` | Bandeja, privacidad de mensajes, lectura, silencio y mensajes |
| `Models/Story.php` | Historias visibles, barra, vistas, espectadores, creación, borrado y limpieza de caducadas |
| `Models/Community.php` | Comunidades, membresías, roles, solicitudes, vetos, búsqueda, transferencia y eliminación |
| `Models/Report.php` | Reportes, agrupación por objetivo, vista previa del contenido reportado y cierre |
| `Models/AuditLog.php`, `Models/AppSetting.php` | Registro de auditoría y configuración general editable |
| `Services/Moderation.php` | Reglas de permisos y todas las medidas de moderación (con cierre de reportes y auditoría) |
| `Services/Mentions.php` | Extracción de menciones `@usuario` |
| `Services/Mailer.php`, `Services/AccountMail.php` | Envío de correos y plantillas de la cuenta |
| `Services/AccountRules.php`, `Services/ImageUpload.php` | Validación de cuenta y procesamiento de imágenes de perfil |
| `Services/MediaUpload.php` | Validación y procesamiento de imágenes y videos de publicaciones, mensajes e historias |
| `Middleware/*.php` | Autenticación, invitados, roles, CSRF y modo mantenimiento |
| `Helpers/functions.php` | Funciones de vista y formato |
| `Data/DemoData.php`, `Data/countries.php` | Demostración y catálogo de países |
| `Data/ix-conocimiento.md` | Lo que IX sabe de TREVIX (funciones, menús, políticas y límites) |
| `Core/Deferred.php` | Tareas después de entregar la respuesta (sin colas en el hosting compartido) |
| `Services/Gemini.php`, `Services/Ix.php`, `Models/Support.php` | Cliente de Gemini · IX (respuestas, clasificación, bienvenida) · cuenta de soporte y solicitudes |
| `Controllers/Admin/SupportController.php`, `Views/admin/support.php`, `admin/support.php` | Panel › Soporte IX |

### Controladores

`LandingController`, `AuthController`, `FeedController`, `ExploreController`, `ProfileController`,
`PostController`, `CommentController`, `RelationshipController`, `NotificationController`, `MessageController`,
`SettingsController`, `CommunityController`, `StoryController`, `ReportController`, `MusicController` y la base `Controller`
(`isPreview`, `viewer`, `asideData`, `rejectWritesUntil`, `onlyPost`, `redirectBack`, `fail`, `paging`, `renderList`,
`requireVerifiedEmail`). Panel: `Admin/AdminController` (base) con `DashboardController`, `ReportsController`,
`ContentController`, `MusicController`, `UsersController`, `CommunitiesController`, `SettingsController` y
`AuditController`.

### Vistas

- `layouts/`: `app`, `public`, `auth`, `immersive`, `admin`.
- `partials/`: `head`, `logo`, `flash`, `preview-banner`, `empty-state`, `sidebar`, `mobile-header`, `mobile-nav`,
  `right-panel`, `post-card`, `post-embed`, `post-list`, `comment`, `follow-button`, `message`, `stories-bar`,
  `composer-inline`, `composer` (incluye el visor de imágenes y el diálogo de confirmación), `confirm-dialog`,
  `verify-banner`, `community-card`, `community-join`, `password-confirm`, `report-fields`, `report-dialog`,
  `site-notices`, `admin-report-row`, `admin-audit-entry`, `admin-pager`, `song-chip` (reproductor),
  `song-field` (canción elegida en un formulario), `song-row`, `music-picker`, `gif` (GIF o sticker mostrado),
  `gif-field` (GIF elegido en un formulario), `gif-picker` (buscador de GIPHY).
- `pages/`: `landing`, `legal`, `error`, `maintenance`, `auth/login`, `auth/register`, `auth/forgot-password`, `feed`,
  `explore`, `profile`, `edit-profile`, `post`, `edit-post`, `notifications`, `messages`, `communities`,
  `community`, `community-new`, `settings`, `stories`, `story-new`, `report`, `music`, `song`, `artist`.
- `admin/`: `dashboard`, `reports`, `report`, `content`, `music`, `users`, `user`, `communities`, `settings`, `audit`.

### Recursos (`assets/`)

- `css/`: `tokens`, `base`, `components`, `layout`, `pages`, `music`, `landing`, `auth`, `admin`.
- `js/`: `prefs`, `core`, `app`, `composer`, `posts`, `follows`, `live`, `messages`, `stories`, `story-create`,
  `music`, `gifs`, `communities`, `report`, `admin`, `auth`, `landing`.
- `icons/`: 129 iconos Lucide. `fonts/`: 3 fuentes variables `woff2`. `img/`: favicon y 6 ilustraciones de demostración.

## Pendiente por fase

### Notas para fases siguientes

- Los archivos de publicaciones tienen nombres aleatorios no adivinables, pero cualquiera con el enlace exacto puede
  abrirlos aunque la publicación sea «Solo yo» o «Seguidores». Servirlos a través de PHP con control de acceso queda
  para la Fase 8 (optimización). Lo mismo aplica a las imágenes de `uploads/messages/` y a los archivos de
  historias de cuentas privadas en `uploads/stories/` (los archivos caducados sí se borran del disco).
- Se retiró el interruptor «Resumen semanal por correo» de Configuración → Notificaciones: necesita una tarea
  programada (cron) y se puede añadir más adelante sin cambiar el esquema de avisos.
- La mensajería usa sondeo (cada 4 s en el chat abierto, 45 s para los contadores) porque el hosting compartido no
  admite WebSockets; en la Fase 8 se puede pasar a Server-Sent Events o a un servicio de tiempo real.
- Historias: la limpieza de caducadas se hace por lotes durante el uso (sin cron). Si el sitio pasa mucho tiempo sin
  visitas, las filas vencidas siguen en la base hasta la siguiente apertura, pero nunca se muestran. En la Fase 8 se
  puede añadir un cron que llame a `Story::purgeExpired()`.
- Comunidades: un miembro vetado no puede publicar, volver a unirse ni ver una comunidad privada, pero sigue viendo y
  comentando las publicaciones de una comunidad pública, como cualquier visitante (los comentarios siguen las reglas
  de la publicación). Si un vetado abusa de los comentarios, el equipo puede eliminarlos o suspender la cuenta desde
  el panel; restringir los comentarios por veto sigue pendiente.
- El tipo `community` del `ENUM` de avisos queda reservado (sin uso); los avisos reales usan `community_request` y
  `community_accepted`.
- Los modelos se resolvieron con `Story` (vistas en `story_views`) y `Community` (membresías en
  `community_members`); no hicieron falta `StoryView.php` ni `CommunityMember.php`.

- Moderación (Fase 7): quien reporta no recibe un aviso cuando su reporte se resuelve (el estado queda en el panel);
  el autor de un contenido eliminado tampoco recibe aviso, solo la suspensión muestra su motivo al iniciar sesión.
- El panel no cambia el dueño de una comunidad: lo hace su administrador desde Ajustes → Transferir. El panel
  suspende, reactiva o elimina.
- Una comunidad suspendida cuenta como «administrada» al eliminar la cuenta de su dueño, así que este debe pedir al
  equipo que la reactive o la elimine antes de borrar su cuenta (el mensaje de error lo indica).
- Eliminar una cuenta borra los reportes que envió. Los reportes sobre contenido que ya no existe (borrado por su
  autor o con la cuenta) siguen en la cola como «Ya no existe» para que el equipo los cierre. La auditoría conserva
  las acciones de un miembro del equipo eliminado (el responsable aparece como «cuenta eliminada»).
- Música: los archivos de `uploads/songs/` tienen nombres aleatorios pero son públicos con el enlace exacto, incluso
  mientras la canción está en revisión o retirada (se sirven así para que el reproductor pueda buscar posiciones).
  Servirlos por PHP con control de acceso entra en la misma tarea de la Fase 8. No hay huella acústica: la
  revisión de derechos la hace el equipo al escuchar cada envío.
- Una canción usada en una publicación de la comunidad sigue las reglas de la publicación; la ficha de la canción
  solo lista las publicaciones que quien la mira puede ver.

### App Flutter (iOS y después Android)

- La app de iOS está en `mobile/` (detalles en [`mobile/README.md`](../mobile/README.md)). Se compila en GitHub
  Actions (`.github/workflows/ios.yml`, `macos-26` con el Xcode estable más reciente) y se instala con ESign.
  Compila sin errores desde la compilación 3 (`ios-build-3`); cada envío a `mobile/` genera una Release nueva con
  `TREVIX.ipa`. El equipo de desarrollo no tiene Flutter instalado, así que el flujo es la verificación
  (`flutter analyze` y `flutter build ios`); si falla, el registro indica archivo y línea.
- Queda fuera de la app (se abre en el panel web): gestión de cuentas, comunidades, configuración y auditoría.
- Android: reutiliza todo `lib/`; falta generar la carpeta `android/`, permisos y un flujo que publique el `.apk`.
- Notificaciones push (APNs / FCM): falta registrar el token del dispositivo y enviar los avisos. Requiere una
  cuenta de Apple Developer de pago y firmar la app con ella (una instalación con ESign no puede recibir push).
  Mientras tanto la app usa sondeo con `me/counts` y `messages/{id}/messages?after=`, igual que la web, y muestra
  avisos locales cuando suben los contadores.
- Nuevos archivos de la app: `lib/core/device.dart` (permisos, avisos locales, ubicación, contactos y guardar en
  Fotos), `lib/widgets/gif_picker.dart` (buscador de GIPHY) y `lib/screens/settings/permissions_screen.dart`
  (permisos e invitar contactos).
- Enlaces universales / App Links: falta publicar `apple-app-site-association` y `assetlinks.json` cuando existan
  el Team ID de Apple y la firma de Android.
- CORS: la API no envía cabeceras CORS porque las apps nativas no las necesitan; se añadirían solo para un cliente
  web en otro dominio.

### Fase 8 (resto) · Optimización

- Caché, compresión de imágenes, `manifest.webmanifest`, service worker, servir los archivos privados a través de
  PHP y cron para limpiar historias caducadas.
