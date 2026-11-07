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
   mensajes, historias, música, comunidades, reportes
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

`Me` = `Profile` + `email`, `email_verified`, `birth_date` (`YYYY-MM-DD`), `is_staff` (moderador o admin) y:

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

- `format`: `post` | `thread`. `visibility`: `public` | `followers` | `private`.
- `media[].type`: `image` | `video` (como mucho un video por publicación).
- `shared`: la publicación original completa cuando es un compartido; `shared_unavailable: true` si la original
  ya no se puede ver.
- `community`: `{id, slug, name, visibility}` en publicaciones de comunidades; en las listas de una comunidad, quien
  modera recibe además `can_moderate`.
- `body` es texto plano: la app debe resaltar `#hashtags`, `@menciones` y enlaces por su cuenta.
- `song`: canción de la biblioteca (`null` si no tiene). En publicaciones e historias suena solo el fragmento
  `clip` (de `start` a `end`, como mucho 30 s).
- Los hilos (`format: "thread"`) salen mezclados con las demás publicaciones en todas las pestañas del inicio: ya no
  hay una sección aparte.

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

### Comentario (`Comment`)

```json
{ "id": 9, "post_id": 48, "parent_id": null, "body": "…", "created_at": "…", "user": { User },
  "replies_count": 1, "replies": [ { Comment } ], "can_delete": true }
```

Un solo nivel de respuestas: responder a una respuesta la cuelga del comentario principal.

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
  "deleted": false, "story": null, "song": null, "created_at": "…" }
```

- Un mensaje borrado llega con `deleted: true` y `body`/`image_url`/`song` en `null` («Mensaje eliminado»).
- `song`: `Song` completa (en los mensajes se escucha entera, sin `clip`).
- `story`: respuesta a una historia, `{id, type, media_url, body, background}`, o `{id, expired: true}` si caducó.
- «Visto»: un mensaje propio está visto cuando su `id` ≤ `seen_id` (o `partner_last_read_id`).

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
`max_files_per_post`, `story_video_seconds`, `song_title`, `song_featuring`, `song_clip_seconds`,
`story_song_seconds`, `audio_max_bytes`, `audio_min_seconds`, `audio_max_seconds`), `image_mimes`, `video_mimes`,
`audio_extensions`, `audio_mimes`, `account_types`, `creator_categories`, `song_genres`, `song_statuses`,
`post_formats`, `post_visibilities`, `story_backgrounds`, `message_privacy`, `community_categories`,
`community_visibilities`, `report_types`, `report_reasons` y `countries`. Úsalo para validar en la app y llenar los selectores; el servidor valida igual.

### Cuenta y sesiones

| Método | Ruta | Acceso | Cuerpo | Respuesta |
|--------|------|--------|--------|-----------|
| POST | `auth/login` | público | `identifier` (usuario o correo), `password`, `device_name?` | `{token, token_type, expires_at, user: Me, reactivated}` |
| POST | `auth/register` | público | `display_name`, `username`, `email`, `birth_date` (`YYYY-MM-DD`), `password`, `password_confirmation`, `terms: true`, `device_name?` | 201 `{token, …, user: Me, verification_email_sent}` |
| POST | `auth/password/forgot` | público | `email` | `{message}` (misma respuesta exista o no la cuenta) |
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
| PATCH | `me/account` | `username?`, `email?`, `current_password` | Cambiar usuario o correo (el correo se confirma por enlace) → `{changed, message, warning, user}` |
| POST | `me/email/verification` | — | Reenvía el enlace de verificación |
| PUT | `me/password` | `current_password`, `password`, `password_confirmation` | Cambia la contraseña y cierra los demás dispositivos |
| PATCH | `me/privacy` | `is_private?`, `show_activity?`, `message_privacy?` (`everyone`/`following`/`nobody`) | Privacidad |
| PATCH | `me/notification-settings` | `notify_follows?`, `notify_likes?`, `notify_comments?`, `notify_mentions?` | Preferencias de avisos |
| GET | `me/blocked` | — | `[User + blocked_at]` |
| GET | `me/follow-requests` | `?page=` | Solicitudes recibidas `[User + requested_at]` |
| POST | `me/follow-requests/{userId}/accept` · `/reject` | — | Aceptar o rechazar |
| GET | `me/saved` | `?page=` | Publicaciones guardadas |
| POST | `me/deactivate` | `password` | Desactivar (se reactiva al iniciar sesión); cierra todas las sesiones |
| DELETE | `me` | `password`, `confirm_username` | Eliminación definitiva. Antes hay que transferir o eliminar las comunidades que administras (409). Las cuentas admin no pueden darse de baja (403) |

Pasar la cuenta a pública acepta las solicitudes pendientes (el mensaje indica cuántas).

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

Seguir responde `{message, state, relation, followers_count}`.

### Feed, publicaciones y comentarios

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `feed` | `?tab=foryou\|following\|friends\|trending&before=\|page=` | Inicio con publicaciones e hilos mezclados (Tendencias pagina por página) |
| POST | `posts` | `body?`, `format?`, `visibility?`, `community_id?`, `shared_post_id?`, `song_id?`, `song_start?`; archivos en `media[]` (multipart) | 201 `Post` |
| GET | `posts/{id}` | — | `Post` |
| PATCH | `posts/{id}` | `body?`, `visibility?`, `song_id?`, `song_start?` | Editar (solo el autor) → `Post` |
| DELETE | `posts/{id}` | — | Eliminar (solo el autor) |
| POST · DELETE | `posts/{id}/like` | — | Dar · quitar me gusta → `{liked, count}` (idempotente) |
| POST · DELETE | `posts/{id}/save` | — | Guardar · quitar → `{saved, count}` |
| GET | `posts/{id}/comments` | `?page=` | Comentarios con respuestas |
| POST | `posts/{id}/comments` | `body`, `parent_id?` | 201 `Comment` |
| DELETE | `comments/{id}` | — | El autor del comentario o el de la publicación |

- Publicar: hasta 10 archivos (JPG, PNG, WEBP, GIF; un solo video MP4/WEBM/MOV de 60 MB). Las imágenes se
  reprocesan en el servidor. Un compartido no lleva archivos. En una comunidad la visibilidad es siempre pública.
- Con varios archivos usa claves `media[0]`, `media[1]`… o repite `media[]` en el formulario.
- La antigua ruta `threads` ya no existe (404): los hilos llegan en `feed`. En el perfil siguen filtrándose con
  `users/{username}/posts?tab=threads`.
- **Música:** `song_id` = canción publicada de la biblioteca y `song_start` = segundo en que empieza el fragmento de
  30 s (el servidor lo ajusta para que el fragmento quepa en la canción). Una publicación puede llevar solo la
  canción, sin texto ni archivos (salvo los hilos, que necesitan texto). Un compartido no lleva música. Al editar:
  `song_id` distinto cambia la canción, `song_id: 0` la quita, y solo `song_start` mueve el fragmento. Una canción
  no disponible responde 422 en `fields.song_id`.

### Explorar

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `search` | `?q=&type=people\|posts\|tags\|communities` (cada tipo pagina por separado) |
| GET | `explore` | `{people, hashtags, communities, media}` para la portada de Explorar |
| GET | `hashtags/trending` | `?limit=` (máx. 30) → `[{tag, category, posts_count}]` |
| GET | `hashtags/{tag}` | Publicaciones con la etiqueta; `meta.hashtag = {tag, posts_count}` |
| GET | `suggestions/users` | `?limit=` (máx. 30) → `[User + reason]` |

### Notificaciones

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `notifications` | `?filter=all\|mentions&before=` → avisos; `meta.counts` con los contadores |
| POST | `notifications/read-all` | `{marked}` |
| POST | `notifications/{id}/read` | Marca uno y devuelve `target {post_id, comment_id, community_slug, username}` para navegar |

Las solicitudes de seguimiento no están aquí: van en `me/follow-requests`.

### Mensajes

| Método | Ruta | Cuerpo / parámetros | Descripción |
|--------|------|---------------------|-------------|
| GET | `conversations` | — | Bandeja; `meta.unread` = conversaciones con mensajes sin leer |
| GET | `conversations/{id}` | — | `Conversation` + `blocked_reason` |
| PATCH | `conversations/{id}` | `muted` | Silenciar o reactivar avisos |
| GET | `conversations/{id}/messages` | `?before=` | Historial en orden cronológico; `meta.next.before` para los anteriores |
| GET | `conversations/{id}/messages` | `?after=ID&from=ID&read=1` | Sondeo: mensajes nuevos + `meta {last_id, deleted, seen_id, online, unread}` |
| POST | `conversations/{id}/messages` | `body?`, `song_id?`; imagen en `image` (multipart) | 201 `{conversation_id, message}` |
| POST | `messages` | `to` (usuario), `body?`, `image?`, `song_id?` | Primer mensaje (abre la conversación si no existía) |
| POST | `conversations/{id}/read` | `message_id?` | Marca como leída (sin id: hasta el último) |
| GET | `messages/recipients` | `?q=` | Personas a las que escribir (sin término: a quienes sigues) |
| DELETE | `messages/{id}` | — | Borrar un mensaje propio → `Message` con `deleted: true` |

- `read=1` marca como leído hasta el último mensaje devuelto (úsalo con la conversación en pantalla).
- `from` = id del mensaje más antiguo cargado: `meta.deleted` lista los ids borrados desde ahí para actualizarlos.
- Privacidad: «Nadie» o «Personas que sigo» impiden iniciar una conversación (403 con el motivo), pero quien ya te
  escribió puede recibir respuesta. Texto máx. 2000 caracteres, una imagen por mensaje.
- Un mensaje puede llevar texto con una imagen **o** con una canción, pero no imagen y canción a la vez (422 en
  `fields.song_id`). En la bandeja, un mensaje solo con canción se resume como «Canción».

### Historias

| Método | Ruta | Cuerpo | Descripción |
|--------|------|--------|-------------|
| GET | `stories` | — | Barra completa: grupos (los propios primero) con todos sus elementos |
| POST | `stories` | Texto: `type: "text"`, `text`, `background`. Foto o video: multipart con `type=media`, `caption?` y el archivo en `media`. Ambas: `song_id?`, `song_start?` | 201 `{id, message}` |
| POST | `stories/{id}/view` | — | Registra la vista → `{new}` (el autor no cuenta) |
| GET | `stories/{id}/viewers` | — | Solo las propias: `[User + viewed_at]`, `meta.count` |
| POST | `stories/{id}/reply` | `body` | Responde por mensaje privado → 201 `{conversation_id, message_id, message}` |
| DELETE | `stories/{id}` | — | `{remaining}` (si quedan historias propias activas) |

Duración de 24 horas. Video de hasta 30 MB y 30 s. Muestra fotos y textos 6 s (`seconds`; 15 s si llevan música) y
los videos según su duración real.

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
| GET | `admin/dashboard` | mod | — | `{stats, open_reports, reports, audit}` (`audit` solo para admin) |
| GET | `admin/reports` | mod | `?status=open\|resolved\|dismissed&type=&page=` | Objetivos reportados; `meta.open_by_type` |
| GET | `admin/reports/{type}/{id}` | mod | — | `{preview, reports, pending, reviewing, measures, durations, history}` |
| POST | `admin/reports/{type}/{id}/take` | mod | — | Marcar «en revisión» |
| POST | `admin/reports/{type}/{id}/dismiss` | mod | `note?` | Descartar (el contenido se mantiene) |
| POST | `admin/reports/{type}/{id}/resolve` | mod | `measure` (de `measures`), `days?` (de `durations`; 0 = sin fecha de fin), `note?` | Aplicar la medida y cerrar |
| GET | `admin/posts` | mod | `?q=` (texto o `@usuario`), `status=published\|hidden`, `page=` | Publicaciones |
| POST | `admin/posts/{id}/hide` · `/restore` | mod | `note?` | Ocultar · restaurar |
| DELETE | `admin/posts/{id}` | mod | `note?` | Eliminar definitivamente |
| GET | `admin/comments` | mod | `?q=&page=` | Comentarios |
| DELETE | `admin/comments/{id}` | mod | `note?` | Eliminar |
| GET | `admin/music` | mod | `?status=pending\|published\|rejected\|removed\|withdrawn&q=&page=` | Canciones (`q`: título o `@artista`); `meta.counts` por estado |
| POST | `admin/music/{id}/approve` | mod | `note?` | Aprobar una en revisión: pasa a la biblioteca y avisa al artista |
| POST | `admin/music/{id}/reject` | mod | `reason` | Rechazar una en revisión (el artista ve el motivo) |
| POST | `admin/music/{id}/remove` | mod | `reason` | Retirar de la biblioteca una publicada o retirada por el artista |
| POST | `admin/music/{id}/restore` | mod | `note?` | Restaurar una retirada por moderación |
| GET | `admin/users` | mod | `?q=&role=&status=&page=` | Cuentas |
| GET | `admin/users/{id}` | mod | — | `{user, can_act, is_self, open_reports, posts, history, durations}` |
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
- Selector de canciones: `GET music?q=…&sort=popular`. Al publicar, envía `song_id` y `song_start`.
- Si `available` es `false`, muestra «Canción no disponible» sin reproductor.

### Tiempo real

El hosting compartido no admite WebSockets ni hay notificaciones push todavía. La app web consulta cada 4 s el chat
abierto y cada 45 s los contadores; en la app:

- Chat abierto: `GET conversations/{id}/messages?after=<último>&from=<primero>&read=1` cada 3–5 s.
- Distintivos: `GET me/counts` al volver a primer plano y cada 30–60 s en primer plano.
- Detén los sondeos en segundo plano.

### Pendiente (fuera de esta versión)

- **Notificaciones push** (APNs para iOS y FCM para Android): requieren registrar tokens de dispositivo y un
  servicio de envío; los avisos ya existen en `notifications`, así que se pueden añadir sin cambiar la API actual.
- **CORS:** no se envían cabeceras CORS porque las apps nativas no las necesitan. Si se hace un cliente web en otro
  dominio, habrá que añadirlas.
- Restablecer la contraseña y confirmar el correo se hace desde el enlace del correo (web). Para abrirlos en la app
  harán falta Universal Links / App Links.
