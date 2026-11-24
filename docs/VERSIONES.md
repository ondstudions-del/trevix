# TREVIX · Versiones de la app

## Regla

- Cada versión que se publica con cambios en la app suma una décima: Alpha 1.2, 1.3 … 1.9 y después 2.0
  (luego 2.1 … 2.9, 3.0, etc.).
- La versión vive en dos sitios que deben coincidir (GitHub Actions falla si no coinciden):
  - `mobile/pubspec.yaml`: `version: X.Y.0+N`, donde `N` es el número de compilación de Android (sube siempre).
  - `mobile/lib/core/config.dart`: `AppConfig.version = 'Alpha X.Y'` (se muestra en Ajustes de la app).
- El Release de iOS en GitHub se llama «TREVIX iOS Alpha X.Y · compilación R».

## Alpha 3.8 (compilaciones de Android 90)

### Compilación 90
- Live OBS: vídeo en **16:9** centrado (letterbox), igual que la señal 1280×720; la cámara sigue a pantalla completa.

## Alpha 3.7 (compilaciones de Android 89)

### Compilación 89
- OBS: copiar/mostrar clave RTMP; vídeo/audio solo desde OBS; live 720p (1280×720).
- Overlays OBS: `live-obs-comments.php` y `live-obs-gifts.php` con feed propio; texto «X te regaló 1 …».

## Alpha 3.6 (compilaciones de Android 88)

### Compilación 88
- OBS: transcodificación RTMP corregida (LiveKit); servidor y clave visibles al elegir modo OBS; URL de overlay para comentarios/regalos en Browser Source.

## Alpha 3.5 (compilaciones de Android 87)

### Compilación 87
- LIVE por **OBS Studio**: modo OBS en configuración del live, RTMP Ingress (servidor + clave) y misma sala/overlay que la cámara.
- Requiere **Ingress** activado en LiveKit y migración `054`.

## Alpha 3.4 (compilaciones de Android 86)

### Compilación 86
- Fondos de chat renovados: Corazones, Estrellas y Burbujas con patrones dibujados (más suaves).
- Nuevo fondo **Orgullo** (arcoíris + corazones).
- Catálogo alineado con el servidor (sin Caramelo; verán la lista nueva al actualizar).

## Alpha 3.3 (compilaciones de Android 85)

### Compilación 85
- Chat: animaciones de reacciones y emojis (explosión al reaccionar, pastilla con rebote, mensajes solo emoji).
- Fondos de chat: Champán, Terciopelo, Perla y Duna (salen Caramelo, Corazones, Estrellas y Burbujas).

## Alpha 3.2 (compilaciones de Android 84)

### Compilación 84
- Reels: menos datos al deslizar (prefetch del siguiente, sin descarga doble, menos players en memoria).
- Biblioteca de sonidos: no listan los «Sonido original» sin nombre (sí en el reel y si el autor les pone título).

## Alpha 3.1 (compilaciones de Android 83)

### Compilación 83
- Entrega agrupada: listas con portada, compositor de listas, «Ver más» en textos largos, fondos de color en publicaciones (estilo Facebook).

### Incluye (desde 3.0.19)
- Fondos de color en publicaciones de solo texto: 15 degradados, texto centrado.
- Listas de reproducción: portada, diseño «Nueva lista», agregar al publicar reel.
- «Ver más» / «Ver menos» en publicaciones largas del feed.

## Alpha 3.0.21 (compilaciones de Android 82)

### Compilación 82
- Fondos de color en publicaciones de solo texto (estilo Facebook): 15 degradados, texto centrado en feed y compositor.
- Web y API: fondos también en formato «publicación» (no solo hilos).

## Alpha 3.0.20 (compilaciones de Android 81)

### Compilación 81
- Listas: portada obligatoria al crear, cambiar portada y diseño de «Nueva lista».
- Compositor: listas antes de publicar y hoja «¿Agregar a una lista?» después.
- Listas solo en la pestaña del perfil (sin carrusel en la cabecera).
- API + migración 053: `cover_path` / `cover_custom` en playlists.

## Alpha 3.0.19 (compilaciones de Android 80)

### Compilación 80
- Publicaciones largas: «Ver más» / «Ver menos» en el feed.
- Compositor de reel: agregar a listas de reproducción al publicar.
- Perfil de creador: carrusel de listas de reproducción y pestaña renombrada; compartir lista.

## Alpha 3.0.18 (compilaciones de Android 79)

### Compilación 79
- LIVE cámara: libera la vista previa antes de conectar LiveKit; la UI no queda cargando si tarda la cámara WebRTC.

## Alpha 3.0.17 (compilaciones de Android 78)

### Compilación 78
- Notificaciones: texto «Marcar como Leido» en lugar de icono.
- LIVE chat de voz: ondas alrededor del avatar cuando habla.
- Perfil propio: botones circulares (live, ajustes, más) estilo claro sobre portada.

## Alpha 3.0.16 (compilaciones de Android 77)

### Compilación 77
- LIVE chat de voz: rejilla minimalista, avatares pequeños y centrados.
- Crear live solo cuentas Stream (refuerzo en app).
- Feed: animación al pulsar «publicaciones nuevas».
- Notificaciones: icono «marcar todo como leído» renovado.

## Alpha 3.0.15 (compilaciones de Android 76)

### Compilación 76
- LIVE chat de voz: diseño premium, invitar desde lista de espectadores (máx. 8 en micrófono), comentarios con avatar y fecha.
- Ajustes del live: toggle +18, advertencia antes de entrar; lives +18 ocultos a menores.
- Dock «Comentar»; se quitó «Comunidad» del live.

### Servidor (migración 052)
- `live_sessions.is_adult`, tabla `live_session_audience`, `GET livekit/sessions/{id}/viewers`.

## Alpha 3.0.14 (compilaciones de Android 75)

### Servidor / Para ti
- Refresco con `refresh=1` y semilla nueva: orden más aleatorio; lo propio no se fija arriba (solo al publicar en la app).
- Más peso a publicaciones con pocos likes/visualizaciones; afinidad por hashtags de tus likes.

## Alpha 3.0.13 (compilaciones de Android 74)

### Compilación 74
- Eliminadas las videollamadas 1:1; solo llamadas de audio (chat + sala conectada).

## Alpha 3.0.12 (compilaciones de Android 73)

### Compilación 73
- Llamada conectada: UI audio/vídeo estilo WhatsApp (fondo, PiP, dock); colgar cierra en ambos dispositivos.

## Alpha 3.0.11 (compilaciones de Android 72)

### Compilación 72
- Llamadas: suena ~1 minuto antes de «no contestada»; UI entrante/saliente estilo Messenger (fondo difuminado, dock).

## Alpha 3.0.10 (compilaciones de Android 71)

### Compilación 71
- Llamadas: notificación FCM mejorada, iOS reenvía datos completos; pantalla saliente (evita cierre en iPhone).
- LIVE: doble toque = like, animación de regalos, @menciones en chat; aviso a seguidores y miembros de comunidades.

## Alpha 3.0.9 (compilaciones de Android 70)

### Compilación 70
- Sala LIVE estilo TikTok: cabecera compacta, chat lateral, dock de iconos y aviso al host.
- Resumen del LIVE a pantalla completa (felicitaciones, estadísticas y tarjetas).
- Reels más fluidos: reproduce por red sin esperar descarga completa, prefetch ±2 videos y menos trabajo por frame.

## Alpha 3.0.8 (compilaciones de Android 69)

### Compilación 69
- Corregido contestar llamadas: el servidor ya no marca como «perdida» al instante (hora `NOW()` vs `UTC_TIMESTAMP()`).
- Aceptar reintenta si la llamada ya está `active`; pantalla de preparación LIVE estilo TikTok (cámara/voz + panel inferior).

## Alpha 3.0.7 (compilaciones de Android 68)

### Compilación 68
- LIVE solo para creadores categoría **Stream** (botón en perfil propio con `isStreamer`).
- Banners al elegir categoría de creador: Stream, Influencer, Blogger, Otro (además de músico y desarrollador).
- Diseño renovado: preparación del live y barra superior/inferior en la sala.
- Llamadas: Contestar/Rechazar en la notificación Android, tono en segundo plano, UI inmediata desde FCM y sonido iOS personalizado.

## Alpha 3.0.6 (compilaciones de Android 67)

### Compilación 67
- Llamadas estilo Messenger: tono en bucle al entrar, Contestar/Rechazar; canal Android `trevix_llamadas_tono`.
- Lives fuera de Para ti: se ven en Stories (anillo rojo + VIVO), perfil y bloque «En vivo» en Explorar (swipe vertical).
- Solo Creador › Stream puede emitir; setup pre-aire (título, descripción, #, categoría, portada, cámara / chat de voz).
- Overlay live: regalos, quién se une, espectadores, compartir, reportar, responder comentarios; resumen al finalizar.
- Reels más fluidos: menos rebuilds por frame, cache de vídeo, miniaturas sin VideoFrame de red.
- Migración `051_live_stream_setup`.

## Alpha 3.0.5 (compilaciones de Android 66)

### Compilación 66
- Llamadas LiveKit: FCM `livekit_call` abre pantalla completa (Android notificación de llamadas + full-screen intent; iOS alerta + hint).
- Lives visibles: `active_live` en perfil (anillo EN VIVO / portada), rail «En vivo» en el feed, unirse como espectador.
- Sala live estilo TikTok: vídeo a pantalla completa, chat (DataChannel + API), likes y regalos (`context=live`).
- Migración `050_livekit_live_ux` (mensajes de live, likes/viewers, regalos en live).

## Alpha 3.0.4 (compilaciones de Android 63–65)

### Compilación 65
- Mis apps: ID y clave API visibles (ocultar con el ojito y copiar).
- Al tocar una app: HTML de «Iniciar sesión con TREVIX», pasos web/Android/iOS, ejemplo de token, política de uso, requisitos y responsabilidades.
- Regenerar clave API; las claves se guardan cifradas en el servidor para poder mostrarlas de nuevo.

### Compilación 64
- Corregido: Creador › Desarrollador ya se guarda en la base de datos (ENUM) y activa Mis apps.
- Mensaje informativo al elegir Desarrollador (como el de Artista musical).
- Desarrollador y admin ven cuántos usuarios han iniciado sesión en cada app OAuth.

### Compilación 63
- Corregido: tras personalizar Para ti al registrarse, ya no se queda cargando.
- «Creador de contenido» pasa a llamarse **Creador**; nueva categoría **Desarrollador**.
- Apps OAuth: crear app (icono, nombre, paquete o URL web, descripción), aprobación admin/mod, ID y clave API.
- Inicio de sesión con TREVIX para apps de terceros (solo foto, usuario, nombre y acceso; sin contraseñas).
- Login con **VINCRIPTAR** en app y web.

## Alpha 3.0.3 (compilaciones de Android 62)

### Compilación 62
- Bienvenida al suscribirse: tarjeta opaca, animación, sonido elegante y mensaje más claro.
- El suscriptor puede cancelar y recupera el 50 % en su monedero.
- El colaborador administra suscriptores: quitar acceso o hacer devolución completa.

## Alpha 3.0.2 (compilaciones de Android 61)

### Compilación 61
- Posts de suscriptores visibles en Para ti y perfil con banner «Suscríbete» (contenido desenfocado).
- Contenido +18 en feed, perfil y Reels con advertencia «Mirar» para mayores de edad.
- Animación de bienvenida al suscribirse a un colaborador.
- Billetera infinita para admin/moderador: compras de prueba sin acreditar ni notificar al otro usuario.

## Alpha 3.0.1 (compilaciones de Android 60)

### Compilación 60
- Colaborador: el pago de US$ 10 solo aplica si no se cumplen los requisitos; si se cumplen, la solicitud es gratis.
- Verificado al aceptar solo si la cuenta no tiene advertencias, restricciones ni otros problemas.
- Sigue el 80 % de ganancias para el colaborador.

## Alpha 3.0 (compilaciones de Android 59)

### Compilación 59
- Panel admin: diseño de usuarios y comunidades; restricción por horas/días también en web.
- Corrección del 500 del resumen de moderación (`AdminBadges`).
- Colaborador: solicitud abierta (pago único 10 USD), requisitos 500 seguidores + 100 vistas en una story (7 días), 80 % de ganancias, verificado al aceptar, impulso cada 90 días.

## Alpha 2.9 (compilaciones de Android 58)

### Compilación 58
- Textos de configuración: «comunidad» en lugar de «grupo».
- Botón Guardar en la barra superior: los cambios de configuración se aplican juntos, no uno a uno.

## Alpha 2.8 (compilaciones de Android 57)

### Compilación 57
- Pagos (Google Play, Nequi, PayPal) disponibles para todos los usuarios.
- Notificaciones al publicar en comunidades; audio se detiene al cambiar de sección o abrir un perfil.
- Enlaces PayPal bloqueados en perfiles.
- Restricciones parciales por horas/días (mensajes, posts, stories, comentarios, regalos, perfil, comunidades).
- Configuración avanzada de comunidades: reglas, quién publica, formatos, ocultar, bienvenida.

## Alpha 2.7 (compilaciones de Android 56)

### Compilación 56
- PayPal: el checkout se abre en el navegador in-app (no en la app nativa de PayPal), para poder pagar con otra cuenta distinta a la del comercio (`CANNOT_PAY_SELF`).

## Alpha 2.6 (compilaciones de Android 55)

### Compilación 55
- Compatibilidad Google Play 16 KB (NDK r28 + packaging).
- Tras registrarse: lista de personas para seguir (recomendada / cercana / FoF).
- Para ti más inteligente: seguidos, hashtags/temas, amigos de amigos y cercanía por ciudad.
- Publicar vuelve al Para ti al instante con barra de %; stories muestran el porcentaje en el avatar.

## Alpha 2.5 (compilaciones de Android 49–54)

### Compilación 54
- Ajustes: grupos expandibles (despliegan sus opciones al tocar), sin chips que recortaban el texto.

### Compilación 53
- Ajustes más limpios: lista estilo Instagram + TREVIX, grupos horizontales desplazables, buscador y aviso de confirmar correo.

### Compilación 52
- Ajustes rediseñados: hub con 11 categorías, búsqueda y accesos rápidos.
- Notificaciones correctas de like/comentario en foto de perfil y portada (texto, miniatura y apertura del visor).
- Medios PayPal/comprobante solo para moderadores y administradores; usuarios normales siguen con Google Play (y Nequi si aplica).

### Compilación 51
- Visor de foto estilo Facebook: nombre/pie abajo a la izquierda, like/comentario/compartir centrados; compartir con el sheet de posts; comentarios con hilos, reacciones, GIF/foto, reportar/eliminar/ocultar (migración `043`).

### Compilación 50
- Visor de foto de perfil: nombre legible en negro, imagen a pantalla, acciones como el feed (corazón rosa, comentario, repost) y composer de comentarios visible.

### Compilación 49
- Foto de perfil/portada: like y comentarios funcionan (rutas API, permisos y lectura de lista de comentarios).
- Se permite me gusta en la propia foto; avisos de comentario de foto ya no rompen la FK de `notifications`.

## Alpha 2.4 (compilación de Android 48)

### Compilación 48
- **LiveKit:** panel admin, API de sesiones y tokens JWT en el servidor; app con `livekit_client`, llamadas desde el chat y pantalla de sala.
- Migración `042_livekit` (`live_sessions`). Guía en `docs/LIVEKIT.md`.

## Alpha 2.3 (compilación de Android 47)

### Compilación 47
- PayPal: checkout en navegador dentro de la app; menos errores «Error interno del servidor» con recargas.
- Foto de perfil y portada: me gusta, comentarios, compartir, privacidad, pie de foto, texto alternativo y silenciar avisos de esa foto.

### Compilación 46
- Quitado el cambio de icono de la app (Ajustes › Apariencia).
- VINCRIPTAR: escáner con linterna, esquinas, destello al leer y código `XXXX-XXXX`.
- Comentarios con foto adjunta (API + app).
- Visor de foto de perfil/portada con opciones y deslizar galería del perfil.
- Historias: más fuentes y efectos de texto; pestaña Animación (pulso, rebote, etc.).
- PayPal Checkout: medio `paypal` en admin, credenciales en `config/local.php`, recarga en app.

## Alpha 2.2 (compilaciones de Android 37–45)

### Compilación 45
- **Equipo:** hub «Panel del equipo» con búsqueda, badges y todas las secciones del admin web.
- Nativo: usuarios, contenido, comunidades, auditoría, configuración; moderación (reportes, música, verificación) mejor enlazada.
- API: `badges` en `GET admin/dashboard`.

### Compilación 44
- VINCRIPTAR 2.0: QR estándar (`trevix://vincriptar/CODIGO`) + código legible `XXXX-XXXX`; escaneo con mobile_scanner (app) y jsQR (web).
- Sin anillo óptico VINCODE como método principal; TTL de enlace 90 s.
- iOS CI: copia PNG de iconos alternativos al `.app` antes de verificar.

### Compilación 43
- iOS iconos alternativos: `CFBundleIconFiles` + PNG @2x/@3x obligatorios en el `.app` (corrección de la rejilla vacía al cambiar icono).
- VINCRIPTAR: visual más limpio (anillo de enlace, sin «#»/partículas tipo QR); escaneo de cámara corregido (radio + color iOS/Android).
- App: si cierras una sesión desde Ajustes en otro dispositivo, este comprueba el token cada ~20 s y al volver al primer plano (antes podía quedar la UI abierta hasta la siguiente acción).

### Iconos, compartidos, privacidad y vinculación
- Iconos alternativos: adaptive Android sin referencia circular + `roundIcon`; PNG sueltos iOS para `setAlternateIconName`.
- Cambio de icono Android: no se desactiva el alias con el que abriste la sesión hasta cerrar la app (evita «aplicación desinstalada» y cierre forzado); diálogo para borrar accesos viejos en la pantalla de inicio.
- Cambio de icono Android (41+): activar el alias nuevo antes de desactivar los demás; sin reaplicar en cada arranque si ya coincide.
- iOS iconos alternativos: `CFBundleIconName` + appiconset completo en Assets (evita rejilla vacía al cambiar icono); PNG @2x/@3x en bundle + verificación post-build.
- Empaquetado iOS: CI falla si falta `CFBundleAlternateIcons` o PNG en Resources.
- El icono elegido en Apariencia se reaplica al arrancar solo si el lanzador no coincide.
- Contador de compartidos: suma repost + compartir externo + enviar por chat (UI local al instante).
- Privacidad de conexiones: quién ve seguidores y siguiendo (todos / seguidores / solo yo).
- **VINCRIPTAR** sustituye la vinculación por QR: el dispositivo nuevo genera un VINCODE (60 s); la cuenta iniciada escanea o introduce el código y autoriza (web, Android, iOS). UI alineada al design system (AuthBackground, Tx, anillo de escaneo).
- Sesiones con tipo de dispositivo, hora y cierre individual (app y web).


## Alpha 2.1 (compilación de Android 36)

### Chats y compartir
- Compartir a Instagram: publicación del feed (no Stories).
- Grupos: los administradores eligen quién puede enviar mensajes (todos o solo admins).
- Encuestas en los chats (crear y votar).
- Franja de activos: conectados primero y quienes se desconectaron hace menos de 24 h (`2h`, `12h`…).
- Chats cifrados: la bandeja muestra el contenido descifrado, no «Mensaje cifrado».
- Contador de mensajes enviados aún sin leer por la otra persona.
- Más fluidez en la lista de chats (animaciones y menos carga al sondear).

## Alpha 2.0 (compilación de Android 34–35)

### Corrección (compilación 35)
- Cambiar el icono en Android ya no deja la app como «desinstalada» (el lanzador usa activity-alias; MainActivity no se desactiva).
- Stickers/GIF de GIPHY: se sirven en formato GIF (no WebP animado) para que se vean en la app.

### Apariencia
- Icono de la app: original + onda, corazón, mensajes y marca (Ajustes › Apariencia y accesibilidad).
- Cinco temas de color: TREVIX (predeterminado), Océano, Atardecer, Bosque y Ember.

### Privacidad
- Bloqueo de app: Face ID (iOS), huella (Android), o PIN / patrón en ambos. Si está activo, pide verificación al abrir o volver a la app.

## Alpha 1.9 (compilación de Android 30; correcciones 31–33)

### App (compilación 33)
- «Para ti»: más variación al precargar/refrescar (misma lógica de intereses).
- Aviso al recibir me gusta en un comentario.
- Compartir post/reel con la imagen (WhatsApp, Facebook, Instagram y «Más opciones»).

### Dominio (compilación 32)
- La web y la API pasan a https://treviix.app; https://trevix.ond-s.com redirige al nuevo dominio.

### Corrección en Android (compilación 31)
- Descargar un reel, guardar una historia en video, el editor de reels y las fotos animadas cerraban la app al
  llegar al 100 % y no se guardaba nada. Ya se guardan con su marca de agua (en iPhone no pasaba).

### Chats privados
- Esconde los chats que quieras detrás de un PIN de 4 a 8 números: mantén pulsado un chat y toca «Privado» (en la
  web, «Mover a chats privados» en las opciones del chat).
- No salen en la bandeja, la búsqueda ni el contador de mensajes. Para verlos, escribe tu PIN en el buscador de los
  chats. Se vuelven a esconder al salir de la lista o si la app pasa más de un minuto en segundo plano.
- Sus avisos son discretos: solo «TREVIX · Tienes un mensaje nuevo», sin nombre, foto ni «Responder».
- Ajustes › Chats privados: crear o cambiar el PIN, exportar (un .txt con todos los mensajes, también los cifrados),
  vaciar y desactivar.
- ¿Olvidaste el PIN? Con la contraseña de tu cuenta puedes exportarlos; después se vacían y creas un PIN nuevo,
  como en los chats ocultos de WhatsApp.

## Alpha 1.8 (compilación de Android 29)

### Editor de video de reels
- Al terminar de grabar (o al elegir un video) se abre el editor: textos con fuentes, efectos y colores, emojis y
  stickers animados que se mueven, giran y agrandan con los dedos.
- Cada texto, emoji o sticker puede verse solo en una parte del video («Duración en el video»).
- Filtros y efectos: viñeta, cine, VHS, grano, destellos, corazones, luz cálida y marco.
- «Siguiente» graba todo en el video y abre la publicación para escribir la descripción.

### Fotos animadas
- En la galería de la cámara de reels, «Fotos»: elige hasta 8 y publícalas como reel en movimiento, en bucle o
  estáticas, de 2 a 8 segundos cada una. Quita fotos con la ✕ y añade más con «+».

### Publicar desde otras apps
- Android: comparte fotos, videos o enlaces con TREVIX desde cualquier app y elige historia, publicación o reel.
- iPhone: «Abrir en TREVIX» en fotos y videos (por ejemplo desde Archivos).

## Alpha 1.7 (compilación de Android 28)

### Países
- Todos los países del mundo (con Panamá) con su bandera, y un buscador para encontrarlos rápido en el perfil.

### Historias
- Collage: elige de 2 a 6 fotos, cambia el diseño, toca una foto para cambiarla, encuadrarla o quitarla, y ajusta
  bordes y esquinas.
- 11 fuentes y 9 efectos para los textos (fondo, suave, neón, contorno, sombra, 3D, glitch y degradado).
- La historia se sube en segundo plano con su progreso en tu círculo de la barra; si falla, queda en Borradores.
- Al descargar una historia se guarda como se publicó: con su canción, textos, stickers y filtro (también las fotos
  en movimiento).

### Reels
- Los grabados en 4:5 se ven en 4:5 desde la vista previa.
- Más luz con el flash: linterna al máximo y, con la cámara frontal, la pantalla al máximo brillo y un aro de luz
  más amplio.

### Música
- Las canciones se guardan en el teléfono y la siguiente se precarga: suenan al instante y sin cortes.

### Enviar por mensaje
- Comparte publicaciones y reels en tus chats (también en grupos y chats cifrados) desde «Compartir», con un
  mensaje opcional. En la web, desde el menú de la publicación.

### Avisos
- Tonos propios, suaves y elegantes para los mensajes y para la actividad.
- En Android los mensajes llegan antes: el aviso trae el mensaje y se muestra sin una consulta extra.

## Alpha 1.6 (compilación de Android 27)

### Feed y reels que aprenden lo que te gusta
- «Para ti» muestra primero lo que acabas de publicar (6 horas), después lo nuevo (48 horas) de tus intereses y
  luego el resto ordenado por afinidad, interacción y frescura.
- La IA (Gemini) clasifica cada publicación en temas (texto, hashtags y hasta 3 imágenes o la portada del video) y,
  una vez al día por persona, predice qué otros temas te van a gustar a partir de lo que te gustó. Feed y reels
  usan esos temas y predicciones además de los hashtags.

### «No me importa»
- En el menú de las publicaciones y de los reels de otras personas. Quita la publicación de tu feed (con
  «Deshacer») y resta peso a sus temas y hashtags para que veas menos contenido así.

### Contenido para adultos
- Quien publica puede marcarlo como +18 y la IA lo detecta si no se marcó. Solo lo ven los mayores de 18 años según
  su fecha de nacimiento (en el feed, los reels, los perfiles, la búsqueda y los enlaces). Lleva la etiqueta «+18».

### Encuestas
- Nueva publicación con pregunta y de 2 a 4 respuestas, de 1, 3 o 7 días. Un voto por persona; los resultados se
  ven después de votar o al terminar.

### Comentarios
- Me gusta y No me gusta en cada comentario (y en sus respuestas).

### Música
- Las fotos y textos con canción ya no muestran la tarjeta abajo: el nombre va bajo el autor y la canción suena sola
  mientras la publicación está a la vista, con un botón para silenciar la música de todas las publicaciones.
- Los reels del feed ya no muestran su música abajo: se escucha en Reels.
- Reels: los botones de sonido y cámara vuelven al borde derecho de la barra superior.

## Alpha 1.5 (compilación de Android 26)

### Sonidos de los reels
- Los reels con su propio audio publican un «Sonido original» en la biblioteca de música para que otras personas lo
  usen. No aparece en el perfil de quien lo creó (ni como artista ni como usuario): solo en el reel y en la biblioteca.
- Tocar el sonido de un reel abre su página: nombre, portada y los videos que lo usan (en rejilla; al tocar uno se
  reproducen en Reels en ese orden).
- Quien creó el reel puede cambiar el nombre del sonido y ponerle una portada (o quitarla) desde esa página.

### Listas de reproducción (creadores de contenido)
- Las cuentas de creador de contenido pueden crear listas de reproducción con sus reels. Se ven en la pestaña
  «Listas» del perfil, que reemplaza a «Hilos». Al reproducir desde la lista, los videos van en el orden en que se
  agregaron a la lista.
- Los reels se agregan desde el menú «⋯» del reel o de la publicación («Agregar a una lista»).
- Las cuentas de creador de contenido ya no publican hilos (la web, la app y el servidor lo impiden).

### «Para ti» según tus intereses
- El feed «Para ti» se ordena por los hashtags de lo que comentas, te gusta, guardas, compartes o ves durante un rato
  (8 s o más), además de la interacción, la frescura y las cuentas que sigues.

### Visualizaciones
- Cada publicación muestra a su autor cuántas personas la vieron (ícono de ojo). Nadie más ve ese número.

### Avisos push
- Mensajes, reacciones, comentarios, menciones, seguidores y avisos de TREVIX llegan al instante aunque la app esté
  cerrada, por Firebase Cloud Messaging (Android e iPhone), sin el aviso fijo de Android ni gasto extra de batería.
- Desde el panel se pueden enviar avisos a una persona o a todos los teléfonos.
- Si el teléfono no puede usar Firebase, la app sigue avisando como antes.

## Alpha 1.4 (compilación de Android 25)

### Descargar historias completas
- Historias › Descargar guarda lo que se publicó: el video o la foto con su canción (desde el punto elegido), los
  textos, stickers y el filtro. Una foto con canción se guarda como video con la duración de la historia; una foto
  sin canción, como imagen. El video sin canción conserva su propio audio.
- El plugin `trevix_video` acepta una imagen como entrada (`imageMs`) y encuadre sin recorte (`contain`, con franjas
  negras); el filtro se aplica antes del encuadre.

### Formato del texto al publicar
- Negrita, cursiva y viñetas en el compositor de la app y de la web. Se guardan como texto plano: `**negrita**`,
  `*cursiva*` y líneas con «• » (también «- » o «* » al inicio de línea). Lo muestran las publicaciones, comentarios,
  respuestas y biografías; el chat no. Los extractos (notificaciones, compartir) van sin marcas.

### Reels
- El sonido se muestra como en TikTok: nombre de la canción y artista (o «Sonido original · @usuario») que se desplaza
  si no cabe, y un disco giratorio con la portada. Tocarlos abre la pantalla del sonido.

### Correcciones
- Al cambiar el @usuario, el perfil propio ya no muestra «No encontramos a @anterior»: se recarga con el nuevo.
- Perfil: los botones Mensaje, Campana y Regalo ya no se montan sobre el nombre.
- Descargas: la app ya no se cierra ni queda en blanco al terminar una descarga. El aviso de progreso se cierra por
  sí mismo (no con «volver»), los menús no se cierran dos veces y, si la pila de pantallas queda vacía, la app vuelve
  al inicio en lugar de salir.

## Alpha 1.3 (compilación de Android 24)

### Cámara de reels
- Formato de grabación: pantalla completa (9:16) o 4:5. En 4:5 la vista previa oscurece lo que queda fuera del marco
  y el video final se recorta a 4:5.
- Efectos de cara como los de TikTok: gafas, gato, conejo, corona, corazones, rubor, pecas y bigote. Siguen la
  cara en la vista previa y quedan grabados en el video. Correcciones: filtro Rejuvenecer (ya existente), rubor y
  pecas. No hay deformación de la cara (afinar, ojos grandes).
- La detección de caras es del propio teléfono (Vision en iOS y el detector del sistema en Android), sin ML Kit ni
  Firebase. iOS sigue pidiendo 14.0.
- Plugin nativo nuevo `mobile/packages/trevix_video` (Media3 Transformer en Android, AVFoundation en iOS): recorta,
  aplica filtros, superpone imágenes animadas, añade un cierre y cambia el audio.

### Sonido original
- Un video público con su propio sonido (sin canción) registra un «Sonido original» a nombre de quien lo publica.
- Desde la pantalla del sonido: grabar un reel, usarlo en una historia, una nota o una publicación, o ponerlo en el
  perfil. También enlaza al video original.

### Borradores
- Perfil propio › Borradores: publicaciones, reels e historias guardados en el teléfono como borrador.

### Perfil y Guardado
- Las pestañas del perfil (Publicaciones, Exclusivas, Hilos, Multimedia, Música y Guardado) son iconos.
- Guardado tiene 3 categorías: Guardado (publicaciones y reels), Solo yo (publicaciones, reels e historias
  privadas; las historias «Solo yo» no se borran a las 24 horas) y Me gusta.

### Descargar reels
- Reels › Compartir › Descargar: el video se guarda con la marca de agua de TREVIX y @usuario (cambia de esquina a
  mitad del video), el filtro y la canción si se grabó con ella, y un cierre de 3 s con el logo, @usuario y la web.

## Alpha 1.2 (compilación de Android 23)

### Historias
- Nuevo creador: al abrirlo se ve la galería del teléfono dentro de la app (álbumes, duración de los videos, fotos
  en movimiento con la etiqueta LIVE), con una casilla para la cámara y el selector del sistema como alternativa.
  Si no hay permiso de Fotos, ofrece abrir los ajustes o elegir con el selector del sistema.
- Fotos en movimiento (Live Photos de iPhone y fotos en movimiento de Android, JPEG con el video incrustado): se
  pueden publicar como foto o como foto en movimiento (se reproduce en bucle, sin sonido, con la etiqueta LIVE en
  la app y en la web). Campo `live` de la API (migración `028_camara_reels_historias_live.sql`).
- Descargar una historia: solo quien la publica (app: menú y botón de la barra inferior; web: botón de descarga).
  En la app, los videos se guardan tal cual y las fotos con sus textos, stickers y filtro.
- Filtros nuevos en historias y reels: Rejuvenecer (suaviza la piel y da luz), Brillo, Rosa, Neón y Noir.

### Reels
- «Reel» (menú Crear y pantalla Reels) abre una cámara propia como la de TikTok:
  - Duración de 15 s, 30 s o 1 min, con barra de progreso por tramos; tocar el botón pausa y reanuda.
  - Música: con una canción elegida la cámara graba sin micrófono (ni la música ni el sonido de fuera entran en
    el video) y la canción suena a su compás al grabar, en la vista previa, en Reels y en la web (`song_sync`).
  - Cambiar de cámara, flash (linterna en la trasera; aro de luz en pantalla con la delantera), cuenta regresiva de
    3 a 10 s, filtros en vivo.
  - A la izquierda del botón de grabar está el botón para elegir un video de la galería.
  - Vista previa con cambio de filtro y «Siguiente» al compositor, que publica el filtro (`filter`) y la
    sincronización. El filtro se ve en Reels, el feed, el visor de fotos y la web.

### Otros
- Ajustes › Acerca de muestra la versión (Alpha 1.2).
- Permisos nuevos de Android: cámara y fotos/videos (Android 13+ con acceso parcial de Android 14).
