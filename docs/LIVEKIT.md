# TREVIX · LiveKit (Alpha 2.4)

Llamadas de audio, videollamadas 1:1 y transmisiones **live** usan [LiveKit](https://livekit.io): WebRTC gestionado por salas (`room`), con tokens JWT firmados en el servidor PHP.

## Arquitectura

| Capa | Responsabilidad |
|------|-----------------|
| **LiveKit Cloud / servidor** | SFU, salas, tracks de audio/vídeo |
| **PHP (TREVIX)** | Credenciales, tabla `live_sessions`, API `/api/v1/livekit/*`, emisión de JWT |
| **App Flutter** | `livekit_client`, conectar a la sala, UI de llamada/live |

El **API Secret** solo vive en el servidor (`config/local.php`, `config/livekit.credentials.php` o panel **Admin → LiveKit**). La app recibe `wss://…` en `GET app/config → features.livekit`.

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
- `POST /livekit/live` — `{ title? }` inicia emisión (`active`).
- `POST /livekit/sessions/{id}/token` — JWT para unirse (publicar en llamadas; solo el host publica en live).
- `GET /livekit/sessions/{id}` — metadatos de la sesión.

Las llamadas respetan las mismas reglas que los mensajes (`Conversation::cannotMessage`).

## App móvil

- Dependencia: `livekit_client`.
- Servicio: `mobile/lib/core/livekit_api.dart`.
- Pantalla: `mobile/lib/screens/livekit/livekit_room_screen.dart`.
- En chats 1:1, iconos de audio/vídeo en la barra si `features.livekit` está configurado.

## Pendiente (siguientes iteraciones)

- Avisos push / VoIP para llamada entrante (FCM + datos `livekit_call`).
- Listado de lives activos en el feed.
- Grabación y moderación desde el panel.
- TURN dedicado si hay usuarios detrás de NAT estricto (LiveKit Cloud ya incluye infraestructura).