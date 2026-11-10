# TREVIX para iOS y Android (Flutter)

App nativa de TREVIX para iPhone y Android, con el mismo código, diseño y funciones en los dos. Usa la API REST v1 de `https://trevix.ond-s.com/api/v1/` (referencia en
[`../docs/API.md`](../docs/API.md)) con los mismos permisos, validaciones y límites que la web: no hay datos de
ejemplo; todo lo que se ve viene del servidor.

## Compilar e instalar (GitHub Actions + ESign)

No hace falta un Mac ni el SDK de Flutter en el equipo:

1. Sube el repositorio a GitHub (rama `main` o `master`).
2. Cada `push` que toque `mobile/` lanza el flujo **App iOS** (`.github/workflows/ios.yml`). También se puede lanzar a
   mano desde *Actions → App iOS → Run workflow* (opcionalmente con una versión fija de Flutter).
3. El flujo genera la carpeta `ios/` si no existe, instala las dependencias, crea el icono, configura `Info.plist`
   (nombre TREVIX; textos de permisos de Fotos, Cámara, Micrófono, Ubicación y Contactos; solo vertical; iOS 14+, que exige `fc_native_video_thumbnail` 3.x: la 4.x pediría iOS 16),
   ajusta `AppDelegate.swift` para mostrar avisos con la app abierta, revisa el código con `flutter analyze`,
   abre la app en un simulador de iPhone y comprueba que sigue abierta a los 30 s (si se cierra, el flujo falla y no
   publica nada; la captura y el informe del cierre quedan en el artefacto `prueba-simulador-N`), y compila sin
   firmar.
   Los plugins deben ser compatibles con las escenas de iOS (`SceneDelegate`, plantilla actual de Flutter): por eso
   `flutter_contacts` va en la versión 2.x, porque la 1.x cerraba la app al arrancar.
4. El resultado `TREVIX.ipa` queda como artefacto del flujo y como *pre-release* `ios-build-N` en **Releases**.
5. En el iPhone: abre la Release desde Safari, descarga `TREVIX.ipa`, «Abrir con ESign» → Firmar → Instalar.

Si un paso falla, el registro del flujo indica el archivo y la línea (`flutter analyze` se ejecuta antes de compilar).

## Android (compilación local con Flutter, APK y AAB firmados)

GitHub Actions solo compila iOS. Android se compila en Windows con `android_overrides/build-android.ps1`:

```powershell
$env:TREVIX_KEYSTORE = 'C:\ruta\trevix-release.jks'
$env:TREVIX_KEYSTORE_PASSWORD = '...'
.\mobile\android_overrides\build-android.ps1 -BuildNumber 6   # siempre mayor que la anterior
```

Requisitos: Flutter estable (`%USERPROFILE%\dev\flutter`), Android Studio (su `jbr` es el JDK) y el SDK de Android con
`cmdline-tools` (Flutter los usa para quitar los símbolos de depuración del AAB).

El script copia `mobile/` a `%USERPROFILE%\dev\trevix-mobile`, porque Gradle y el NDK fallan con espacios en la ruta, y:

1. Genera `android/` con `flutter create` (solo la primera vez) y copia encima `android_overrides/app`:
   - `AndroidManifest.xml`: nombre TREVIX, permisos, enlaces `trevix://` y `https://trevix.ond-s.com/...` (App Links)
     y las apps a las que se comparte.
   - Pantalla de arranque oscura e icono de los avisos (`ic_stat_trevix`).
   - `kotlin/com/ondsc/trevix/`: `MainActivity` (canal `trevix/push`), `PushService`, `Push` y `PushReceiver`: los
     avisos al instante (ver abajo).
2. `configure_gradle.py`: minSdk 23 como mínimo (hoy Flutter exige 24, Android 7.0+), desugaring (lo pide
   `flutter_local_notifications`), plugins compilados contra el SDK 36 y firma de release con la clave de TREVIX.
3. Icono adaptable (`flutter_launcher_icons_android.yaml`), `flutter analyze`, y compila `TREVIX.apk` (instalación
   directa) y `TREVIX.aab` (Google Play), que deja en el escritorio.

La clave de firma nunca va en el repositorio. Con la misma firma, cada APK nuevo se instala encima del anterior sin
perder la sesión.

El tema fuerza el comportamiento de iOS (`platform: TargetPlatform.iOS`): rebote al desplazar, volver deslizando
desde el borde y selección de texto iguales que en el iPhone. El botón «atrás» de Android vuelve a la pantalla
anterior y, en el inicio, a la primera pestaña antes de salir.

La huella SHA-256 del certificado está en `config/app.php` (`app.android.sha256`) y se publica en
`/.well-known/assetlinks.json` para que Android abra los enlaces del sitio en la app.

### Avisos al instante (sin Firebase)

- `PushService` es un servicio en primer plano de tipo `remoteMessaging` con un aviso fijo y silencioso («Conexión
  en segundo plano»). Consulta `GET me/push` cada 20 s con la pantalla encendida y cada minuto con la pantalla
  apagada; también al encender la pantalla.
- Con el teléfono dormido lo despierta una alarma (`setAndAllowWhileIdle`). En reposo profundo (Doze) Android la
  espacia hasta unos minutos, sobre todo si TREVIX tiene la optimización de batería activa (Ajustes ›
  Notificaciones › Uso de batería).
- Notificaciones:
  - Una por chat, con los últimos mensajes, la foto de quien escribe y las acciones «Responder» (envía desde la
    notificación) y «Marcar como leído».
  - Una por cada aviso de actividad (me gusta, comentarios, menciones, seguidores, solicitudes, comunidades y
    avisos de TREVIX) y por cada reacción a tus mensajes.
  - Tocarlas abre la pantalla con `trevix://open/<link>` (`lib/core/deeplinks.dart`).
- Canales: «Mensajes», «Actividad» y «Conexión en segundo plano».
- Se inicia al entrar con el permiso de notificaciones concedido (`BackgroundNotices.start`, `lib/core/push.dart`)
  y se reanuda al reiniciar el teléfono o actualizar la app.
- Se detiene al cerrar sesión (borra el token guardado), con un 401 o desde Ajustes › Notificaciones › «Avisos
  al instante». Si se desactiva, vuelve la revisión periódica de WorkManager.
- No avisa del chat abierto en pantalla. Abrir un chat o la pestaña de notificaciones quita sus avisos.
- Google Play pide declarar el uso del servicio en primer plano «Mensajería remota» (Contenido de la app →
  Servicios en primer plano), con una descripción y un video corto de la función.

## Desarrollo local (opcional)

```bash
cd mobile
flutter create --platforms=ios --org com.ondsc --project-name trevix .   # solo la primera vez
flutter pub get
flutter run --dart-define=TREVIX_SITE=https://trevix.ond-s.com/
```

`TREVIX_SITE` permite apuntar la app a otro servidor (con la barra final).

## Estructura (`lib/`)

| Carpeta / archivo | Contenido |
|---|---|
| `main.dart`, `app.dart` | Arranque, tema, español y la puerta: splash → bienvenida (solo la primera vez) → acceso → inicio |
| `core/theme.dart`, `core/appearance.dart` | Paletas oscura y clara (y sus variantes de alto contraste) y las preferencias de Apariencia y accesibilidad: tema del sistema / claro / oscuro, tamaño de texto, negrita, reducir movimiento y aumentar contraste. Se guardan en el teléfono y se aplican al instante. Las historias, la bienvenida y el visor de fotos son siempre oscuros (`TxDark`) |
| `core/` | Cliente HTTP (`api.dart`), sesión y token en el llavero (`session.dart`), listas paginadas, reproductor de música único, navegación, avisos y hojas, catálogos, tema y formatos |
| `models/models.dart` | Objetos de la API: usuario, perfil, publicación, comentario, canción, aviso, conversación, mensaje, historia, comunidad… |
| `widgets/` | Logo, avatar con anillo de historias, botones, tarjeta de publicación, galería y video, chips de canción, reporte, listas paginadas |
| `widgets/tx_icon.dart` | Iconos SVG propios (`TxIcon` / `TxGlyph`, trazos de Lucide con variantes rellenas) para la barra inferior, cabecera, acciones de publicación, menú «Crear», intro y estados vacíos. El resto de iconos usa `CupertinoIcons` (paquete `cupertino_icons`, necesario para que no salgan como «?») |
| `screens/intro/` | Bienvenida animada de 4 pantallas (se muestra una vez; se puede repetir desde Ajustes) |
| `screens/auth/` | Iniciar sesión, crear cuenta y recuperar contraseña |
| `screens/home/` | Barra inferior de vidrio (Inicio, Explorar, Crear, Actividad, Perfil) y menú de creación (publicación, hilo, historia, reel, nota…; «Subir canción» solo aparece en cuentas de artista) |
| `screens/feed/`, `screens/stories/` | Inicio con pestañas y avisos · barra de historias con las notas encima de cada avatar, visor (nota del autor, reacciones con emoji, quién reaccionó en «Vistas») y creación de historias (texto o foto/video, con canción; las capas se seleccionan y se agrandan o giran con el tirador de la esquina, la barra lateral de tamaño o dos dedos) |
| `screens/notes/`, `widgets/note_bubble.dart` | Notas de 6 horas (nube `NoteCloud`): ver, responder por mensaje, publicar con público (seguidores, amigos o mejores amigos) y eliminar (`note_sheets.dart`); lista de mejores amigos (`close_friends_screen.dart`, también en Ajustes) |
| `screens/post/` | Compositor (publicación, hilo, compartir, editar; fotos, video, canción, comunidad) y detalle con comentarios. Los hilos solo llevan texto e imágenes (la barra oculta video, GIF, música, mención, ubicación, acontecimiento y evento). El video se comprueba antes de subirlo (5 minutos y 300 MB como máximo) y se sube con su miniatura, creada en el teléfono con `fc_native_video_thumbnail` |
| `screens/reels/` | Reels a pantalla completa (`reels_screen.dart`): todos los videos publicados, deslizando hacia arriba para ver más (`GET reels` con semilla por sesión). Se abre desde el icono de la cabecera del inicio, al tocar un video de una publicación o de Explorar (empieza por ese video) y desde «Crear → Reel». Videos verticales a pantalla completa y horizontales encajados sobre su miniatura difuminada; tocar pausa, doble toque da «Me gusta», barra de progreso arrastrable, sonido on/off, comentar, compartir, seguir y menú. Solo se carga el video visible y sus vecinos |
| `screens/explore/` | Búsqueda (personas por nombre, usuario, ciudad o intereses con el motivo; publicaciones, etiquetas, comunidades), recientes (`core/recent_searches.dart`, solo en el teléfono), «Personas que quizá conozcas» con «No me interesa» (`suggestions_screen.dart`), tendencias y etiquetas |
| `screens/notifications/` | Avisos (todas / menciones) y solicitudes de seguimiento; los del sistema (advertencias, verificado) aparecen como «TREVIX» |
| `screens/profile/` | Perfil (con nota, canción, ciudades, enlaces e «Información»), editar perfil (foto, portada, tipo de cuenta, música del perfil), datos personales y seguidores / seguidos |
| `screens/messages/` | Bandeja estilo Messenger (`inbox_screen.dart`: activos, filtros Todos / No leídos / Grupos), chat con sondeo cada 4 s (`chat_screen.dart`, burbujas en `chat_bubble.dart`, colores en `chat_style.dart`): imágenes, notas de voz, GIF y stickers, ubicación, «Visto» con avatares, reacciones, deslizar para responder, reenviar (`forward_screen.dart`, vuelve a cifrar los cifrados), destacar o fijar, eliminar, buscar en el chat (`chat_search_screen.dart`), mensajes temporales. Editor de foto antes de enviar con fuentes, dibujo, emojis, stickers y visualización única (`photo_editor.dart`, `view_once_viewer.dart`). Información del chat (`chat_info_screen.dart`), grupos: crear, ajustes del administrador, miembros, solicitudes, unirse por enlace y grupos públicos (`group_screens.dart`). Contenido enviado y almacenamiento del chat y de Ajustes (`chat_storage_screens.dart`). PIN, código de seguridad y ajustes del cifrado (`e2ee_screens.dart`) |
| `core/e2ee.dart`, `core/chat_sender.dart`, `core/chat_media.dart` | Cifrado de extremo a extremo (X25519, AES-256-GCM y HKDF del paquete `cryptography`; clave privada en el llavero con copia protegida por PIN), envío de mensajes cifrados o normales según el chat, y caché de fotos y notas de voz de los chats (descifradas) en el teléfono |
| `widgets/emoji_text.dart`, `widgets/emoji_picker.dart` | Emojis que se ven completos en textos (Reels, publicaciones, mensajes de solo emojis en grande) y selector de emojis con recientes |
| `screens/music/` | Biblioteca (TREVIX, Audius y Free To Use), ficha con reproductor, selector de canción y panel del artista con subida de canciones |
| `core/device.dart` | Permisos del iPhone y lo que hace cada uno: avisos locales, país por ubicación, contactos, guardar en Fotos y micrófono |
| `widgets/gif_picker.dart` | Buscador de GIF y stickers de GIPHY (a través del servidor) |
| `screens/settings/permissions_screen.dart` | Permisos (también se muestra una vez después de iniciar sesión) e invitar contactos por SMS |
| `screens/communities/` | Descubrir y mis comunidades, ficha, crear y editar, miembros, solicitudes, vetos y moderadores |
| `screens/settings/` | Ajustes: cuenta, contraseña, sesiones, verificación (requisitos y solicitud, `verification_screen.dart`), estado de la cuenta (advertencias, `account_status_screen.dart`), privacidad, avisos, apariencia y accesibilidad, bloqueados, guardados, legales, desactivar y eliminar |
| `screens/admin/` | Moderación para el equipo: resumen, cola de reportes con decisión (incluida «Advertir al autor»), revisión de canciones y, para administradores, solicitudes de verificado. «Advertir (equipo)» en el menú de un perfil |

## Permisos

| Permiso | Para qué se usa |
|---|---|
| Notificaciones | Avisos de mensajes y notificaciones nuevas (detectados con el sondeo de `me/counts`) |
| Micrófono | Notas de voz en los chats (M4A, hasta 2 minutos) |
| Fotos | Guardar en la galería las imágenes del visor (elegir fotos usa el selector del sistema, sin permiso) |
| Ubicación (solo en uso) | «Detectar mi país» en Editar perfil y enviar la ubicación en un chat |
| Contactos | Invitar contactos por SMS; los contactos no salen del teléfono |

Cada uno se pide al usarlo por primera vez o desde Ajustes → Dispositivo → Permisos. Si se rechazó, el botón abre
los Ajustes del iPhone.

## Pendiente

- Notificaciones push (APNs): necesitan una cuenta de Apple Developer de pago y firmar la app con ella (una app
  instalada con ESign no puede recibirlas). Mientras tanto la app usa sondeo de `me/counts` cada 45 s, igual que la
  web, y muestra avisos locales cuando suben los contadores.
- Enlaces universales (`apple-app-site-association`) cuando exista un Team ID de Apple.
- Gestión de cuentas, comunidades, configuración y auditoría del panel de administración: se abren en el panel web
  desde Moderación → icono de globo.
