# TREVIX para iOS (Flutter)

App nativa de TREVIX para iPhone. Usa la API REST v1 de `https://trevix.ond-s.com/api/v1/` (referencia en
[`../docs/API.md`](../docs/API.md)) con los mismos permisos, validaciones y límites que la web: no hay datos de
ejemplo; todo lo que se ve viene del servidor.

## Compilar e instalar (GitHub Actions + ESign)

No hace falta un Mac ni el SDK de Flutter en el equipo:

1. Sube el repositorio a GitHub (rama `main` o `master`).
2. Cada `push` que toque `mobile/` lanza el flujo **App iOS** (`.github/workflows/ios.yml`). También se puede lanzar a
   mano desde *Actions → App iOS → Run workflow* (opcionalmente con una versión fija de Flutter).
3. El flujo genera la carpeta `ios/` si no existe, instala las dependencias, crea el icono, configura `Info.plist`
   (nombre TREVIX; textos de permisos de Fotos, Cámara, Micrófono, Ubicación y Contactos; solo vertical; iOS 13+),
   ajusta `AppDelegate.swift` para mostrar avisos con la app abierta, revisa el código con `flutter analyze` y
   compila sin firmar.
4. El resultado `TREVIX.ipa` queda como artefacto del flujo y como *pre-release* `ios-build-N` en **Releases**.
5. En el iPhone: abre la Release desde Safari, descarga `TREVIX.ipa`, «Abrir con ESign» → Firmar → Instalar.

Si un paso falla, el registro del flujo indica el archivo y la línea (`flutter analyze` se ejecuta antes de compilar).

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
| `main.dart`, `app.dart` | Arranque, tema oscuro, español y la puerta: splash → bienvenida (solo la primera vez) → acceso → inicio |
| `core/` | Cliente HTTP (`api.dart`), sesión y token en el llavero (`session.dart`), listas paginadas, reproductor de música único, navegación, avisos y hojas, catálogos, tema y formatos |
| `models/models.dart` | Objetos de la API: usuario, perfil, publicación, comentario, canción, aviso, conversación, mensaje, historia, comunidad… |
| `widgets/` | Logo, avatar con anillo de historias, botones, tarjeta de publicación, galería y video, chips de canción, reporte, listas paginadas |
| `widgets/tx_icon.dart` | Iconos SVG propios (`TxIcon` / `TxGlyph`, trazos de Lucide con variantes rellenas) para la barra inferior, cabecera, acciones de publicación, menú «Crear», intro y estados vacíos. El resto de iconos usa `CupertinoIcons` (paquete `cupertino_icons`, necesario para que no salgan como «?») |
| `screens/intro/` | Bienvenida animada de 4 pantallas (se muestra una vez; se puede repetir desde Ajustes) |
| `screens/auth/` | Iniciar sesión, crear cuenta y recuperar contraseña |
| `screens/home/` | Barra inferior de vidrio (Inicio, Explorar, Crear, Actividad, Perfil) y menú de creación |
| `screens/feed/`, `screens/stories/` | Inicio con pestañas y avisos · barra, visor y creación de historias (texto o foto/video, con canción) |
| `screens/post/` | Compositor (publicación, hilo, compartir, editar; fotos, video, canción, comunidad) y detalle con comentarios |
| `screens/explore/` | Búsqueda (personas, publicaciones, etiquetas, comunidades), tendencias y etiquetas |
| `screens/notifications/` | Avisos (todas / menciones) y solicitudes de seguimiento |
| `screens/profile/` | Perfil, editar perfil (foto, portada, tipo de cuenta) y seguidores / seguidos |
| `screens/messages/` | Bandeja, chat con sondeo cada 4 s, imágenes, notas de voz, GIF y stickers, «Visto», silenciar y nuevo mensaje |
| `screens/music/` | Biblioteca (TREVIX, Audius y Free To Use), ficha con reproductor, selector de canción y panel del artista con subida de canciones |
| `core/device.dart` | Permisos del iPhone y lo que hace cada uno: avisos locales, país por ubicación, contactos, guardar en Fotos y micrófono |
| `widgets/gif_picker.dart` | Buscador de GIF y stickers de GIPHY (a través del servidor) |
| `screens/settings/permissions_screen.dart` | Permisos (también se muestra una vez después de iniciar sesión) e invitar contactos por SMS |
| `screens/communities/` | Descubrir y mis comunidades, ficha, crear y editar, miembros, solicitudes, vetos y moderadores |
| `screens/settings/` | Ajustes: cuenta, contraseña, sesiones, privacidad, avisos, bloqueados, guardados, legales, desactivar y eliminar |
| `screens/admin/` | Moderación para el equipo: resumen, cola de reportes con decisión y revisión de canciones |

## Permisos

| Permiso | Para qué se usa |
|---|---|
| Notificaciones | Avisos de mensajes y notificaciones nuevas (detectados con el sondeo de `me/counts`) |
| Micrófono | Notas de voz en los chats (M4A, hasta 2 minutos) |
| Fotos | Guardar en la galería las imágenes del visor (elegir fotos usa el selector del sistema, sin permiso) |
| Ubicación (solo en uso) | «Detectar mi país» en Editar perfil |
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
