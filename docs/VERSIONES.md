# TREVIX · Versiones de la app

## Regla

- Cada versión que se publica con cambios en la app suma una décima: Alpha 1.2, 1.3 … 1.9 y después 2.0
  (luego 2.1 … 2.9, 3.0, etc.).
- La versión vive en dos sitios que deben coincidir (GitHub Actions falla si no coinciden):
  - `mobile/pubspec.yaml`: `version: X.Y.0+N`, donde `N` es el número de compilación de Android (sube siempre).
  - `mobile/lib/core/config.dart`: `AppConfig.version = 'Alpha X.Y'` (se muestra en Ajustes de la app).
- El Release de iOS en GitHub se llama «TREVIX iOS Alpha X.Y · compilación R».

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
