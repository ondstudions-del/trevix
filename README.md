# TREVIX

Red social web que combina contenido visual (fotos, videos, historias) y conversacional (hilos, debates, comunidades).
Logo oficial: `#`. Lema: **Conecta. Comparte. Descubre.**

> **Estado actual: Fases 1 a 7 completadas** (cuentas; publicaciones con texto, imágenes, video, hilos, feed real
> con paginación, me gusta, comentarios, compartir, guardar y hashtags; seguir, solicitudes, perfiles privados,
> bloqueos, búsqueda de personas y publicaciones, y sugerencias; notificaciones reales con menciones y mensajería
> privada con imágenes, «Visto», estado en línea y privacidad de mensajes; historias de 24 horas con foto, video o
> texto, vistas y respuestas por mensaje; comunidades públicas y privadas con solicitudes, roles, moderación y
> publicaciones propias; reportes de cualquier contenido y panel de administración con moderación, cuentas,
> comunidades, configuración general y auditoría), más la **API REST v1** para las apps de iOS y Android
> (referencia en [`docs/API.md`](docs/API.md)) y **creadores de contenido con biblioteca de música**: cuentas de
> creador (Artista musical, Influencer, Blogger u Otro), envío de canciones por los artistas con revisión del
> equipo, y canciones en publicaciones, historias y mensajes. Los hilos salen mezclados en el inicio (sin sección
> Threads aparte).
> En producción en [trevix.ond-s.com](https://trevix.ond-s.com); API en `https://trevix.ond-s.com/api/v1/`.
> App de iOS en Flutter en [`mobile/`](mobile/README.md): se compila en GitHub Actions y se instala con ESign.
> El inventario de archivos creados y pendientes está en [`docs/ESTADO.md`](docs/ESTADO.md).

---

## Stack

| Capa | Tecnología |
|------|------------|
| Frontend | HTML5, CSS3 (variables, grid, `:has()`), JavaScript Vanilla (sin dependencias) |
| Backend | PHP 8.3+ (probado en 8.4), PDO |
| Base de datos | MySQL 8 / MariaDB 10.6+ (`utf8mb4_unicode_ci`) |
| Servidor | Apache 2.4 con `mod_rewrite` y `mod_headers` |
| Iconos | Lucide (SVG autoalojados en `assets/icons/`, insertados en línea con `icon()`) |
| Fuentes | Variables, autoalojadas en `assets/fonts/` (sin CDN, compatible con la CSP) |

Extensiones PHP requeridas: `pdo_mysql`, `mbstring`, `fileinfo`, `gd` (procesado de imágenes desde la Fase 3).

## Instalación

### 1. Base de datos

```bash
mysql -u root -p < database/trevix_db.sql
```

El script crea la base `trevix_db` y todas las tablas. Es idempotente (`CREATE TABLE IF NOT EXISTS`). No inserta usuarios
de prueba: tras registrar la primera cuenta (Fase 2), se promueve a administrador con:

```sql
UPDATE trevix_db.users SET role = 'admin' WHERE username = 'tu_usuario';
```

Si la base se creó con una versión anterior, aplica las migraciones de `database/migrations/` en orden
(`005_mensajes_notificaciones.sql` al pasar a la Fase 5, `006_historias_comunidades.sql` al pasar a la Fase 6,
`007_administracion.sql` al pasar a la Fase 7 y `008_api_tokens.sql` al añadir la API para las apps).

Para nombrar moderadores o más administradores después, usa el panel: Administración → Usuarios → ficha de la cuenta.

### 2. Configuración

Copia `config/local.example.php` a `config/local.php` y ajusta credenciales y entorno. `local.php` está en `.gitignore`.
También se pueden usar variables de entorno: `TREVIX_ENV`, `TREVIX_DEBUG`, `TREVIX_URL`, `TREVIX_DB_HOST`,
`TREVIX_DB_PORT`, `TREVIX_DB_NAME`, `TREVIX_DB_USER`, `TREVIX_DB_PASS`, `TREVIX_MAIL_DRIVER`, `TREVIX_MAIL_FROM`
y `TREVIX_SMTP_*`.

En producción: `env = production` (desactiva el modo vista previa y los mensajes de depuración) y HTTPS obligatorio.

**Correo** (`app.mail`): `log` escribe los correos en `storage/logs/mail.log` (desarrollo, para abrir los enlaces de
verificación y recuperación); `mail` usa la función `mail()` del servidor; `smtp` se conecta a un buzón con usuario y
contraseña (SSL en el 465 o STARTTLS en el 587). El remitente debe ser una dirección del dominio del sitio.

### 3. Servidor

**Apache (XAMPP, Laragon, hosting):** apunta el `DocumentRoot` (o una subcarpeta) a la raíz del proyecto.
El `.htaccess` raíz bloquea carpetas internas y archivos sensibles; `uploads/.htaccess` impide ejecutar código subido.
La aplicación detecta automáticamente si está en una subcarpeta (`http://localhost/trevix/`).

**Servidor integrado de PHP (desarrollo):**

```bash
php -S localhost:8000 router.php
```

`router.php` replica las restricciones del `.htaccess`, que el servidor integrado no lee.

## Modo vista previa

Mientras `preview_mode` esté activo y el entorno no sea `production`, las páginas muestran contenido de demostración
(`app/Data/DemoData.php`) para recorrer el diseño sin base de datos. Reglas que garantizan que nada aparente funcionar
sin lógica real:

- Todo control que depende del backend se renderiza deshabilitado con `pending(N)`, que añade el tooltip
  «Disponible en la Fase N».
- El servidor rechaza cualquier `POST` a esas funciones con **503** (tras validar CSRF), aunque se manipule el HTML.
- Un aviso global indica que se está en vista previa.
- Con sesión real, los controladores no usan datos de demostración: devuelven listas vacías y estados vacíos hasta
  que su fase conecte la consulta real.

Lo que **sí funciona de verdad** en la Fase 1: navegación y filtros por `GET` (pestañas del feed, exploración,
perfil, notificaciones, configuración), editor de publicaciones con validación de archivos (tipo MIME, extensión,
tamaño, cantidad), visor de imágenes, visor de historias (avance automático, pausa, teclado), copiar enlaces,
preferencias de apariencia (`localStorage`), validaciones de formularios y medidor de contraseñas, protección CSRF,
cabeceras de seguridad y control de acceso del panel de administración por rol.

## Arquitectura

```
trevix/
├── index.php, feed.php, …      Puntos de entrada delgados: cargan bootstrap y llaman a un controlador
├── admin/                      Panel: dashboard, reportes, contenido, música, usuarios (moderador o superior);
│                               comunidades, configuración y auditoría (solo administradores)
├── api/                        Endpoints AJAX/Fetch de la web (sesión + CSRF) que responden JSON
│   └── v1/index.php            API REST para las apps móviles (token Bearer), ver docs/API.md
├── app/
│   ├── bootstrap.php           Autoload PSR-4 (Trevix\ → app/), config, errores, cabeceras y sesión
│   ├── Core/                   Config, Database (PDO), Request, Response, Session, Csrf, Auth, View, ErrorHandler
│   ├── Api/                    Kernel, Router, routes.php, Input, Reply, Present y Controllers/ de la API v1
│   ├── Controllers/            Un controlador por sección; Admin/ para el panel
│   ├── Models/                 Acceso a datos con consultas preparadas
│   ├── Services/               Lógica de cada acción compartida por la web y la API (publicar, mensajes,
│   │                           relaciones, comunidades, ajustes…), correo, subidas, menciones y moderación
│   ├── Middleware/             Authenticate, RedirectIfAuthenticated, RequireRole, VerifyCsrf, MaintenanceMode
│   ├── Helpers/functions.php   e(), url(), asset(), icon(), avatar(), pending(), time_ago(), …
│   ├── Data/                   Contenido de demostración y catálogos (países)
│   └── Views/                  layouts/, partials/, pages/, admin/
├── config/                     app.php, database.php, local.php (no versionado)
├── database/trevix_db.sql      Esquema completo de MySQL
├── assets/                     css/, js/, icons/, fonts/, img/
├── uploads/                    avatars/, covers/, posts/, messages/, stories/, communities/, songs/ (sin ejecución de scripts)
├── storage/                    logs/, cache/ (no accesibles por web)
├── mobile/                     App de iOS en Flutter (ver mobile/README.md); .github/workflows/ios.yml la compila
└── docs/                       Documentación interna
```

Flujo de una petición: `feed.php` → `app/bootstrap.php` → `FeedController::index()` → middleware → modelo / datos →
`View::render('pages/feed', $data, 'layouts/app')`.

### Hojas de estilo y scripts

| Archivo | Contenido |
|---------|-----------|
| `tokens.css` | Fuentes, colores, espaciado, radios, sombras, z-index y duraciones |
| `base.css` | Reset, foco accesible, utilidades, `prefers-reduced-motion` |
| `components.css` | Botones, formularios, tarjetas, pestañas, menús, modales, toasts, avatares, chips |
| `layout.css` | Estructura de la app: sidebar, panel derecho, cabecera y navegación móvil |
| `pages.css` | Estilos específicos por página |
| `music.css` | Reproductor, selector de música, biblioteca, ficha de canción, panel del artista y tipo de cuenta |
| `landing.css`, `auth.css`, `admin.css` | Landing, acceso y panel de administración |
| `prefs.js` | Aplica preferencias guardadas antes del primer render (evita parpadeos) |
| `core.js` | `window.Trevix`: `api()` con CSRF, toasts, menús, diálogos, contadores, validaciones comunes |
| `app.js`, `composer.js`, `auth.js`, `landing.js` | Comportamiento por área |
| `stories.js`, `story-create.js` | Visor de historias (vistas, espectadores, respuestas, borrar) y creación con vista previa |
| `communities.js` | Unirse y salir de comunidades sin recargar, confirmaciones y filtros |
| `posts.js` | Me gusta y guardar sin recargar, scroll infinito y confirmación de borrados |
| `follows.js` | Seguir, solicitudes y aceptar/rechazar sin recargar, sincronizando los botones de la página |
| `live.js` | Contadores de avisos y mensajes en vivo y «Marcar todo como leído» |
| `messages.js` | Chat con sondeo: enviar, imágenes, «Visto», en línea, borrar y cargar mensajes anteriores |
| `report.js` | Diálogo «Reportar» con envío sin recargar (sin JavaScript, el enlace abre `report.php`) |
| `music.js` | Reproductor (un solo audio a la vez, fragmentos de 30 s), selector de canciones y envío con progreso |
| `admin.js` | Confirmaciones del panel y formulario de decisión de reportes (duración y nota según la medida) |

### Responsive

| Ancho | Distribución |
|-------|--------------|
| ≥ 1280 px | Sidebar completa + feed + panel derecho |
| 1024–1279 px | Sidebar compacta (iconos con tooltip) + feed + panel derecho |
| 768–1023 px | Sidebar compacta + feed |
| < 768 px | Cabecera superior + feed + barra inferior (Inicio, Explorar, Crear, Notificaciones, Perfil) |

## Seguridad

- **SQL injection:** solo consultas preparadas con PDO (`ATTR_EMULATE_PREPARES = false`).
- **XSS:** toda salida pasa por `e()`; `format_post_body()` escapa antes de enlazar hashtags, menciones y URLs.
  CSP estricta sin scripts ni estilos en línea; la configuración del cliente viaja en un bloque JSON.
- **CSRF:** token por sesión, validado con `hash_equals` en todo `POST` (campo `_csrf` o cabecera `X-CSRF-Token`).
- **Sesión:** `strict_mode`, cookies `HttpOnly` + `SameSite=Lax` (+ `Secure` con HTTPS), regeneración periódica
  y al iniciar sesión, expiración por inactividad.
- **Contraseñas:** `password_hash()` / `password_verify()`, mínimo 10 caracteres con mayúsculas, minúsculas,
  número y símbolo (validado también en el servidor desde la Fase 2).
- **Rate limiting:** tabla `rate_limits`; activo en login (por IP + usuario y por IP), registro, recuperación de
  contraseña, confirmación con la contraseña actual, reenvío de verificación, cambio de correo, publicaciones
  (10 cada 10 min), comentarios (30 cada 10 min), me gusta / guardar (300 cada 10 min), seguir (60 cada 10 min),
  bloquear (20 cada 10 min), mensajes (40 cada 5 min), historias (20 por hora), crear comunidades (3 al día),
  acciones en comunidades (60 cada 10 min), reportes (20 por hora), canciones enviadas (10 al día) y acciones del
  panel (120 cada 10 min).
- **Sesiones:** cada sesión guarda una huella del hash de la contraseña; cambiarla o «cerrar las demás sesiones»
  invalida las sesiones de otros dispositivos.
- **API de las apps:** token Bearer aleatorio de 256 bits (solo se guarda su SHA-256), vencimiento deslizante de
  90 días y máximo 20 por cuenta. Lleva la misma huella de contraseña que la sesión web, así que cambiarla o cerrar
  las demás sesiones también cierra las apps de otros dispositivos; suspender o eliminar la cuenta revoca todos sus
  tokens. La API reutiliza los mismos servicios, validaciones, permisos y límites que la web.
- **Enlaces por correo:** tokens aleatorios de 256 bits, de un solo uso y con vencimiento; en la base solo se guarda su SHA-256.
- **Archivos:** `uploads/` bloquea la ejecución de scripts. Las imágenes se validan con el MIME real (`finfo`) y se
  reprocesan con GD (sin metadatos); los videos se validan por la firma del contenedor. Todo se guarda con nombres
  aleatorios y se sirve con `Cache-Control: private`, para que ningún CDN conserve archivos borrados. El audio de
  las canciones (MP3 o M4A) se identifica por su contenido y su duración se calcula en el servidor.
- **Música:** solo las cuentas de Artista musical envían canciones, y nada entra en la biblioteca sin la aprobación
  del equipo. Una canción retirada o de una cuenta inactiva deja de sonar en todas partes en el servidor («Canción no
  disponible»), no solo en la interfaz.
- **Visibilidad:** cada consulta de publicaciones aplica en el servidor la visibilidad (Público, Seguidores, Solo yo),
  los bloqueos y las cuentas inactivas; editar y borrar solo lo puede hacer el autor.
- **Privacidad y bloqueos:** el contenido de una cuenta privada solo lo ven sus seguidores (también en búsquedas).
  Bloquear rompe los seguimientos en ambos sentidos; la cuenta bloqueada no puede ver el perfil, encontrarlo ni
  seguirlo. Todo se comprueba en el servidor.
- **Mensajes y avisos:** solo los participantes pueden leer una conversación (404 para el resto). La privacidad de
  mensajes (Todos, Personas que sigo, Nadie) y los bloqueos se aplican al enviar; los avisos respetan las
  preferencias de cada cuenta, los bloqueos y la visibilidad de la publicación mencionada.
- **Historias y comunidades:** las historias de una cuenta privada solo las ven sus seguidores y caducan a las 24 h
  (filas y archivos se borran). Las publicaciones de una comunidad privada solo las ven sus miembros activos en
  cualquier listado o enlace directo, y no se pueden compartir. Los roles (administrador, moderador, miembro) se
  comprueban en el servidor en cada acción; transferir o eliminar una comunidad exige la contraseña.
- **Cabeceras:** CSP, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, HSTS con HTTPS.
- **Acceso:** roles `user`, `moderator`, `admin` verificados en el servidor (`RequireRole`).
- **Moderación:** `Services/Moderation.php` decide cada permiso en el servidor: nadie actúa sobre sí mismo ni sobre
  un rango igual o superior, los moderadores suspenden como máximo 30 días y solo los administradores gestionan
  comunidades, roles y configuración; siempre queda al menos un administrador activo. Toda acción del panel exige
  CSRF y queda en `admin_audit_log` con responsable, nota e IP. Suspender una cuenta cierra sus sesiones.
- **Reportes:** solo se puede reportar lo que uno ve (nunca lo propio) y cada persona tiene un único reporte por
  objetivo, así que repetirlo no infla el conteo.
- **Errores:** en producción no se muestran detalles; se registran en `storage/logs/php-error.log`.

## Hoja de ruta

| Fase | Alcance | Estado |
|------|---------|--------|
| 1 | Arquitectura, sistema visual, landing, layouts, componentes y vistas | **Completada** |
| 2 | Registro, login, logout, recuperación de contraseña, verificación de correo, edición de perfil, rate limiting | **Completada** |
| 3 | Publicaciones (texto, imágenes, video, hilos), feed real con paginación, me gusta, comentarios, compartir, guardar, hashtags | **Completada** |
| 4 | Seguir / solicitudes, perfiles privados, explorar, búsqueda, sugerencias | **Completada** |
| 5 | Notificaciones y mensajería privada | **Completada** |
| 6 | Historias y comunidades | **Completada** |
| 7 | Panel de administración, moderación, reportes y auditoría | **Completada** |
| 8 | API REST v1 para las apps de iOS y Android | **Completada** |
| — | Creadores de contenido, biblioteca de música y Threads dentro del inicio | **Completada** |
| — | App de iOS en Flutter (`mobile/`), compilada en GitHub Actions e instalable con ESign | Compila en CI · falta probarla en el iPhone |
| 8 | Optimización, PWA y notificaciones push | Pendiente |
