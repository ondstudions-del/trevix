# TREVIX · Versiones de la app

## Regla

- Cada versión que se publica con cambios en la app suma una décima: Alpha 1.2, 1.3 … 1.9 y después 2.0
  (luego 2.1 … 2.9, 3.0, etc.).
- La versión vive en dos sitios que deben coincidir (GitHub Actions falla si no coinciden):
  - `mobile/pubspec.yaml`: `version: X.Y.0+N`, donde `N` es el número de compilación de Android (sube siempre).
  - `mobile/lib/core/config.dart`: `AppConfig.version = 'Alpha X.Y'` (se muestra en Ajustes de la app).
- El Release de iOS en GitHub se llama «TREVIX iOS Alpha X.Y · compilación R».

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
