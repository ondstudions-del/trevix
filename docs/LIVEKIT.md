# TREVIX · LiveKit (Alpha 2.4)

Llamadas de audio, videollamadas 1:1 y transmisiones **live** usan [LiveKit](https://livekit.io): WebRTC gestionado por salas (`room`), con tokens JWT firmados en el servidor PHP.

## Arquitectura

| Capa | Responsabilidad |
|------|-----------------|
| **LiveKit Cloud / servidor** | SFU, salas, tracks de audio/vídeo |
| **PHP (TREVIX)** | Credenciales, tabla `live_sessions`, API `/api/v1/livekit/*`, emisión de JWT |
| **App Flutter** | `livekit_client`, conectar a la sala, UI de llamada/live |

El **API Secret** solo vive en el servidor (`config/local.php`, `config/livekit.credentials.php` o panel **Admin → LiveKit**). La app recibe `wss://…` en `GET app/config → features.livekit`.

## Puesta en marcha en producción (checklist)

1. **Subir PHP** al sitio correcto (Hostinger TUS). En `trevix.ond-s.com` la raíz es `public_html/trevix`, no el `public_html` principal de otra cuenta.
   - Scripts: `scripts/deploy-livekit.ps1` o `scripts/deploy-livekit-from-json.ps1` (JWT desde el File Manager, sin commitear).
2. **Migración 042:** abre en el navegador (como admin del servidor)  
   `https://TU-DOMINIO/_migrate_042.php?t=cl042-5b1f0a39bb915c88d53d0c6d76de3f20280b717cc782c9718f03d56d1a57858c`  
   Debe responder `DONE`.
3. **Credenciales LiveKit** (obligatorio para que la app muestre llamadas):
   - Crea `livekit-live.secrets.json` (ver ejemplo en `%TEMP%\trevix-deploy\livekit-live.secrets.json.example`) y ejecuta `scripts/configure-livekit.ps1`.
   - Sube `config/livekit.credentials.php` generado al servidor **o** rellena **Admin → LiveKit**.
4. **App:** instala build **48** (Alpha 2.4). En chat 1:1 aparecen iconos de llamada; en tu perfil, **En vivo**.

## Configuración

1. Crea un proyecto en [LiveKit Cloud](https://cloud.livekit.io) (o despliega `livekit-server` con Docker).
2. Copia **URL WebSocket**, **API Key** y **API Secret**.
3. En TREVIX:
   - Panel **Admin → LiveKit**, o
   - `config/local.php` → `app.livekit`, o
   - Archivo `config/livekit.credentials.php` (misma forma que PayPal).
4. Ejecuta la migración `database/migrations/042_livekit.sql`.
5. Activa las funciones que quieras (audio / vídeo / live) en el panel.

## API (resumen)

- `GET /livekit` — estado y flags (usuario autenticado).
- `POST /livekit/calls` — `{ user_id, kind: audio|video }` inicia llamada (estado `ringing`).
- `POST /livekit/calls/{id}/accept|decline|end`
- `GET /livekit/incoming` — llamada entrante en curso (poll de respaldo).
- `POST /livekit/live` — `{ title?, description?, hashtags?, category?, cover_url?, live_mode: camera|voice_chat }` (solo Creador › Stream).
- `GET /livekit/lives` — lives activos (seguidos primero).
- `POST /livekit/sessions/{id}/token` — JWT; en `voice_chat` también publican speakers activos.
- `POST /livekit/sessions/{id}/speakers/invite|accept|remove`
- `GET /livekit/sessions/{id}` — metadatos de la sesión.
- `POST /livekit/sessions/{id}/like` — suma likes del live.
- `GET|POST /livekit/sessions/{id}/messages` — chat (`reply_to_id` opcional); al terminar el host, resumen (regalos, uniones, duración).
- Perfil / Stories / Explorar: `active_live` y anillo VIVO; ya no hay rail en Para ti.
- Regalos: `context=live` + `ref_id` = `live_session_id`. Reportes: tipo `live`.

Las llamadas respetan las mismas reglas que los mensajes (`Conversation::cannotMessage`).

Migraciones: `050_livekit_live_ux.sql`, `051_live_stream_setup.sql` (o `_migrate_050.php` / `_migrate_051.php`).

## App móvil (Alpha 3.0.6+)

- Dependencia: `livekit_client`.
- Servicios: `mobile/lib/core/livekit_api.dart`, `livekit_incoming.dart`, `livekit_nav.dart`.
- Llamada entrante: tono en bucle + Contestar/Rechazar (`incoming_call_sheet.dart`); Android canal «Llamadas».
- Setup: `live_setup_screen.dart` (cámara / chat de voz).
- Sala: overlay TikTok (chat con respuesta, likes, regalos, joins, compartir, reportar, resumen).
- Descubrimiento: Stories + perfil + Explorar (PageView vertical).
- En chats 1:1, iconos de audio/vídeo si `features.livekit` está configurado.
- Deeplinks: `livekit-call.php?id=` y `livekit-live.php?id=`.

## Pendiente (siguientes iteraciones)

- CallKit / PushKit VoIP nativo en iOS.
- Grabación y moderación avanzada desde el panel.
- Visor live WebRTC en la web PHP.
- TURN dedicado si hay usuarios detrás de NAT estricto (LiveKit Cloud ya incluye infraestructura).