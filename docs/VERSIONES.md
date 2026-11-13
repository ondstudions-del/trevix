# TREVIX · Versiones de la app

## Regla

- Cada versión que se publica con cambios en la app suma una décima: Alpha 1.2, 1.3 … 1.9 y después 2.0
  (luego 2.1 … 2.9, 3.0, etc.).
- La versión vive en dos sitios que deben coincidir (GitHub Actions falla si no coinciden):
  - `mobile/pubspec.yaml`: `version: X.Y.0+N`, donde `N` es el número de compilación de Android (sube siempre).
  - `mobile/lib/core/config.dart`: `AppConfig.version = 'Alpha X.Y'` (se muestra en Ajustes de la app).
- El Release de iOS en GitHub se llama «TREVIX iOS Alpha X.Y · compilación R».

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
