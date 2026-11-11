# TREVIX · API REST v1

Referencia para las apps móviles (Flutter: iOS primero, después Android). La API usa la misma lógica, las mismas
validaciones, permisos y límites que la web: todo lo que la web rechaza, la API también lo rechaza con el mismo mensaje.

- **Base:** `https://trevix.ond-s.com/api/v1/`
- **Formato:** JSON en UTF-8. Fechas en ISO 8601 con zona horaria (`2026-11-07T14:05:14-05:00`), archivos como URL
  absoluta, ids como enteros y banderas como booleanos.
- **Código:** `app/Api/` (núcleo, serializadores y controladores) y `api/v1/index.php` (entrada). La tabla de rutas
  está en `app/Api/routes.php`.

## Índice

1. [Convenciones](#convenciones)
2. [Autenticación y sesiones](#autenticación-y-sesiones)
3. [Errores](#errores)
4. [Objetos](#objetos)
5. [Endpoints](#endpoints): app, cuenta, perfil propio, personas, feed y publicaciones, explorar, notificaciones,
   mensajes, historias, notas, música, comunidades, monedero y colaborador, reportes
6. [Panel de moderación y administración](#panel-de-moderación-y-administración)
7. [Guía para la app Flutter](#guía-para-la-app-flutter)

---

## Convenciones

### Petición

| Caso | Cómo enviar |
|------|-------------|
| Datos simples | `Content-Type: application/json` con un **objeto** JSON (máx. 256 KB) |
| Subir archivos | `multipart/form-data`, **siempre con `POST`** (los demás campos van como texto del formulario) |
| Filtros y paginación | Parámetros de la URL (`?page=2&limit=10`) |
| Token | Cabecera `Authorization: Bearer trx_…` |

- `DELETE` puede llevar cuerpo JSON cuando la acción pide confirmación (por ejemplo, la contraseña). En Dart, usa
  `http.Request('DELETE', uri)..body = jsonEncode(...)`.
- Los booleanos aceptan `true`/`false`, `1`/`0` o `"true"`/`"false"`.
- En los `PATCH` solo cambia lo que envías; lo que omites conserva su valor.
- Envía siempre `Accept: application/json`.
- Idioma: los mensajes (`message`, `warning`, `error.message`, `error.fields`) salen en español salvo que envíes
  `Accept-Language: en` (inglés). Idiomas disponibles: `es` y `en`. Los datos (nombres, publicaciones, claves) no
  se traducen.

### Respuesta

```json
{ "ok": true, "data": { … }, "meta": { … } }
```

- `data`: el recurso o la lista. `meta` aparece solo cuando hay paginación u otra información (contadores, etc.).
- Crear devuelve **201**; el resto de éxitos, **200**.
- Todas las respuestas llevan `Cache-Control: no-store`.

### Paginación

Hay dos estilos; la respuesta indica cuál usar en `meta.next` (es `null` cuando no hay más):

| Estilo | `meta.next` | Siguiente página |
|--------|-------------|------------------|
| Cursor (feeds recientes, avisos, historial de chat) | `{"before": 123}` | Repite la petición con `?before=123` |
| Página (búsquedas, listas de personas, comunidades, órdenes por popularidad) | `{"page": 3}` | Repite con `?page=3` |

`?limit=` reduce el tamaño de página (nunca lo aumenta por encima del máximo): publicaciones 15, comentarios 30,
personas 30, comunidades 24, miembros 30, mensajes 40, avisos 30, panel 25.

---

## Autenticación y sesiones

- `POST auth/login` o `POST auth/register` devuelven un **token** (`trx_` + 64 caracteres hex). Guárdalo en el
  almacenamiento seguro del dispositivo (Keychain en iOS, Keystore en Android: paquete `flutter_secure_storage`).
- En la base solo se guarda el SHA-256 del token; si se pierde, hay que volver a iniciar sesión.
- **Vencimiento deslizante de 90 días**: cada uso renueva el plazo (como mucho una vez cada 2 minutos).
- Máximo 20 sesiones de la app por cuenta; al pasar el límite se cierran las que llevan más tiempo sin usarse.
- Envía `device_name` al iniciar sesión (por ejemplo, `"iPhone de Ana"`): es lo que se ve en la lista de sesiones.
- El token **deja de valer** (401) cuando:
  - se cierra la sesión (`auth/logout`) o se cierra desde otro dispositivo (`DELETE auth/sessions/{id}`);
  - se cambia la contraseña o se pide «cerrar las demás sesiones», ya sea desde la web o desde la app (la sesión que
    hizo el cambio sigue abierta);
  - el equipo suspende la cuenta, o la cuenta se desactiva o elimina.
- Sin sesión, CSRF ni cookies: la API es independiente de la sesión web.
- **Modo mantenimiento:** las rutas con token responden 503 salvo a moderadores y administradores. `app/config`,
  `auth/login`, `auth/register` y `auth/password/forgot` siguen respondiendo (el login de una cuenta normal devuelve
  503 con el aviso).

---

## Errores

```json
{
  "ok": false,
  "error": {
    "code": "validation_error",
    "message": "Revisa los datos marcados.",
    "fields": { "email": "Escribe un correo válido." }
  }
}
```

| HTTP | `code` | Cuándo |
|------|--------|--------|
| 400 | `bad_request` | JSON mal formado o parámetro inválido |
| 401 | `unauthenticated` | Sin token, token inválido, vencido o revocado → volver a la pantalla de login |
| 402 | `insufficient_funds` | El saldo del monedero no alcanza para la compra (suscribirse) |
| 403 | `forbidden` | Sin permiso (rol, correo sin verificar, cuenta suspendida al iniciar sesión, registro cerrado…) |
| 404 | `not_found` | No existe o no lo puedes ver (bloqueos, privacidad, contenido oculto) |
| 405 | `method_not_allowed` | Método incorrecto (la cabecera `Allow` dice cuáles valen) |
| 409 | `conflict` | Estado que ya cambió (solicitud ya resuelta, ya vetado…) |
| 413 | `payload_too_large` | Archivos o cuerpo demasiado grandes |
| 422 | `validation_error` | Datos inválidos; `fields` trae el mensaje de cada campo |
| 429 | `too_many_requests` | Límite de uso; la cabecera `Retry-After` indica los segundos de espera |
| 500 | `server_error` | Error interno (se registra en el servidor; no se muestran detalles) |
| 503 | `unavailable` | Modo mantenimiento |

`message` siempre es un texto en español listo para mostrar al usuario. En los errores de login y registro, el
mensaje general va en `fields.form`.

---

## Objetos

### Usuario (`User`)

Aparece como autor, en listas de personas y en resultados.

```json
{
  "id": 25, "username": "ana", "display_name": "Ana Ríos", "avatar_url": "https://…/uploads/avatars/…webp",
  "is_verified": false,
  "is_private": false,
  "bio": "…",
  "followers_count": 120,
  "relation": { "following": true, "requested": false, "follows_you": false }
}
```

`is_private`, `bio`, `followers_count` y `relation` solo vienen cuando la consulta los incluye. En sugerencias se
añade `reason` («Te sigue», «Seguido por…», «Nuevo en TREVIX»…).

### Perfil (`Profile`) y cuenta propia (`Me`)

`Profile` = `User` + `bio`, `website`, `country` (código ISO), `cover_url`, `is_private`, `role`
(`user`|`moderator`|`admin`), `online`, `followers_count`, `following_count`, `posts_count`, `created_at` y el tipo
de cuenta:

```json
"account_type": "creator", "creator_category": "music_artist", "creator_label": "Artista musical",
"is_music_artist": true
```

- `account_type`: `personal` (cuenta normal) | `creator` (creador de contenido). `creator_category` solo en
  creadores: `music_artist` | `influencer` | `blogger` | `other`. `creator_label` es la insignia lista para mostrar
  (`null` en cuentas normales).
- `is_music_artist` activa la sección **Artista** (publicar música); solo con `creator` + `music_artist`.

En `users/{username}`, `collaborator` trae el plan de colaborador y el acceso de quien mira (`null` si la cuenta no
tiene plan activo y no hay acceso vigente):

```json
"collaborator": { "accepting": true, "price": { "cents": 500, "formatted": "US$ 5,00" }, "days": 30,
                  "description": "…", "exclusive_posts": 4, "access_until": "2026-12-11T10:00:00-05:00", "is_owner": false }
```

`Me` = `Profile` + `email`, `email_verified`, `phone` (`+573001234567` o `null`), `locale` (`es`|`en`|`null`:
idioma elegido en la web o con `PUT me/locale`), `birth_date` (`YYYY-MM-DD`), `is_staff` (moderador o admin),
`collaborator_active` (plan de colaborador activo: puede publicar con `visibility: "subscribers"`) y:

```json
"settings": { "is_private": false, "show_activity": true, "message_privacy": "everyone",
              "notify_follows": true, "notify_likes": true, "notify_comments": true, "notify_mentions": true },
"counts":   { "notifications": 2, "follow_requests": 0, "messages": 1 }
```

### Publicación (`Post`)

```json
{
  "id": 48, "format": "post", "body": "Texto con #hashtag y @mención", "visibility": "public",
  "created_at": "…", "is_edited": false,
  "user": { User },
  "community": null,
  "media": [ { "type": "image", "url": "https://…", "alt": "", "width": 1600, "height": 1200 } ],
  "song": { Song + "clip": { "start": 10, "end": 40 } },
  "shared": null, "shared_unavailable": false,
  "counts": { "likes": 3, "comments": 1, "shares": 0, "saves": 0 },
  "viewer": { "liked": false, "saved": false, "is_author": false },
  "web_url": "https://trevix.ond-s.com/post.php?id=48"
}
```

- `format`: `post` | `thread`. `visibility`: `public` | `followers` | `private` | `subscribers` (solo con plan de
  colaborador activo; la ven el autor y quien tenga una suscripción vigente; no vale en comunidades ni al compartir).
- `media[].type`: `image` | `video` (como mucho un video por publicación). Cada elemento trae además
  `poster_url` (miniatura del video, `null` en imágenes y en videos subidos sin póster) y `duration` (segundos del
  video, `null` si no se conoce).
- `shared`: la publicación original completa cuando es un compartido; `shared_unavailable: true` si la original
  ya no se puede ver.
- `community`: `{id, slug, name, visibility}` en publicaciones de comunidades; en las listas de una comunidad, quien
  modera recibe además `can_moderate`.
- `body` es texto plano: la app debe resaltar `#hashtags`, `@menciones` y enlaces por su cuenta.
- `song`: canción de la biblioteca (`null` si no tiene). En publicaciones e historias suena solo el fragmento
  `clip` (de `start` a `end`, como mucho 30 s).
- Los hilos (`format: "thread"`) salen mezclados con las demás publicaciones en todas las pestañas del inicio: ya no
  hay una sección aparte.
- Campos añadidos (todos pueden ser `null`):
  - `background`: fondo de color de un hilo (claves de `story_backgrounds`).
  - `life_event`: `{key, label}`, el acontecimiento importante.
  - `location`: `{name, lat, lng}`; coordenadas redondeadas a ~100 m, o `null` si el lugar se escribió a mano.
  - `gif`: el mismo objeto `Gif` de los comentarios.
  - `event`: ver abajo.
  - `featured`: `true` si la administración la destacó.
- `event`: `{id, title, description, place, starts_at, ends_at, cover_url, going_count, interested_count,
  viewer_response: "going"|"interested"|null, is_past, is_owner}`.

### Canción (`Song`)

```json
{ "id": 7, "available": true, "title": "Noche clara", "featuring": "Luna", "genre": "pop", "genre_label": "Pop",
  "is_explicit": false, "duration": 184, "audio_url": "https://…/uploads/songs/….mp3", "mime": "audio/mpeg",
  "cover_url": "https://…/uploads/songs/covers/….webp", "uses_count": 12, "published_at": "…",
  "artist": { User }, "web_url": "https://trevix.ond-s.com/music.php?id=7" }
```

- Si el artista la retira, moderación la retira o la cuenta deja de estar activa, la canción llega como
  `{ "id": 7, "available": false }` en todas partes donde se usó: muestra «Canción no disponible» y no reproduzcas nada.
  Si se elimina definitivamente, `id` puede ser `0`.
- `uses_count` cuenta cada vez que se eligió (publicaciones, historias y mensajes) y nunca baja.
- Formatos: MP3 (`audio/mpeg`) o M4A (`audio/mp4`).
- `source`: `trevix` (enviada por un artista de TREVIX), `audius` o `freetouse` (tomada de un catálogo externo;
  ver «Música»). `source_label` es el nombre para mostrar y `external_url` la página original (null en las de
  TREVIX). En las externas `artist` es `{ "id": 0, "username": "", "display_name": "Nombre del artista" }`: no
  enlaces a un perfil y muestra el crédito «vía `source_label`».

### Comentario (`Comment`)

```json
{ "id": 9, "post_id": 48, "parent_id": null, "body": "…", "created_at": "…", "user": { User },
  "replies_count": 1, "replies": [ { Comment } ], "can_delete": true, "gif": null }
```

Un solo nivel de respuestas: responder a una respuesta la cuelga del comentario principal.

`gif` (`Gif`, null si no tiene): `{ "id": "…", "kind": "gif" | "sticker", "url": "https://media.giphy.com/…",
"width": 200, "height": 200, "title": "…" }`. Un comentario con GIF puede tener `body` vacío. Muestra el logo o el
texto «Powered by GIPHY» en el buscador.

### Aviso (`Notification`)

```json
{ "id": 37, "type": "comment", "actor": { User }, "text": "comentó tu publicación:", "excerpt": "…",
  "thumb_url": null, "post_id": 48, "comment_id": 10, "community_id": null, "read": false, "created_at": "…" }
```

`type`: `like`, `comment`, `reply`, `mention`, `share`, `follow`, `follow_accepted`, `community_request`,
`community_accepted`, `song_approved`, `song_rejected`, `song_removed`. En los `follow`, `actor.relation` permite
mostrar «Seguir también». Los avisos de música traen `song_id`, no tienen `actor` (los envía el equipo) y en
`excerpt` llega el motivo del rechazo o de la retirada.

### Conversación (`Conversation`) y mensaje (`Message`)

```json
{ "id": 5, "user": { User }, "available": true, "blocked": false, "online": false, "unread": 1, "muted": false,
  "preview": "Tú: Hola", "last_message_at": "…", "partner_last_read_id": 120 }
```

```json
{ "id": 121, "conversation_id": 5, "sender_id": 25, "is_mine": true, "body": "Hola", "image_url": null,
  "voice": null, "gif": null, "deleted": false, "story": null, "song": null, "created_at": "…" }
```

- Un mensaje borrado llega con `deleted: true` y `body`/`image_url`/`voice`/`gif`/`song` en `null` («Mensaje eliminado»).
- `voice`: nota de voz `{url, mime, duration}` (`audio/wav`, `audio/mp4` o `audio/mpeg`; `duration` en segundos).
- `gif`: `Gif` (ver Comentario). Los stickers se ven mejor sin burbuja.
- `song`: solo en mensajes antiguos (ya no se envían canciones por chat). Si llega, es una `Song` completa.
- `story`: respuesta a una historia, `{id, type, media_url, body, background}`, o `{id, expired: true}` si caducó.
- `context`: `null` | `story_reaction` (reacción a una historia; `body` es el emoji y `story` la historia) |
  `note_reply` (respuesta a una nota; `note_text` es el texto de la nota respondida).
- «Visto»: un mensaje propio está visto cuando su `id` ≤ `seen_id` (o `partner_last_read_id`). El servidor solo
  informa lecturas de quienes tienen la confirmación de lectura activa, y ninguna si quien pregunta la desactivó.
- `video` (migración 019): video normal `{url, mime, duration, width, height, poster_url}`; en ese caso `image_url`
  es `null`. Los de visualización única llegan como `view_once` (sin URL) y se abren por `messages/{id}/media`.

### Grupo de historias (`StoryGroup`)

```json
{ "user": { User }, "own": false, "reply_blocked": null, "has_unseen": true,
  "items": [ { "id": 3, "type": "image", "media_url": "https://…", "mime": "image/webp", "body": "",
               "background": null, "seconds": 6, "views": null, "seen": false,
               "song": { Song + "clip": { "start": 12, "end": 42 } }, "created_at": "…" } ] }
```

- `type`: `image` | `video` | `text` (las de texto usan `body` y `background`).
- `song`: canción de fondo (`null` si no tiene). Una foto o un texto con música dura `seconds` (15 s); en los
  videos la canción suena mientras dura el video.
- `views` solo se informa en las historias propias. `reply_blocked` es el motivo por el que no se puede responder
  (null si se puede).
- `note`: la nota activa del autor (`Note`) si quien mira puede verla, o `null`.
- Reacciones: en las propias cada elemento trae `reactions` (cuántas personas reaccionaron); en las ajenas,
  `my_reaction` (el emoji propio o `null`).

### Nota (`Note`)

```json
{ "id": 9, "user": { User }, "own": true, "body": "Pensando en la playa 🌊", "sticker": { Gif } | null,
  "song": { Song + "clip" } | null, "liked": false, "likes": 3, "views": 12, "friend_views": 5,
  "audience": "followers", "audience_label": "Seguidores", "created_at": "…", "expires_at": "…" }
```

- Texto de hasta 60 caracteres, un sticker y/o un fragmento de 30 s de una canción (al menos uno de los tres). Una
  nota activa por persona (publicar otra reemplaza la anterior). Dura 6 horas.
- `likes`, `views` (personas que la vieron, sin contar al autor) y `friend_views` (de ellas, amistades: se siguen
  mutuamente) solo llegan en la propia; `liked` es el me gusta de quien mira.
- `audience` y `audience_label` solo llegan en la propia: `followers` (seguidores), `friends` (amigos: se siguen
  mutuamente) o `close_friends` (la lista de mejores amigos).

### Comunidad (`Community`)

```json
{ "id": 4, "slug": "fotografos", "name": "Fotógrafos", "description": "…", "category": "Fotografía",
  "avatar_url": null, "cover_url": null, "visibility": "public", "members_count": 12, "posts_count": 30,
  "created_at": "…", "membership": { "role": "member", "status": "active" },
  "owner": { "username": "ana", "display_name": "Ana", "id": 25 },
  "access": { "member": true, "owner": false, "manager": false, "banned": false, "pending": false,
              "can_view": true, "can_post": true },
  "web_url": "…" }
```

`membership` es `null` si no perteneces. `owner` y `access` aparecen en el detalle y tras cada acción.

---

## Endpoints

Acceso: **público** = sin token; **usuario** = token válido; **mod** = moderador o admin; **admin** = solo admin.

### App

| Método | Ruta | Acceso | Descripción |
|--------|------|--------|-------------|
| GET | `app/config` | público | Configuración para arrancar la app |

Devuelve `name`, `api_version`, `maintenance`, `registration_open`, `require_email_verification`, `announcement`
(aviso general, puede estar vacío), `password_min_length`, `limits` (largos máximos de textos, tamaños de archivos,
`max_files_per_post`, `video_max_bytes`, `video_max_seconds` (300: 5 minutos), `story_video_seconds`, `song_title`, `song_featuring`, `song_clip_seconds`,
`story_song_seconds`, `audio_max_bytes`, `audio_min_seconds`, `audio_max_seconds`, `voice_max_bytes`,
`voice_min_seconds`, `voice_max_seconds`), `features` (`gifs`: GIPHY disponible; `music_catalogs`: catálogos
externos `{audius: "Audius", freetouse: "Free To Use"}`; `voice_notes`), `image_mimes`, `video_mimes`,
`audio_extensions`, `audio_mimes`, `account_types`, `creator_categories`, `song_genres`, `song_statuses`,
`post_formats`, `post_visibilities`, `story_backgrounds`, `story_filters`, `story_text_colors`, `life_events`, `message_privacy`, `community_categories`,
`community_visibilities`, `report_types`, `report_reasons` y `countries`. Úsalo para validar en la app y llenar los selectores; el servidor valida igual.

### Cuenta y sesiones

| Método | Ruta | Acceso | Cuerpo | Respuesta |
|--------|------|--------|--------|-----------|
| POST | `auth/login` | público | `identifier` (usuario o correo), `password`, `device_name?` | `{token, token_type, expires_at, user: Me, reactivated}` |
| POST | `auth/register` | público | `display_name`, `username`, `email`, `birth_date` (`YYYY-MM-DD`), `password`, `password_confirmation`, `terms: true`, `device_name?` | 201 `{token, …, user: Me, verification_email_sent}` |
| POST | `auth/password/forgot` | público | `email` | `{message}` (misma respuesta exista o no la cuenta) |
| POST | `auth/appeal` | público | `identifier`, `password`, `message` (20–1000) | Apelar una suspensión o baneo → 201 `{appeal_id, message}`. 409 si la cuenta no está suspendida o ya hay una apelación pendiente; 429 si la rechazaron hace menos de 7 días. Comparte el límite de intentos del login |
| POST | `auth/logout` | usuario | — | Cierra esta sesión |
| GET | `auth/sessions` | usuario | — | `[{id, name, current, last_used_at, last_ip, expires_at, created_at}]` |
| DELETE | `auth/sessions/{id}` | usuario | — | Cierra esa sesión (`current: true` si era esta) |
| POST | `auth/sessions/logout-others` | usuario | `password` | Cierra las demás sesiones, web y app |

- El login reactiva una cuenta desactivada (`reactivated: true`). Una cuenta suspendida recibe 403 con el motivo y la
  fecha de fin en `error.message`.
- El restablecimiento de contraseña se completa en la web con el enlace del correo.

### Perfil propio y ajustes

| Método | Ruta | Cuerpo | Descripción |
|--------|------|--------|-------------|
| GET | `me` | — | `Me` |
| GET | `me/counts` | — | `{notifications, follow_requests, messages}` para los distintivos |
| PATCH | `me` | `display_name?`, `username?`, `bio?`, `website?`, `country?`, `birth_date?`, `is_private?`, `account_type?`, `creator_category?` | Edita el perfil → `{message, user: Me}` |
| POST | `me/avatar` · `me/cover` | multipart: archivo en `avatar` / `cover` | Sube la foto o la portada (JPG, PNG, WEBP; recorte al centro) |
| DELETE | `me/avatar` · `me/cover` | — | Quita la foto o la portada |
| GET | `me/details` | — | Datos personales completos → `{details, options}` (`options`: listas `{key, label}` de `relationship_status`, `gender`, `details_audience`, `contact_types` y `limits`) |
| PUT | `me/details` | `city?`, `hometown?`, `relationship_status?`, `gender?`, `interests?: string[]`, `links?: {title, url}[]`, `contacts?: {type, value}[]`, `details_audience?` (`everyone\|followers\|friends\|nobody`), `show_birth_year?`, `birth_date?` | Solo cambia lo enviado; texto vacío borra el dato. Hasta 15 intereses, 5 enlaces (http/https) y 10 contactos → `{message, details}` |
| PUT · DELETE | `me/profile-song` | `song_id`, `song_start?` | Canción del perfil (fragmento de 30 s de la biblioteca) → `{message, song}` |
| PATCH | `me/account` | `username?`, `email?`, `phone?`, `current_password` | Cambiar usuario, correo o teléfono (el correo se confirma por enlace; el teléfono acepta espacios, guiones y paréntesis y se guarda como `+` y 7–15 dígitos; vacío lo borra) → `{changed, message, warning, user}` |
| PUT | `me/locale` | `locale` (`es`\|`en`) | Idioma de la cuenta (el mismo que elige en la web) → `{locale}` |
| GET | `me/appeals` | — | Apelaciones propias `[{id, type (suspension\|warning), warning_id, sanction_reason, message, status (pending\|accepted\|rejected), resolution_note, created_at, reviewed_at}]` |
| POST | `me/appeals` | `warning_id`, `message` (20–1000) | Apelar una advertencia vigente → 201 `{appeal_id, message}` (409 si ya hay una pendiente; 3 al día) |
| POST | `me/email/verification` | — | Reenvía el enlace de verificación |
| PUT | `me/password` | `current_password`, `password`, `password_confirmation` | Cambia la contraseña y cierra los demás dispositivos |
| PATCH | `me/privacy` | `is_private?`, `show_activity?`, `read_receipts?`, `message_privacy?` (`everyone`/`following`/`nobody`) | Privacidad. `read_receipts` (confirmación de lectura, `Me.settings.read_receipts`) es recíproca: quien la desactiva no muestra cuándo leyó ni abrió una foto o video de una vez, y tampoco ve quién leyó lo suyo |
| PATCH | `me/notification-settings` | `notify_follows?`, `notify_likes?`, `notify_comments?`, `notify_mentions?` | Preferencias de avisos |
| GET | `me/blocked` | — | `[User + blocked_at]` |
| GET | `me/follow-requests` | `?page=` | Solicitudes recibidas `[User + requested_at]` |
| POST | `me/follow-requests/{userId}/accept` · `/reject` | — | Aceptar o rechazar |
| GET | `me/saved` | `?page=` | Publicaciones guardadas |
| POST | `me/deactivate` | `password` | Desactivar (se reactiva al iniciar sesión); cierra todas las sesiones |
| DELETE | `me` | `password`, `confirm_username` | Eliminación definitiva. Antes hay que transferir o eliminar las comunidades que administras (409). Las cuentas admin no pueden darse de baja (403) |
| GET | `me/verification` | — | Verificado → `{verified, eligible, checks: [{key, label, ok, current, required, detail}], request, can_apply, blocked_reason, categories: [{key, label}]}` |
| POST | `me/verification` | `category` (`creator\|artist\|public_figure\|brand\|journalist\|athlete\|other`), `full_name` (2–80), `note?` (≤ 500) | Pedir el verificado (422 con `fields.form` si no cumple o ya hay una en revisión; 3 envíos al día) → el mismo estado + `message` |
| DELETE | `me/verification` | — | Cancelar la solicitud en revisión (404 si no hay) |
| GET | `me/warnings` | — | Advertencias del equipo → `{warnings: [{id, reason, about, created_at, revoked, active}], active_count, days}` |

Pasar la cuenta a pública acepta las solicitudes pendientes (el mensaje indica cuántas).

**Verificado.** Requisitos (`config/app.php` → `verification`): 1.000 seguidores o más, promedio de 100 «Me gusta»
en las últimas 10 publicaciones propias (mínimo 5; no cuentan las compartidas) y ninguna advertencia vigente en los
últimos 30 días. El servidor los comprueba al pedirlo y guarda una foto de los números. Tras un rechazo hay que
esperar 30 días para volver a pedirlo. Lo aprueba o rechaza un administrador (app o `admin/verification.php`); la
persona recibe un aviso (`verification_approved` / `verification_rejected`, con el motivo).

**Advertencias.** El equipo puede advertir a una cuenta desde su ficha o al resolver un reporte (medida
`warn_user`). La persona recibe un aviso `warning` (sin `actor`; el motivo va en `excerpt`). Una advertencia
retirada sigue en el historial pero deja de contar.

**Apelaciones.** Una por sanción pendiente a la vez. Las resuelve el equipo (web: `admin/appeals.php` o la ficha del
usuario); aceptar levanta la suspensión o retira la advertencia. La persona recibe un aviso `appeal_accepted` /
`appeal_rejected` (la nota del equipo va en `excerpt`) y un correo.

Tipo de cuenta: `account_type: "creator"` exige `creator_category` (422 si falta o no es válida); volver a
`personal` borra la categoría. Las canciones ya publicadas siguen en la biblioteca aunque la cuenta deje de ser de
artista, pero no puede enviar canciones nuevas.

### Personas

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `users/{username}` | Perfil |
| GET | `users/{username}/posts` | `?tab=posts\|threads\|media&before=` |
| GET | `users/{username}/followers` · `/following` | `?page=` |
| GET | `users/{username}/stories` | `StoryGroup` de esa cuenta o `null` |
| GET | `users/{username}/music` | `?page=` → canciones publicadas del artista (`[Song]`, también en perfiles privados) |
| POST · DELETE | `users/{id}/follow` | Seguir (o solicitar si es privada) · dejar de seguir o cancelar la solicitud |
| DELETE | `users/{id}/follower` | Quitar a esa persona de tus seguidores |
| POST · DELETE | `users/{id}/block` | Bloquear · desbloquear |

`GET users/{username}` devuelve `Profile` + `is_own`, `is_blocked` (lo bloqueaste tú), `can_view`, `relation`,
`message` (`{conversation_id, blocked_reason}`), `stories` (`{active, unseen}`) y `web_url`. Si esa cuenta te
bloqueó, o no existe, responde 404. Sin `can_view` (cuenta privada que no sigues), las listas responden vacías con
`meta.private: true`.

`details` trae los datos personales que esa cuenta deja ver (null si la bloqueaste; sin `can_view`, solo `song`):
`interests`, `links` y `song` siempre; según `details_audience` (todos, seguidores, amigos = seguimiento mutuo, solo
yo) también `city`, `hometown`, `relationship_status` + `relationship_label`, `gender` + `gender_label`, `contacts`
(`{type, value, label, url}`) y `birthday` (`{day, month, year}`; `year` null salvo que la cuenta lo muestre).

Seguir responde `{message, state, relation, followers_count}`.

### Feed, publicaciones y comentarios

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `feed` | `?tab=foryou\|following\|friends\|trending&before=\|page=` | Inicio con publicaciones e hilos mezclados (Tendencias pagina por página) |
| GET | `reels` | `?seed=&page=&start=` | Reels: todas las publicaciones con video visibles, a pantalla completa |
| POST | `posts` | `body?`, `format?`, `visibility?`, `community_id?`, `shared_post_id?`, `song_id?`, `song_start?`; archivos en `media[]` y `poster` (multipart) | 201 `Post` |
| GET | `posts/{id}` | — | `Post` |
| PATCH | `posts/{id}` | `body?`, `visibility?`, `song_id?`, `song_start?` | Editar (solo el autor) → `Post` |
| DELETE | `posts/{id}` | — | Eliminar (solo el autor) |
| POST | `posts/{id}/translation` | `lang?` (`es`\|`en`; por defecto el de `Accept-Language`) | Traducción del texto con IX (Gemini) → `{post_id, lang, source_lang, body, same_language, cached}`. Se guarda en caché por publicación e idioma (se rehace si el texto cambia). `same_language: true` si ya está en ese idioma. 404 si no puedes ver la publicación; 422 si no tiene texto o el idioma no existe; 429 con 60 por hora (2.000 al día en todo el sitio); 503 si la IA no está disponible |
| POST · DELETE | `posts/{id}/like` | — | Dar · quitar me gusta → `{liked, count}` (idempotente) |
| POST · DELETE | `posts/{id}/save` | — | Guardar · quitar → `{saved, count}` |
| GET | `posts/{id}/comments` | `?page=` | Comentarios con respuestas |
| POST | `posts/{id}/comments` | `body?`, `parent_id?`, `gif_id?`, `gif_kind?` (`gif` \| `sticker`) | 201 `Comment` (texto, GIF o ambos) |
| DELETE | `comments/{id}` | — | El autor del comentario o el de la publicación |

- Publicar: hasta 10 archivos (JPG, PNG, WEBP, GIF; un solo video MP4/WEBM/MOV de hasta 300 MB y **5 minutos**).
  Las imágenes se reprocesan en el servidor. Un compartido no lleva archivos. En una comunidad la visibilidad es
  siempre pública.
- **Duración del video:** el servidor la lee del propio archivo (MP4/MOV: `moov/mvhd`; WEBM: `Info/Duration`) y
  también el ancho y alto (con el giro de los videos verticales del móvil). Más de 5 minutos → 422 en
  `fields.media` («Los videos pueden durar como máximo 5 minutos.»); si no se puede leer la duración, también 422.
- **Póster:** con el video se puede enviar `poster` (JPG/PNG/WEBP, la miniatura que genera la app). Se guarda
  reducido a 1080 px y sale en `media[].poster_url`; si falla, el video se publica igual sin póster. Al borrar la
  publicación se borra también.
- **Hilos** (`format: "thread"`): solo texto e imágenes (o fondo de color). Video, `song_id`, `gif_id`,
  `location_name`, `life_event` o `event` → 422 «Los hilos solo llevan texto e imágenes.» (también al editar y
  añadir una canción).
- **Reels** (`GET reels`): cada publicación con video que el usuario puede ver (las mismas reglas de visibilidad y
  bloqueos que el inicio), de 8 en 8. El orden mezcla interacción, novedad y un
  impulso a quien sigues, barajado con `seed`: envía la misma semilla en todas las páginas de una sesión (la app la
  elige al abrir) para que no se repitan. `start` = id del video que se tocó para abrir Reels: va primero en la
  página 1 (si se puede ver y tiene video) y no vuelve a salir. `meta.next` ya incluye `seed` y `start`.
- Con varios archivos usa claves `media[0]`, `media[1]`… o repite `media[]` en el formulario.
- La antigua ruta `threads` ya no existe (404): los hilos llegan en `feed`. En el perfil siguen filtrándose con
  `users/{username}/posts?tab=threads`.
- **Música:** `song_id` = canción publicada de la biblioteca y `song_start` = segundo en que empieza el fragmento de
  30 s (el servidor lo ajusta para que el fragmento quepa en la canción). Una publicación puede llevar solo la
  canción, sin texto ni archivos (salvo los hilos, que necesitan texto). Un compartido no lleva música. Al editar:
  `song_id` distinto cambia la canción, `song_id: 0` la quita, y solo `song_start` mueve el fragmento. Una canción
  no disponible responde 422 en `fields.song_id`.
- **Extras al publicar** (validados en el servidor):
  - `background`: solo hilos y sin archivos.
  - `life_event`: una clave de `app/config.life_events`.
  - `location_name` (máx. 120), con `location_lat` y `location_lng` opcionales.
  - `gif_id` + `gif_kind`: sin archivos ni compartido.
  - `event`: `event[title]` (3–120), `event[place]` (2–160), `event[starts_at]`, `event[ends_at]?` y
    `event[description]?` (máx. 2000), con la portada opcional en el archivo `event_cover`. Un evento no lleva otros
    archivos ni GIF.
  - Fechas: `YYYY-MM-DDTHH:MM` en hora de Colombia o ISO 8601 con zona horaria (la app envía UTC, `…Z`).
  - En JSON, `event` es un objeto; en multipart se usan las claves `event[...]`.
- `GET posts/featured` `?page=` → publicaciones destacadas visibles (públicas y fuera de comunidades privadas).
  En `feed?tab=foryou` (primera página) las 3 más recientes van arriba con `featured: true`.
- `GET events` `?tab=upcoming|past&page=` → publicaciones con evento (próximos: el más cercano primero).
  `GET events/{id}` → la publicación del evento.
  `POST events/{id}/respond` `{choice: going|interested|none}` → `{going_count, interested_count, viewer_response}`.
  Responder a un evento pasado da error 422.
- `GET geo/reverse` `?lat=&lng=` → `{name, lat, lng}` («Barrio, Ciudad, País», con OpenStreetMap y caché de 30 días).

### Explorar

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `search` | `?q=&type=people\|posts\|tags\|communities\|groups` (cada tipo pagina por separado). Personas: `[User + reason]`; grupos: grupos públicos |
| GET | `explore` | `{people, hashtags, communities, media, featured}` para la portada de Explorar |
| GET | `hashtags/trending` | `?limit=` (máx. 30) → `[{tag, category, posts_count}]` |
| GET | `hashtags/{tag}` | Publicaciones con la etiqueta; `meta.hashtag = {tag, posts_count}` |
| GET | `suggestions/users` | `?limit=` (máx. 30) `&page=` (hasta 10) → `[User + reason]`, paginado |
| POST | `suggestions/users/{id}/dismiss` | «No me interesa»: no se vuelve a sugerir en 90 días |

Sugerencias: personas que aún no sigues, ordenadas por cercanía. Puntúan que te siga, los amigos en común
(personas que sigues y la siguen), vivir en tu ciudad o ser de tu ciudad natal, las interacciones de los últimos
90 días (Me gusta, comentarios y chats, en ambos sentidos) y los intereses en común; si no hay señales, cuentas
nuevas y populares. La ciudad solo cuenta si esa persona muestra sus datos a todos (`details_audience = everyone`),
así una sugerencia nunca revela dónde vive alguien. `reason` explica la principal: «Te sigue», «Vive en Bogotá ·
2 amigos en común», «Seguido por Ana y 3 más», «También es de Medellín», «Interactúa contigo», «También le gusta
Fútbol», «Nuevo en TREVIX», «Popular en TREVIX».

Búsqueda de personas: coincide con usuario, nombre, biografía, ciudad pública e intereses (desde 3 letras). El
usuario exacto va primero; después pesan la coincidencia del texto y la relación (lo sigues, te sigue, misma
ciudad). `reason`: «Lo sigues», «Te sigue», «N amigos en común», «Vive en …», «Le interesa …» o `null`.

### Notificaciones

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `notifications` | `?filter=all\|mentions&before=` → avisos; `meta.counts` con los contadores |
| POST | `notifications/read-all` | `{marked}` |
| POST | `notifications/{id}/read` | Marca uno y devuelve `target {post_id, comment_id, community_slug, username}` para navegar |

Las solicitudes de seguimiento no están aquí: van en `me/follow-requests`. Los avisos del sistema (`warning`,
`verification_approved`, `verification_rejected`) llegan con `actor: null`; la app los muestra como «TREVIX».

### Avisos del teléfono (`me/push`)

| Método | Ruta | Parámetros | Descripción |
|--------|------|------------|-------------|
| GET | `me/push` | `?n=&m=&f=&r=` | Lo nuevo desde los cursores, listo para mostrar como notificación del sistema. `meta.cursor {n, m, f, r}` se envía tal cual en la consulta siguiente |

- Cursores: `n` último aviso, `m` último mensaje, `f` última solicitud de seguimiento y `r` fecha (de la base de
  datos) de la última reacción revisada. Sin un `r` válido devuelve `data: []` y los cursores iniciales: nunca se
  avisa de nada anterior a la primera consulta.
- Cada elemento: `{kind, key, id, title, text, avatar_url, link, at}` (+ `type` en la actividad,
  `conversation_id` en mensajes y reacciones, `encrypted` y `prefix` (nombre de quien escribe en los grupos) en
  mensajes, `emoji` en reacciones, y `e2ee {epoch, ciphertext, sender_id}` en mensajes y reacciones a mensajes
  cifrados normales —ni de visualización única ni respuestas a historias o notas—: el teléfono lo descifra con la
  clave del chat y, si no puede, muestra `text` («Mensaje cifrado»)). `meta.uid` es la cuenta del token (el
  teléfono solo usa la clave del cifrado de esa cuenta). `kind`: `activity` (avisos sin leer: me gusta, comentarios,
  menciones, seguidores, comunidades, eventos, canciones, advertencias y verificado), `request` (solicitud de
  seguimiento, si están activos los avisos de seguidores), `message` (sin leer) o `reaction` (a tus mensajes).
  `text` ya viene redactado: «Comenzó a seguirte.», «Reaccionó ❤️ a tu mensaje: «Hola»», «Respondió a tu historia: …».
- `link`: pantalla de la app relativa a `trevix://open/` (`post.php?id=5`, `profile.php?u=ana`, `community.php?c=…`,
  `messages.php?c=12`, `notifications.php` o `notifications.php?tab=requests`).
- No avisa de chats silenciados, mensajes ya leídos, ocultos o caducados, ni entre cuentas bloqueadas. Con 401 la
  app detiene el servicio (sesión cerrada).
- Lo usa el servicio de avisos al instante de Android (cada 20 s con la pantalla encendida y cada minuto apagada).

### Mensajes

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `conversations` | `?q=` | Bandeja: primero los chats fijados (del más reciente al más antiguo) y luego por último mensaje. Cada `Conversation` trae `pinned_chat`, `favorite` y `typing` (alguien escribe ahora). Con `q` busca por nombre, usuario, apodo o texto de los mensajes (`search_match`). `meta {unread, max_pinned_chats}` |
| POST | `conversations/bulk` | `ids [id…]` (1–100), `action: pin\|unpin\|mute\|unmute\|read\|favorite\|unfavorite\|clear\|delete` | Acciones de la bandeja sobre uno o varios chats propios → `{message, unread}`. Fijar: hasta `app.chat.max_pinned_chats` (3; 422 si se pasa). `clear` (vaciar): deja de ver los mensajes que hay ahora; el chat sigue en la bandeja. `delete`: vacía y lo saca de la bandeja (sin fijar ni favorito) hasta que llegue un mensaje nuevo; en los grupos sigue siendo miembro. Ambas solo afectan a quien lo hace. 404 si algún chat no es suyo (y no cambia ninguno) |
| POST | `conversations/{id}/typing` | `typing` (true por defecto) | «Escribiendo…»: la app lo envía como mucho cada 3 s mientras escribes y `false` al borrar o salir; el servidor lo olvida a los 6 s y al enviar un mensaje. No cuenta en chats bloqueados o con cuentas no disponibles |
| GET | `conversations/{id}` | — | `Conversation` + `blocked_reason`, `blocked_by_me`, `pinned` (mensajes fijados) y `options {wallpapers, disappear_options, reactions, max_pins, max_pinned_chats, max_forward, nickname_max}` |
| PATCH | `conversations/{id}` | `muted?`, `nickname?`, `wallpaper?`, `disappear_seconds?` | Solo cambia lo enviado. El apodo solo lo ve quien lo pone; el fondo (como el estilo) y los mensajes temporales cambian para todos y dejan un aviso (`kind: system`) en el chat. En los grupos el fondo solo lo cambian los administradores (migración 021) |
| GET | `conversations/{id}/messages` | `?before=` | Historial en orden cronológico; `meta.next.before` para los anteriores y `meta.now`. No incluye los mensajes que quien mira vació |
| GET | `conversations/{id}/messages` | `?around=ID` | Los mensajes alrededor de uno (saltar a un resultado de la búsqueda o a un mensaje respondido) |
| GET | `conversations/{id}/messages` | `?after=ID&from=ID&since=FECHA&read=1` | Sondeo: mensajes nuevos + `meta {last_id, deleted, updated, pinned, now, seen_id, online, disappear_seconds, theme, wallpaper, typing, unread}`. `typing`: nombres de quienes escriben (hasta 3, sin quien mira). `updated`: mensajes ya cargados que cambiaron desde `since` (el `meta.now` anterior): reacciones, fijados o eliminados |
| GET | `conversations/{id}/search` | `?q=` (2+ letras) | Mensajes con ese texto, del más reciente al más antiguo |
| POST | `conversations/{id}/messages` | `body?`, `reply_to?`; imagen en `image` o nota de voz en `voice` (multipart); o `gif_id` + `gif_kind`; o `location {lat, lng, name?}` | 201 `{conversation_id, message}` |
| POST | `messages` | `to` (usuario), `body?`, `image?`, `voice?`, `gif_id?`, `gif_kind?`, `location?` | Primer mensaje (abre la conversación si no existía) |
| POST | `conversations/{id}/read` | `message_id?` | Marca como leída (sin id: hasta el último) |
| GET | `messages/recipients` | `?q=` | Personas a las que escribir (sin término: a quienes sigues) |
| DELETE | `messages/{id}` | — | Eliminar para todos (solo los propios) → `Message` con `deleted: true` |
| POST / DELETE | `messages/{id}/reaction` | `emoji` | Una reacción por persona (otra la reemplaza) → `Message` |
| POST | `messages/{id}/hide` | — | Eliminar para ti: deja de mostrarse solo a quien lo pide |
| POST / DELETE | `messages/{id}/pin` | — | Fijar o dejar de fijar (para los dos, máximo `max_pins`) → `{pinned: [Message]}` |
| POST | `messages/{id}/forward` | `to: [usuarios]` | Reenviar a hasta `max_forward` personas (cada envío con las reglas del chat) → `{sent, failed}` |

`Message` incluye `kind` (`message` o `system`; los avisos traen `system_text`), `reply_to {id, sender_name, is_mine,
text, available}`, `forwarded`, `location {lat, lng, name}`, `pinned`, `reactions [{emoji, count}]`, `my_reaction` y
`expires_at` (mensajes temporales; al caducar dejan de devolverse y su contenido se borra). Las acciones del chat
usan el límite `message_action` (120 cada 5 min).

- `read=1` marca como leído hasta el último mensaje devuelto (úsalo con la conversación en pantalla).
- `from` = id del mensaje más antiguo cargado: `meta.deleted` lista los ids borrados desde ahí para actualizarlos.
- Privacidad: «Nadie» o «Personas que sigo» impiden iniciar una conversación (403 con el motivo), pero quien ya te
  escribió puede recibir respuesta. Texto máx. 2000 caracteres, una imagen por mensaje.
- Soporte (IX): a la cuenta `@soport` se le puede escribir siempre (salvo bloqueo), también sin el correo verificado.
  Su chat nunca se cifra (`POST conversations/{id}/keys` responde 409 y la cuenta de soporte no puede registrar
  `PUT me/keys`). IX responde en ese chat unos segundos después
  como un mensaje normal de `@soport` (llega por el sondeo); al crear una cuenta, IX le escribe la bienvenida.
- Un mensaje lleva texto y, como mucho, un adjunto: una imagen, una nota de voz o un GIF/sticker (dos adjuntos a
  la vez responden 422). Nota de voz: WAV
  PCM, M4A/AAC o MP3 de `limits.voice_min_seconds` a `limits.voice_max_seconds` (1 a 120 s) y hasta
  `limits.voice_max_bytes` (6 MB). El servidor mide la duración por el contenido. Un archivo falso, una nota
  demasiado corta o un `gif_id` que GIPHY no reconoce responden 422.
- En la bandeja, la vista previa resume «Nota de voz», «GIF» o «Sticker».
- `song_id` ya no se acepta en mensajes.

#### Grupos, visualización única, cifrado y almacenamiento (migración `018_grupos_cifrado.sql`)

`Conversation` añade `type` (`direct` | `group`), `theme` (estilo del chat, para todos), `e2ee` (el chat ya tiene
mensajes cifrados), `key_epoch`, `read_states [{user_id, display_name, avatar_url, last_read_id}]` (grupos) y, en
los grupos, `group {title, description, avatar_url, cover_url, visibility, role, members_count, invite_url,
invite_code}`. `GET conversations/{id}` añade en `options` `themes` y `view_seconds` ([0, 3, 5, 10]). El sondeo
añade a `meta` `theme`, `e2ee`, `key_epoch` y `read_states`.

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| POST | `conversations` | `to` (usuario) | Abre (o devuelve) el chat directo sin enviar nada → `Conversation`. La app lo usa para cifrar el primer mensaje |
| POST | `conversations/{id}/messages` | `view_once=1`, `view_seconds` (0 = hasta cerrarla, 3, 5 o 10) con `image`, `video` o `file` | Foto o video de visualización única: cada persona del chat o del grupo lo abre una vez por `messages/{id}/media`; después responde 410. Cuando lo vieron todos, se borra el archivo |
| POST | `conversations/{id}/messages` | multipart `video` (MP4, MOV o WebM, hasta 64 MB y 180 s), `poster?` (JPEG), `body?` | Video normal (migración 019). Con `view_once=1` no se guarda portada |
| GET | `messages/{id}/info` | — | Solo los propios: `{message_id, view_once, read_receipts, recipients, read, delivered, pending, opened, people [{user, status: read\|delivered\|sent, opened, read_hidden}]}`. «Entregado» = la app o la web de esa persona consultó sus chats después del envío. Sin confirmación de lectura propia, `read`/`opened` no se informan; `read_hidden` marca a quien la desactivó |
| POST | `conversations/{id}/messages` | `e2ee_epoch`, `ciphertext` (base64), `file?` (archivo cifrado), `reply_to?`, `forwarded?`, `view_once?` | Mensaje cifrado: el servidor no ve el contenido. Si la época no es la actual responde 409 con el campo `e2ee_epoch` |
| GET | `messages/{id}/media` | — | Archivo cifrado o de visualización única (con el token). `Cache-Control: no-store` |
| GET | `conversations/{id}/shared` | `?type=media\|links&before=` | Contenido enviado: fotos, notas de voz, GIF y archivos, o mensajes con enlaces (paginado) |
| GET | `conversations/{id}/storage` | — | `{files, bytes, kinds [{kind: photo\|voice\|encrypted, label, files, bytes}], people [User + files, bytes]}` |
| GET | `me/chat-storage` | — | Tus archivos enviados en el servidor: `{files, bytes, older [{days: 30\|90, files, bytes}], conversations [{conversation_id, title, type, files, bytes}], clean_days}` |
| POST | `me/chat-storage/clean` | `older_than_days` (30 o 90), `conversation_id?` | Borra tus archivos enviados más antiguos (los mensajes quedan con `media_cleared: true`) → `{files, bytes, message, storage}` |
| POST | `groups` | `title`, `description?`, `visibility` (`private` \| `public`), `members` (lista o CSV), `avatar?` | Crea el grupo (quien lo crea es el creador y administrador) → `{conversation, failed, message}` |
| GET | `groups` | `?q=` (2+ letras) | Grupos públicos: `[{id, title, description, avatar_url, members_count, is_member, invite_code}]` |
| PATCH | `groups/{id}` | `title?`, `description?`, `theme?`, `visibility?`, `disappear_seconds?` | Ajustes (administradores); cada cambio deja un aviso en el chat |
| POST / DELETE | `groups/{id}/avatar`, `groups/{id}/cover` | multipart `avatar` / `cover` | Foto de perfil y portada del grupo (administradores) |
| GET | `groups/{id}/members` | `?page=` | `User` + `role` (`owner` \| `admin` \| `member`), `is_me`, `has_key`, `available`, `joined_at`; `meta {next, count, requests}` |
| POST | `groups/{id}/members` | `members` | Añadir personas (administradores) → `{added, failed, message, conversation}` |
| DELETE | `groups/{id}/members/{uid}` | — | Eliminar del grupo (administradores; a otro administrador solo el creador) |
| DELETE | `groups/{id}/membership` | — | Salir del grupo. Si sale el creador, pasa a ser creador el administrador (o miembro) más antiguo |
| POST / DELETE | `groups/{id}/admins/{uid}` | — | Nombrar o quitar administrador (solo el creador) |
| POST | `groups/{id}/invite` | — | Nuevo enlace de invitación (el anterior deja de servir) |
| GET | `groups/{id}/requests` | — | Solicitudes para entrar a un grupo privado: `User` + `requested_at` |
| POST | `groups/{id}/requests/{uid}/approve\|reject` | — | Aceptar o rechazar → `{message, conversation}` |
| GET | `invites/{code}` | — | Vista previa del enlace (`/g.php?c=CODE`): `{id, title, description, avatar_url, cover_url, visibility, members_count, state}` (`state`: `member`, `requested` o `none`) |
| POST | `invites/{code}/join` | — | Público: entra. Privado: queda pedido hasta que lo acepte un administrador → `{state, conversation_id, message, conversation?}` |
| GET | `me/keys` | — | Si la cuenta configuró el cifrado: `{configured, public_key, key_id, has_backup, salt}` |
| PUT | `me/keys` | `public_key`, `backup? {blob, salt, auth}` | Registra la clave pública X25519 (o una nueva; las épocas de los chats se renuevan) |
| PUT | `me/keys/backup` | `blob`, `salt`, `auth` | Copia de la clave privada cifrada con otro PIN |
| POST | `me/keys/recover` | `auth` | Devuelve la copia cifrada si la prueba del PIN es correcta (límite `e2ee_pin`: 5 cada 15 min; si no, 403) |
| GET | `conversations/{id}/keys` | — | `{e2ee, epoch, stale, members [{user_id, key_id, public_key}], wraps [{user_id, key_id, wrapped, wrapper_id, wrapper_public}]}` |
| POST | `conversations/{id}/keys` | `epoch`, `keys [{user_id, key_id, wrapped}]` | Nueva época de la clave del chat, envuelta para cada participante con clave (409 si otra persona ya la creó) |

Cifrado de extremo a extremo (solo la app; la web muestra «Ábrelo en la app»):

- Cada cuenta tiene una clave X25519. La privada se guarda en el llavero del teléfono y una copia en el servidor
  cifrada con un PIN de 6 dígitos (PBKDF2-SHA256, 100.000 iteraciones → HKDF: `trevix-pin-auth` para la prueba que
  se envía y `trevix-pin-enc` para AES-256-GCM). El servidor nunca recibe el PIN ni la clave privada.
- Cada chat tiene una clave AES-256 por época, envuelta para cada participante con ECDH (efímera + estática de quien
  la envuelve) y HKDF con `trevix-wrap:{chat}:{época}:{usuario}`. Cambia al entrar o salir alguien de un grupo o al
  registrar alguien una clave nueva (`stale: true`).
- El mensaje es un JSON `{v, t, b, f?, g?, l?}` cifrado con AES-GCM y datos asociados `msg:{chat}:{época}:{autor}`.
  Las fotos y notas de voz se cifran con una clave propia que va dentro del mensaje y se suben en `file`.
- La app cifra cuando el chat ya está cifrado o todos los participantes tienen clave; si alguien solo usa la web,
  el chat sigue sin cifrar. La vista previa y las respuestas a un mensaje cifrado dicen «Mensaje cifrado».

### Historias

| Método | Ruta | Cuerpo | Descripción |
|--------|------|--------|-------------|
| GET | `stories` | — | Barra completa: grupos (los propios primero) con todos sus elementos |
| POST | `stories` | Texto: `type: "text"`, `text`, `background`. Foto o video: multipart con `type=media`, `caption?`, el archivo en `media`, `overlays?` (JSON) y `filter?`. Ambas: `song_id?`, `song_start?` | 201 `{id, message}` |
| POST | `stories/{id}/view` | — | Registra la vista → `{new}` (el autor no cuenta) |
| POST | `stories/{id}/poll` | `choice` (0 o 1) | Vota la encuesta de la historia (una vez; no en las propias) → `{counts, total, viewer_choice}` |
| GET | `stories/{id}/viewers` | — | Solo las propias: `[User + viewed_at + reaction]` (primero quienes reaccionaron), `meta.count` |
| POST | `stories/{id}/reply` | `body` | Responde por mensaje privado → 201 `{conversation_id, message_id, message}` |
| POST / DELETE | `stories/{id}/reaction` | `emoji` | Reacciona (una por persona; otra la reemplaza) o quita la reacción → `{reaction, sent, message}`. Una reacción nueva o distinta también llega al autor por mensaje (`context: story_reaction`) si la privacidad del chat lo permite (`sent`). No en las propias |
| DELETE | `stories/{id}` | — | `{remaining}` (si quedan historias propias activas) |

Duración de 24 horas. Video de hasta 30 MB y 30 s. Muestra fotos y textos 6 s (`seconds`; 15 s si llevan música) y
los videos según su duración real.

Capas de las historias con foto o video (`overlays`, solo en ese tipo):

- Cada capa lleva `type`, `x` e `y` (centro, fracción 0–1 del marco de la historia), `scale` (0.3–4) y
  `rotation` (radianes).
- Tipos y campos:
  - `text`: `text` (1–150), `color` (de `story_text_colors`) y `style` (`plain`, `box` o `neon`).
  - `sticker`: `gif_id` de GIPHY. El servidor lo resuelve y guarda `url`, `width` y `height`.
  - `location`: `name` (2–80).
  - `poll`: `question` (hasta 80) y `options` (exactamente 2, distintas, hasta 25).
  - `mention`: `username`. Debe ser una cuenta activa sin bloqueo; recibe el aviso `story_mention` si puede ver la historia.
  - `link`: `url` http(s) (hasta 300) y `label?` (hasta 30; por defecto, el dominio).
- Límites: 5 textos, 5 stickers, 5 menciones, 1 ubicación, 1 encuesta, 1 enlace y 12 capas en total. Una capa
  inválida responde 422 con el motivo.
- `filter`: una clave de `story_filters` (`vivid`, `warm`, `cool`, `mono`, `vintage`, `fade` o `dramatic`).
- En `StoryGroup.items[]` cada elemento trae `overlays` (sin ids internos), `filter` y `poll`
  (`{counts, total, viewer_choice}` o `null`). `counts` solo llega en las historias propias o después de votar.

### Notas

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `notes` | — | Barra de notas: la propia primero y después las de las cuentas que sigues que puedes ver. `meta {max_length, ttl_seconds, audiences [{key, label}], close_friends_count}` |
| POST | `notes` | `body`, `audience`, `sticker_id?` (GIPHY), `song_id?`, `song_start?` | Publica (reemplaza la anterior) → 201 `{note, message}`. Límite `note_create` (20 por hora) |
| DELETE | `notes` | — | Elimina la nota activa (404 si no hay) |
| POST | `notes/{id}/reply` | `body` | Responde por mensaje privado (`context: note_reply`) → 201 `{conversation_id, message_id, message}`. No a la propia |
| POST | `notes/{id}/view` | — | Registra la vista (el autor no cuenta) → `Note` |
| POST / DELETE | `notes/{id}/like` | — | Me gusta o quitarlo (no en la propia; también cuenta como vista). Límite `note_like` (120 cada 10 min) → `Note` |
| GET | `notes/{id}/activity` | — | Solo la propia: `[User + liked + friend + viewed_at]` (más recientes primero), `meta {views, friend_views, likes}` |
| GET | `me/close-friends` | — | Lista de mejores amigos `[User]`, `meta.count` |
| GET | `me/close-friends/candidates` | `?q=` | Seguidores y cuentas seguidas, con `selected` |
| POST / DELETE | `me/close-friends/{id}` | — | Agrega o quita → `{selected, count}`. Solo personas que sigues o que te siguen, hasta 200. Límite `close_friends` |

- `users/{username}` incluye `note` (o `null`); el grupo de `users/{username}/stories` también la trae.
- `close_friends` sin nadie en la lista responde 422. Las notas caducadas dejan de devolverse y se borran.

### Música

Biblioteca con las canciones que enviaron los artistas y aprobó el equipo.

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `music` | `?q=&genre=&sort=recent\|popular&page=` | Biblioteca (`[Song]`); `q` busca por título, invitados o artista |
| GET | `music/{id}` | — | `Song` (404 si no está publicada) |
| GET | `music/{id}/posts` | `?before=` | Publicaciones visibles que usan la canción |
| GET | `me/music` | `?status=all\|used\|pending\|published\|rejected\|cancelled\|withdrawn\|removed&page=` | Panel del artista: canciones propias (`OwnSong`); `meta.counts` por estado y `meta.is_music_artist` |
| POST | `me/music` | multipart: `title`, `featuring?`, `genre`, `explicit?`, `rights: true`, audio en `audio`, portada opcional en `cover` | 201 `{message, song: OwnSong}` (queda en revisión) |
| POST | `me/music/{id}/cancel` | — | Cancelar el envío (solo en revisión) |
| POST | `me/music/{id}/withdraw` | — | Retirar una publicada: deja de estar en la biblioteca y suena «no disponible» donde se usó |
| POST | `me/music/{id}/republish` | — | Volver a publicar una que retiró el artista (sin nueva revisión) |
| DELETE | `me/music/{id}` | — | Eliminar definitivamente (solo rechazadas, canceladas o retiradas por el artista) |

`OwnSong`:

```json
{ "id": 7, "title": "…", "featuring": null, "genre": "pop", "genre_label": "Pop", "is_explicit": false,
  "status": "published", "status_label": "Publicada", "duration": 184, "size_bytes": 4400000,
  "audio_url": "https://…", "mime": "audio/mpeg", "cover_url": null, "review_note": null,
  "reviewed_at": "…", "published_at": "…", "created_at": "…",
  "uses": { "total": 12, "posts": 3, "stories": 1, "messages": 2 },
  "actions": ["withdraw"] }
```

- Solo pueden enviar las cuentas con `is_music_artist` (403) y con el correo verificado. 10 envíos al día.
- Audio: MP3 o M4A de 15 s a 15 min y hasta 20 MB. El formato y la duración se comprueban en el servidor por el
  contenido del archivo. Portada: JPG, PNG o WEBP (se recorta cuadrada).
- Ciclo: `pending` → `published` (aprobada) · `rejected` (rechazada, con motivo en `review_note`) · `cancelled`
  (cancelada por el artista). `published` → `withdrawn` (retirada por el artista) → `published`.
  `published`/`withdrawn` → `removed` (retirada por moderación, con motivo) → `published` (restaurada por moderación).
- `uses`: `total` es el contador histórico; `posts`, `stories` y `messages` son los usos que siguen activos.
- `actions` dice qué botones mostrar (`cancel`, `withdraw`, `republish`, `delete`).

**Catálogos externos (Audius y Free To Use).** Música libre para usar en publicaciones e historias.

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `music/catalog/{audius\|freetouse}` | `?q=&page=` (sin `q`: destacadas) | `[CatalogTrack]`, `meta.next.page` |
| POST | `music/catalog/{audius\|freetouse}/import` | `external_id` | `Song` lista para usar (`song_id`) |

```json
{ "source": "audius", "source_label": "Audius", "external_id": "D7KyD", "title": "…", "artist": "…",
  "genre": "electronic", "genre_label": "Electrónica", "duration": 201, "preview_url": "https://…",
  "cover_url": "https://…", "page_url": "https://audius.co/…" }
```

- `preview_url` sirve para escuchar antes de elegir. Para usarla en una publicación o historia, primero se importa:
  el servidor vuelve a pedir la pista al catálogo y la guarda una sola vez (importarla otra vez devuelve la misma
  `Song`). Luego se envía su `id` como `song_id`.
- Las búsquedas comparten el límite `catalog_search` (120 cada 10 minutos por usuario; 429 con `Retry-After`).

### GIF y stickers

| Método | Ruta | Parámetros | Descripción |
|--------|------|------------|-------------|
| GET | `gifs/{gif\|sticker}` | `?q=&offset=` (sin `q`: tendencias) | `[Gif]`, `meta.next.offset` |

La clave de GIPHY está en el servidor. Si no hay clave, `app/config` devuelve `features.gifs: false` y esta ruta
responde 503. Para comentar o enviar uno, manda su `id` como `gif_id` y su `kind` como `gif_kind`.

### Comunidades

Las lecturas aceptan el id o el slug (`{key}`); las acciones usan el id numérico.

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `communities` | `?tab=discover\|mine&q=&category=&page=` | Descubrir o «Mis comunidades» |
| POST | `communities` | `name`, `description?`, `category`, `visibility?` | 201 `Community` |
| GET | `communities/{key}` | — | `Community` + `pending_requests` (para quien modera) |
| GET | `communities/{key}/posts` | `?sort=recent\|popular` | Publicaciones (vacío con `meta.private` si no puedes verlas) |
| GET | `communities/{key}/members` | `?status=active\|pending\|banned&page=` | `pending` y `banned` solo para quien modera |
| POST | `communities/{id}/join` | — | Unirse (en las privadas queda como solicitud) |
| DELETE | `communities/{id}/membership` | — | Salir o cancelar la solicitud |
| POST | `communities/{id}/requests/{userId}/approve` · `/reject` | — | Resolver solicitudes |
| POST · DELETE | `communities/{id}/bans/{userId}` | — | Vetar · levantar el veto |
| POST · DELETE | `communities/{id}/moderators/{userId}` | — | Nombrar · retirar moderador (solo el administrador) |
| DELETE | `communities/{id}/posts/{postId}` | — | Quitar una publicación de la comunidad |
| PATCH | `communities/{id}` | `name?`, `description?`, `category?`, `visibility?` | Editar (solo el administrador) |
| POST · DELETE | `communities/{id}/avatar` · `/cover` | multipart con `avatar` / `cover` | Subir · quitar imagen |
| POST | `communities/{id}/transfer` | `username`, `password` | Transferir a otro miembro activo |
| DELETE | `communities/{id}` | `confirm` (el slug), `password` | Eliminar con todas sus publicaciones |

Las acciones responden `{message, community}` con el estado actualizado. Límites: 3 comunidades nuevas al día y 60
acciones cada 10 minutos.

### Monedero y colaborador

Importes en dólares (USD) como `{cents, formatted}`. Al escribir un importe vale `12`, `12.5` o `12,50`. El saldo solo
cambia por movimientos registrados (`wallet_transactions`). La app ofrece el monedero y el colaborador en iOS y en
Android. Reembolsos: `legal.php?doc=reembolsos`.

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `me/wallet` | — | `{currency, balance, withdrawable, min_withdrawal, max_topup, pending_topups, pending_withdrawal, methods: [{id, name, instructions, min_amount}]}` |
| GET | `me/wallet/transactions` | `?before=ID` | `[{id, type, label, amount, balance_after, counterpart: User\|null, created_at}]` (`type`: `topup`, `subscription`, `earning`, `withdrawal`, `withdrawal_refund`, `adjustment`) |
| GET · POST | `me/wallet/topups` | POST multipart: `method_id`, `amount`, `reference`, `note?`, `proof` (imagen) | Recargas (`status`: `pending`, `approved`, `rejected`, `cancelled`; `credited` es lo acreditado). Máximo 3 en revisión |
| DELETE | `me/wallet/topups/{id}` | — | Cancela una recarga en revisión |
| GET · POST | `me/wallet/withdrawals` | POST: `amount`, `method`, `account` | Retiros de lo ganado: se descuenta al pedirlo; uno en revisión a la vez (`status`: `pending`, `paid`, `rejected`, `cancelled`; `payout_reference` al pagarlo) |
| DELETE | `me/wallet/withdrawals/{id}` | — | Cancela un retiro en revisión y devuelve el dinero |
| GET · PUT | `me/collaborator` | PUT: `price`, `days`, `description?` | `{active, plan, eligible, granted, can_activate, checks: [{key, label, ok, current, required, detail}], rules: {commission, min_price, max_price, max_days}, stats: {subscribers, sales, earned, exclusive_posts}}`. Los requisitos solo se exigen para activar el plan por primera vez; `granted`: un administrador habilitó la cuenta sin requisitos (cuenta como `eligible`) |
| POST | `me/collaborator/pause` · `/resume` | — | Deja de aceptar (o vuelve a aceptar) compras nuevas; quien pagó conserva el acceso |
| GET | `me/collaborator/subscribers` | `?page=` | `[User + {access_until, active, since, purchases}]` |
| GET | `me/subscriptions` | `?page=` | `[User + {access_until, active, accepting, price, days}]` |
| POST | `users/{id}/subscribe` | — | Compra o extiende con el monedero: `{message, access_until, price, days, balance}`. 402 `insufficient_funds` sin saldo |

Requisitos, comisión (20 % por defecto), precios y montos se configuran en el panel web (Administración › Monedero).
Las recargas las aprueba un administrador al revisar el comprobante; los retiros se pagan por fuera y se marcan como
pagados. En el panel, «Ajustes y reembolsos» acredita o descuenta saldo con un motivo (movimiento `adjustment`,
`label` «Ajuste de TREVIX: motivo») y «Colaboradores» habilita cuentas sin requisitos. Avisos nuevos: `subscription`,
`topup_approved`, `topup_rejected`, `withdrawal_paid`, `withdrawal_rejected`, `wallet_adjusted` (el `excerpt` lleva
el motivo) y `collaborator_enabled` (abre `wallet.php?tab=collaborator`).

### Regalos (migración `025_regalos_alertas_perfil.sql`)

Regalos GIF o sticker que se pagan con el monedero. El catálogo (categorías, nombre, GIF o sticker subido o de
GIPHY, precio y la comisión) se administra en el panel web (Administración › Regalos). Quien recibe gana el precio
menos la comisión (30 % por defecto, ajuste `gift_commission`; de 0 a 90 %) y lo ganado es retirable. Los regalos recibidos
son privados: solo los ve quien los recibe. No son reembolsables una vez enviados (`legal.php?doc=reembolsos`, punto 3).

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `gifts` | — | `{balance, commission, max_quantity, categories: [{id, name, gifts: [Gift]}], inventory: [Gift + {quantity, paid}]}` |
| POST | `gifts/{id}/buy` | `quantity` (1 a `max_quantity`) | Compra para «Mis regalos»: `{message, balance, inventory}`. 402 sin saldo |
| POST | `gifts/{id}/send` | `to` (usuario), `source: buy\|inventory`, `context: profile\|message\|post\|story`, `ref_id?` | Envía: `{message, send, balance, conversation_id}`. En `post` y `story`, `ref_id` es su id y recibe su autor. En `message` queda como mensaje del chat privado (`Message.gift`). 402 sin saldo |
| GET | `me/gifts/received` · `me/gifts/sent` | `?before=ID` | `[{id, gift: {id, name, kind, media_url, width, height}, user: User\|null, amount, context, post_id, from_inventory, created_at}]` (`amount`: lo ganado o lo pagado) |
| PUT · DELETE | `users/{id}/alerts` | — | Campana del perfil: `{alerts, message}`. Con la campana activa llegan avisos `new_post`, `new_note` y `new_story` de esa cuenta (`Profile.alerts`) |

`Gift`: `{id, name, kind: gif|sticker, media_url, width, height, price, category_id, is_active}`. Movimientos del
monedero nuevos: `gift_purchase` y `gift_received`. Avisos nuevos: `gift` (abre `gifts.php?tab=received`),
`new_post` (la publicación), `new_note` (el perfil) y `new_story` (`stories.php?u=`). `search?type=groups` busca
grupos públicos.

### Reportes

| Método | Ruta | Cuerpo | Descripción |
|--------|------|--------|-------------|
| POST | `reports` | `type` (`post`, `comment`, `user`, `community`, `message`, `story`), `id`, `reason`, `details?` | 201 `{status, message}` |

Solo se reporta lo que uno ve y nunca lo propio (404). `reason: "other"` exige `details` (5 caracteres o más). Los
motivos están en `app/config` → `report_reasons`.

---

## Panel de moderación y administración

Mismas reglas que el panel web (`Services/Moderation.php`): nadie actúa sobre sí mismo ni sobre un rango igual o
superior, los moderadores suspenden como máximo 30 días, siempre queda un administrador activo, cada acción queda
en la auditoría y el panel admite 120 acciones cada 10 minutos. Las respuestas del panel conservan los nombres de
campo de los modelos (fechas en ISO 8601 y archivos como URL).

| Método | Ruta | Acceso | Cuerpo / parámetros | Descripción |
|--------|------|--------|---------------------|-------------|
| GET | `admin/dashboard` | mod | — | `{stats, open_reports, reports, audit, pending_verifications}` (`audit` y `pending_verifications` solo para admin) |
| GET | `admin/reports` | mod | `?status=open\|resolved\|dismissed&type=&page=` | Objetivos reportados; `meta.open_by_type` |
| GET | `admin/reports/{type}/{id}` | mod | — | `{preview, reports, pending, reviewing, measures, durations, history}` |
| POST | `admin/reports/{type}/{id}/take` | mod | — | Marcar «en revisión» |
| POST | `admin/reports/{type}/{id}/dismiss` | mod | `note?` | Descartar (el contenido se mantiene) |
| POST | `admin/reports/{type}/{id}/resolve` | mod | `measure` (de `measures`), `days?` (de `durations`; 0 = sin fecha de fin), `note?` | Aplicar la medida y cerrar |
| GET | `admin/posts` | mod | `?q=` (texto o `@usuario`), `status=published\|hidden`, `page=` | Publicaciones |
| POST | `admin/posts/{id}/hide` · `/restore` | mod | `note?` | Ocultar · restaurar |
| DELETE | `admin/posts/{id}` | mod | `note?` | Eliminar definitivamente |
| POST · DELETE | `admin/posts/{id}/feature` | admin | — | Destacar · quitar de destacadas (solo públicas; avisa al autor y queda en auditoría) |
| GET | `admin/comments` | mod | `?q=&page=` | Comentarios |
| DELETE | `admin/comments/{id}` | mod | `note?` | Eliminar |
| GET | `admin/music` | mod | `?status=pending\|published\|rejected\|removed\|withdrawn&q=&page=` | Canciones (`q`: título o `@artista`); `meta.counts` por estado |
| POST | `admin/music/{id}/approve` | mod | `note?` | Aprobar una en revisión: pasa a la biblioteca y avisa al artista |
| POST | `admin/music/{id}/reject` | mod | `reason` | Rechazar una en revisión (el artista ve el motivo) |
| POST | `admin/music/{id}/remove` | mod | `reason` | Retirar de la biblioteca una publicada o retirada por el artista |
| POST | `admin/music/{id}/restore` | mod | `note?` | Restaurar una retirada por moderación |
| GET | `admin/users` | mod | `?q=&role=&status=&page=` | Cuentas |
| GET | `admin/users/{id}` | mod | — | `{user, can_act, is_self, open_reports, posts, history, durations, warnings}` |
| POST | `admin/users/{id}/warn` | mod | `reason` (≥ 5) | Advertir: la persona recibe un aviso con el motivo |
| DELETE | `admin/warnings/{id}` | mod | `note?` | Retirar una advertencia (deja de contar para el verificado) |
| GET | `admin/verification` | admin | `?status=pending\|approved\|rejected\|cancelled&page=` | Solicitudes de verificado con la foto de números al pedirlo; las pendientes traen `eligible_now` y `checks_now`; `meta.counts` y `meta.rules` |
| POST | `admin/verification/{id}/approve` | admin | `note?` | Verificar: pone la insignia y avisa |
| POST | `admin/verification/{id}/reject` | admin | `reason` (≥ 5) | Rechazar (la persona ve el motivo) |
| POST | `admin/users/{id}/suspend` | mod | `days` (0 = sin fecha de fin, solo admin), `reason` | Suspender: cierra sus sesiones web y de la app |
| POST | `admin/users/{id}/unsuspend` | mod | `note?` | Levantar la suspensión |
| PUT | `admin/users/{id}/role` | admin | `role` (`user`/`moderator`/`admin`) | Cambiar el rol |
| POST · DELETE | `admin/users/{id}/verification` | admin | — | Añadir · quitar la insignia |
| GET | `admin/communities` | admin | `?q=&status=active\|suspended&page=` | Comunidades |
| POST | `admin/communities/{id}/suspend` | admin | `reason` | Suspender |
| POST | `admin/communities/{id}/restore` | admin | `note?` | Reactivar |
| DELETE | `admin/communities/{id}` | admin | `reason` | Eliminar |
| GET | `admin/settings` | admin | — | `{flags: {registration_open, require_email_verification, maintenance_mode}, site_announcement, max_announcement}` |
| PATCH | `admin/settings` | admin | `registration_open?`, `require_email_verification?`, `maintenance_mode?`, `site_announcement?` | Guardar (queda en la auditoría) |
| GET | `admin/audit` | admin | `?group=&admin=&page=` | Auditoría; `meta.groups` y `meta.actors` para los filtros |

Los errores de una regla de moderación (por ejemplo, «No puedes cambiar tu propio rol.») llegan como 422 con el
motivo en `error.message`.

---

## Guía para la app Flutter

### Arranque

1. `GET app/config` → guarda límites y catálogos; si `maintenance` es `true`, muestra el aviso.
2. Si hay token guardado → `GET me`. Con 401, borra el token y abre el login.
3. Muestra `announcement` como banner cuando no esté vacío.

### Cliente HTTP (esquema con `package:http`)

```dart
class TrevixApi {
  static const base = 'https://trevix.ond-s.com/api/v1/';
  final http.Client _client = http.Client();
  String? token;

  Future<Map<String, dynamic>> send(String method, String path, {Map<String, dynamic>? body}) async {
    final request = http.Request(method, Uri.parse(base + path))
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await _client.send(request));
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (json['ok'] == true) return json;
    throw TrevixError(response.statusCode, json['error'], response.headers['retry-after']);
  }
}
```

- Ante `TrevixError` con 401, vuelve al login. Con 422, pinta `error.fields` bajo cada campo. Con 429, usa
  `Retry-After` para desactivar el botón esos segundos.
- Subidas: `http.MultipartRequest('POST', …)` con `files.add(await http.MultipartFile.fromPath('media[0]', path))`
  (o `avatar`, `cover`, `image`, `media`, `audio` según el endpoint). No fijes `Content-Type` a mano.

### Música

- Reproduce `audio_url` con un reproductor de streaming (por ejemplo `just_audio`). En publicaciones e historias,
  limita la reproducción a `clip.start`–`clip.end` (`setClip`); en la biblioteca, la ficha, el perfil y los
  mensajes, reproduce la canción completa.
- Selector de canciones: `GET music?q=…&sort=popular`, o un catálogo externo (`music/catalog/{source}` y después
  `…/import`). Al publicar, envía `song_id` y `song_start`.
- Si `available` es `false`, muestra «Canción no disponible» sin reproductor.

### Tiempo real

El hosting compartido no admite WebSockets y TREVIX no usa Firebase. La app web consulta cada 4 s el chat
abierto y cada 45 s los contadores; en la app:

- Chat abierto: `GET conversations/{id}/messages?after=<último>&from=<primero>&read=1` cada 3–5 s.
- Distintivos: `GET me/counts` al volver a primer plano y cada 30–60 s en primer plano.
- Android: un servicio en primer plano consulta `GET me/push` (ver Avisos del teléfono) también con la app cerrada.
- iOS: `me/counts` en primer plano y la actualización en segundo plano del sistema con la app cerrada.

### Pendiente (fuera de esta versión)

- **Notificaciones push de iOS** (APNs): requieren una cuenta de Apple Developer de pago y registrar tokens de
  dispositivo; los avisos ya existen en `notifications`, así que se pueden añadir sin cambiar la API actual.
- **CORS:** no se envían cabeceras CORS porque las apps nativas no las necesitan. Si se hace un cliente web en otro
  dominio, habrá que añadirlas.
- Restablecer la contraseña y confirmar el correo se hace desde el enlace del correo (web). Para abrirlos en la app
  harán falta Universal Links / App Links.
