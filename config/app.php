<?php
declare(strict_types=1);

/*
 * Configuración general de TREVIX.
 * Los valores sensibles o propios de cada servidor se sobrescriben en config/local.php
 * (ver config/local.example.php). Nunca subas config/local.php al repositorio.
 */

$env = getenv('TREVIX_ENV') ?: 'development';

return [
    'name'     => 'TREVIX',
    'tagline'  => 'Conecta. Comparte. Descubre.',
    'env'      => $env,
    'debug'    => $env !== 'production',
    'url'      => getenv('TREVIX_URL') ?: '',
    'timezone' => 'America/Bogota',
    'locale'   => 'es',

    // Responsable de TREVIX en los Términos y la Política de privacidad (legal.php). updated: fecha de la versión vigente.
    'legal' => [
        'owner'   => 'OND-S',
        'founder' => 'Carlos Eduardo Solorzano Torres',
        'country' => 'Colombia',
        'email'   => 'soporte.trevix@ond-s.com',
        'updated' => '11 de noviembre de 2026',
    ],

    // Fase 1: las vistas de la aplicación se pueden recorrer con contenido de demostración.
    // Se ignora automáticamente cuando env = production.
    'preview_mode' => true,

    'session' => [
        'name'             => 'trevix_session',
        'idle_timeout'     => 60 * 60 * 2,
        'regenerate_after' => 60 * 15,
    ],

    'security' => [
        'password_min_length' => 10,
        'rate_limits' => [
            // Intentos fallidos por IP + cuenta y, en general, por IP.
            'login'            => ['max' => 5, 'window' => 15 * 60],
            'login_ip'         => ['max' => 20, 'window' => 15 * 60],
            // Cuentas creadas por IP e intentos de registro por IP.
            'register'         => ['max' => 3, 'window' => 60 * 60],
            'register_attempt' => ['max' => 15, 'window' => 15 * 60],
            // Solicitudes de recuperación por IP + correo y por IP.
            'password_reset'    => ['max' => 3, 'window' => 60 * 60],
            'password_reset_ip' => ['max' => 10, 'window' => 60 * 60],
            // Contraseña actual incorrecta en acciones sensibles (por usuario).
            'password_confirm'  => ['max' => 5, 'window' => 15 * 60],
            // Correos de verificación y de cambio de correo enviados por usuario.
            'verify_email'      => ['max' => 3, 'window' => 60 * 60],
            'email_change'      => ['max' => 3, 'window' => 60 * 60],
            // Contenido creado por usuario.
            'post_create'       => ['max' => 10, 'window' => 10 * 60],
            'comment_create'    => ['max' => 30, 'window' => 10 * 60],
            'interaction'       => ['max' => 300, 'window' => 10 * 60],
            // Seguir, dejar de seguir, responder solicitudes y bloquear (por usuario).
            'follow'            => ['max' => 60, 'window' => 10 * 60],
            'block'             => ['max' => 20, 'window' => 10 * 60],
            'message_send'      => ['max' => 40, 'window' => 5 * 60],
            // Reaccionar, fijar, eliminar para ti, reenviar y cambiar ajustes del chat.
            'message_action'    => ['max' => 120, 'window' => 5 * 60],
            // Grupos creados por usuario y acciones en grupos (entrar, invitar, quitar, ajustes) por usuario.
            'group_create'      => ['max' => 10, 'window' => 24 * 60 * 60],
            'group_action'      => ['max' => 60, 'window' => 10 * 60],
            // Intentos de recuperar la clave del cifrado con el PIN (por usuario) y cambios de clave.
            'e2ee_pin'          => ['max' => 5, 'window' => 15 * 60],
            'e2ee_keys'         => ['max' => 30, 'window' => 60 * 60],
            // Limpiezas del almacenamiento del chat (por usuario).
            'chat_storage'      => ['max' => 10, 'window' => 60 * 60],
            'story_create'      => ['max' => 20, 'window' => 60 * 60],
            // Publicar o borrar la nota y cambiar la lista de mejores amigos (por usuario).
            'note_create'       => ['max' => 20, 'window' => 60 * 60],
            // Dar o quitar me gusta a una nota (por usuario).
            'note_like'         => ['max' => 120, 'window' => 10 * 60],
            'close_friends'     => ['max' => 200, 'window' => 10 * 60],
            'community_create'  => ['max' => 3, 'window' => 24 * 60 * 60],
            // Unirse, salir, responder solicitudes y moderar miembros (por usuario).
            'community_action'  => ['max' => 60, 'window' => 10 * 60],
            'report'            => ['max' => 20, 'window' => 60 * 60],
            // Solicitudes de verificado enviadas por usuario.
            'verification_request' => ['max' => 3, 'window' => 24 * 60 * 60],
            // Canciones enviadas a revisión por artista.
            'song_submit'       => ['max' => 10, 'window' => 24 * 60 * 60],
            // Búsquedas en catálogos externos (Audius, Free To Use, GIPHY) y canciones tomadas de ellos (por usuario).
            'catalog_search'    => ['max' => 120, 'window' => 10 * 60],
            'song_import'       => ['max' => 60, 'window' => 60 * 60],
            // Sugerencias de @menciones mientras se escribe (por usuario).
            'mention_search'    => ['max' => 300, 'window' => 10 * 60],
            // Acciones del panel de administración (por moderador o administrador).
            'admin_action'      => ['max' => 120, 'window' => 10 * 60],
            // Respuestas de IX por persona y en total al día (cuota de la API de Gemini); avisos de IX sin responder.
            'ix_reply'          => ['max' => 30, 'window' => 60 * 60],
            'ix_daily'          => ['max' => 1500, 'window' => 24 * 60 * 60],
            'ix_notice'         => ['max' => 1, 'window' => 60 * 60],
            // Apelaciones enviadas por cuenta.
            'appeal'            => ['max' => 3, 'window' => 24 * 60 * 60],
            // Traducciones de publicaciones con IA por persona (las ya traducidas se sirven de la copia guardada).
            'translate'         => ['max' => 60, 'window' => 60 * 60],
            'translate_daily'   => ['max' => 2000, 'window' => 24 * 60 * 60],
            // Recargas y retiros pedidos por persona; compras de suscripciones y cambios del plan de colaborador.
            'wallet_request'    => ['max' => 10, 'window' => 24 * 60 * 60],
            // Compras de Google Play enviadas a comprobar por persona (la app las reenvía si no recibe respuesta).
            'wallet_play'       => ['max' => 40, 'window' => 60 * 60],
            'subscribe'         => ['max' => 20, 'window' => 60 * 60],
            'collab_plan'       => ['max' => 20, 'window' => 60 * 60],
            // Regalos: compras para guardar y envíos por persona; cambios de la campana del perfil.
            'gift_buy'          => ['max' => 30, 'window' => 60 * 60],
            'gift_send'         => ['max' => 60, 'window' => 60 * 60],
            'profile_alert'     => ['max' => 60, 'window' => 60 * 60],
            // OND-ADS: campañas creadas por persona.
            'ad_create'         => ['max' => 10, 'window' => 60 * 60],
        ],
        // Vigencia de los enlaces enviados por correo, en segundos.
        'token_ttl' => [
            'email_verification' => 60 * 60 * 48,
            'password_reset'     => 60 * 60,
            'email_change'       => 60 * 60 * 24,
        ],
        'reserved_usernames' => [
            'admin', 'administrador', 'administrator', 'superadmin', 'root', 'system', 'sistema', 'trevix',
            'soporte', 'support', 'ayuda', 'help', 'moderador', 'moderator', 'staff', 'oficial', 'official',
            'seguridad', 'security', 'api', 'www', 'mail', 'login', 'register', 'settings', 'null', 'undefined',
        ],
    ],

    /*
     * Envío de correos.
     *  - log:  escribe los correos en storage/logs/mail.log (solo desarrollo).
     *  - mail: función mail() de PHP del servidor.
     *  - smtp: servidor SMTP con autenticación (ssl en el puerto 465 o tls con STARTTLS en el 587).
     */
    'mail' => [
        'driver'       => getenv('TREVIX_MAIL_DRIVER') ?: 'log',
        'from_address' => getenv('TREVIX_MAIL_FROM') ?: 'no-reply@localhost',
        'from_name'    => 'TREVIX',
        'smtp' => [
            'host'       => getenv('TREVIX_SMTP_HOST') ?: '',
            'port'       => (int) (getenv('TREVIX_SMTP_PORT') ?: 465),
            'encryption' => getenv('TREVIX_SMTP_ENCRYPTION') ?: 'ssl',
            'username'   => getenv('TREVIX_SMTP_USER') ?: '',
            'password'   => getenv('TREVIX_SMTP_PASS') ?: '',
            'timeout'    => 15,
        ],
    ],

    'uploads' => [
        'max_files_per_post' => 10,
        // Imágenes de publicaciones: se reescalan hasta este lado mayor (los GIF se conservan para mantener la animación).
        'post_image_max_side' => 2048,
        'message_image_max_side' => 1600,
        // Historias: imágenes hasta 1920 px de lado mayor y videos más livianos que los de publicaciones.
        'story_image_max_side' => 1920,
        'story_video_max_bytes' => 30 * 1024 * 1024,
        // Duración máxima de un video de historia (se comprueba en el navegador y se respeta al reproducir).
        'story_video_seconds' => 30,
        // Fotos de perfil y portadas: se reprocesan en el servidor con GD.
        'profile' => [
            'max_bytes'  => 5 * 1024 * 1024,
            'max_pixels' => 25_000_000,
            'avatar'     => ['width' => 400, 'height' => 400],
            'cover'      => ['width' => 1500, 'height' => 500],
            'song_cover' => ['width' => 600, 'height' => 600],
            'event_cover' => ['width' => 1200, 'height' => 630],
        ],
        // Canciones de artistas: MP3 o M4A (AAC), validadas por su contenido real.
        'audio' => [
            'max_bytes'   => 20 * 1024 * 1024,
            'min_seconds' => 15,
            'max_seconds' => 15 * 60,
            'mimes'       => ['audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/aac'],
            'extensions'  => ['mp3', 'm4a'],
        ],
        'image' => [
            'max_bytes'  => 8 * 1024 * 1024,
            'max_pixels' => 25_000_000,
            'mimes'      => ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
            'extensions' => ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        ],
        // Videos de publicaciones (todos aparecen también en Reels): hasta 5 minutos, leídos del propio archivo.
        'video' => [
            'max_bytes'  => 300 * 1024 * 1024,
            'max_seconds' => 300,
            'mimes'      => ['video/mp4', 'video/webm', 'video/quicktime'],
            'extensions' => ['mp4', 'webm', 'mov'],
        ],
        // Notas de voz de los chats: WAV PCM (navegador), M4A/AAC (app) o MP3; formato y duración se leen del archivo.
        'voice' => [
            'max_bytes'   => 6 * 1024 * 1024,
            'min_seconds' => 1,
            'max_seconds' => 120,
        ],
    ],

    /*
     * Servicios externos. Las claves van solo en config/local.php del servidor (nunca en el repositorio).
     *  - audius / freetouse: catálogos de música libres; no requieren clave.
     *  - giphy: GIF y stickers en comentarios y mensajes; sin clave la función se muestra como no disponible.
     */
    'services' => [
        'audius'    => ['app_name' => 'TREVIX'],
        'freetouse' => [],
        'giphy'     => ['api_key' => getenv('TREVIX_GIPHY_KEY') ?: '', 'rating' => 'pg-13', 'lang' => 'es'],
        // Segundos que se guardan en storage/cache las respuestas de búsqueda de los catálogos.
        'cache_ttl' => 600,
        'timeout'   => 8,
    ],

    /*
     * Google Play Billing: recargas del monedero compradas en la app de Android. service_account es la ruta (absoluta
     * o relativa a la raíz) del JSON de la cuenta de servicio de Google Cloud con acceso a la Google Play Developer
     * API; va solo en el servidor (por ejemplo storage/private/, que no se sirve por HTTP ni entra en git). Sin ese
     * archivo, la app no ofrece la compra con Google Play.
     */
    'google_play' => [
        'package'         => 'com.ondsc.trevix',
        'service_account' => getenv('TREVIX_GOOGLE_PLAY_SA') ?: '',
    ],

    /*
     * IX: asistente de soporte con la API de Gemini (Google AI Studio). Responde los mensajes privados que recibe la
     * cuenta @username, clasifica las peticiones, quejas, reclamos, errores, sugerencias y reportes (admin/support.php)
     * y da la bienvenida por mensaje a cada cuenta nueva. La clave va solo en config/local.php del servidor; sin ella,
     * la bienvenida usa textos propios y los mensajes quedan registrados para el equipo.
     * human_pause_hours: si alguien del equipo escribe desde @username, IX calla en ese chat durante esas horas.
     */
    'ix' => [
        'name'              => 'IX',
        'username'          => 'soport',
        'api_key'           => getenv('TREVIX_GEMINI_KEY') ?: '',
        'model'             => 'gemini-3.5-flash',
        'timeout'           => 20,
        'history'           => 20,
        'human_pause_hours' => 12,
        'welcome'           => true,
    ],

    'limits' => [
        'post_body'    => 2000,
        'comment_body' => 1000,
        'bio'          => 300,
        'display_name' => 60,
        'hashtags_per_post' => 10,
        'feed_page'         => 15,
        'featured_on_feed'  => 3,     // destacadas arriba de «Para ti»
        'comments_page'     => 30,
        'people_page'       => 30,
        'message_body'      => 2000,
        'messages_page'     => 40,
        'notifications_page' => 30,
        'mentions_per_text' => 10,
        'story_text'        => 300,
        'story_caption'     => 200,
        'community_name'    => 80,
        'community_description' => 500,
        'communities_page'  => 24,
        'members_page'      => 30,
        'report_details'    => 1000,
        'moderation_note'   => 255,
        'site_announcement' => 200,
        'admin_page'        => 25,
        // Unidades de un regalo por compra; personas avisadas por la campana del perfil en cada publicación.
        'gift_buy_max'      => 20,
        'profile_alerts_fanout' => 2000,
        'song_title'        => 100,
        'song_featuring'    => 120,
        'songs_page'        => 24,
        // Fragmento de una canción en publicaciones e historias, y duración de una foto o texto con música.
        'song_clip_seconds' => 30,
        'story_song_seconds' => 15,
        // Días máximos de una suspensión impuesta por un moderador (los administradores pueden suspender sin fecha).
        'moderator_suspension_days' => 30,
    ],
    /*
     * Requisitos para pedir el verificado: N seguidores, un promedio de N «Me gusta» en las últimas publicaciones
     * propias (se cuentan hasta recent_posts y hacen falta al menos min_posts) y ninguna advertencia vigente en los
     * últimos warning_days días. Tras un rechazo se puede volver a pedir pasados reapply_days días.
     */
    'verification' => [
        'min_followers' => 1000,
        'min_avg_likes' => 100,
        'min_posts'     => 5,
        'recent_posts'  => 10,
        'warning_days'  => 30,
        'reapply_days'  => 30,
    ],
    /*
     * Chat de la app. disappear_options: duraciones de los mensajes temporales en segundos (0 = desactivados).
     * wallpapers: fondos predefinidos (la app los dibuja; aquí solo se validan las claves). reactions: las de
     * acceso rápido (se acepta cualquier emoji).
     */
    'chat' => [
        'disappear_options' => [0 => 'Desactivados', 86400 => '24 horas', 604800 => '7 días', 7776000 => '90 días'],
        'max_pins'          => 3,
        // Chats fijados arriba en la bandeja de cada persona.
        'max_pinned_chats'  => 3,
        'max_forward'       => 5,
        'nickname_max'      => 40,
        'location_name_max' => 120,
        'search_results'    => 50,
        'wallpapers'        => [
            'default'  => 'Predeterminado',
            'aurora'   => 'Aurora',
            'sunset'   => 'Atardecer',
            'ocean'    => 'Océano',
            'forest'   => 'Bosque',
            'midnight' => 'Medianoche',
            'candy'    => 'Caramelo',
            'lavender' => 'Lavanda',
            'graphite' => 'Grafito',
            'hearts'   => 'Corazones',
            'stars'    => 'Estrellas',
            'bubbles'  => 'Burbujas',
        ],
        // Reacciones rápidas predeterminadas (la primera es la del doble toque); cada persona puede cambiarlas.
        'reactions'         => ['🖤', '😂', '😮', '😢', '😡', '👍'],
        'max_quick_reactions' => 6,
        // Estilo del chat (color de las burbujas propias): lo eligen los dos en un chat o el administrador del grupo.
        'themes'            => [
            'trevix'   => 'TREVIX',
            'ocean'    => 'Océano',
            'sunset'   => 'Atardecer',
            'forest'   => 'Bosque',
            'berry'    => 'Frutos rojos',
            'love'     => 'Amor',
            'gold'     => 'Dorado',
            'lavender' => 'Lavanda',
            'mono'     => 'Monocromo',
        ],
        // Fotos y videos de visualización única: 0 = hasta cerrarla, o los segundos que se ve. Sin abrir, el archivo se borra
        // a los view_once_days días.
        'view_seconds'      => [0, 3, 5, 10],
        'view_once_days'    => 14,
        'group_max_members' => 256,
        'group_title_max'   => 80,
        'group_description_max' => 500,
        // Mensajes cifrados de extremo a extremo: largo máximo del texto cifrado (base64) y del archivo cifrado.
        'e2ee_body_max'     => 24000,
        'e2ee_file_max'     => 64 * 1024 * 1024,
        // Videos del chat (normales o de visualización única): peso y duración máximos.
        'video_max_bytes'   => 64 * 1024 * 1024,
        'video_max_seconds' => 180,
        // «Eliminar almacenamiento del chat»: borrar tus archivos enviados de más de N días.
        'storage_clean_days' => [30, 90],
    ],
    // API v1 de la app móvil: el token vence tras N días sin uso; cada cuenta conserva sus N sesiones más recientes.
    'api' => [
        'token_days'          => 90,
        'max_tokens_per_user' => 20,
        // Tamaño máximo de un cuerpo JSON (los archivos van en multipart/form-data).
        'max_json_bytes'      => 256 * 1024,
    ],
    /*
     * App de iOS. Los enlaces trevix://open/<página>?… abren la app (botón «Abrir en la app» en iPhone y iPad).
     * Con una cuenta de Apple Developer, pon aquí el Team ID: /.well-known/apple-app-site-association publicará
     * el archivo para que los enlaces https de este dominio abran la app directamente (Universal Links).
     */
    'ios' => [
        'scheme'    => 'trevix',
        'bundle_id' => 'com.ondsc.trevix',
        'team_id'   => getenv('TREVIX_APPLE_TEAM_ID') ?: '',
        // Páginas que la app sabe abrir.
        'pages'     => ['post.php', 'profile.php', 'artist.php', 'community.php', 'music.php', 'explore.php', 'event.php', 'events.php', 'g.php'],
    ],
    /*
     * App de Android (mismo esquema trevix:// y mismas páginas que iOS). /.well-known/assetlinks.json publica la huella
     * SHA-256 del certificado con el que se firma el APK, y Android abre los enlaces https de este dominio en la app.
     * Las huellas son públicas: la de la clave de firma de Google Play (apps instaladas desde Play) y la de nuestra
     * clave de subida (APK instalados fuera de Play). La clave de firma está solo en los secretos de GitHub.
     */
    'android' => [
        'package' => 'com.ondsc.trevix',
        'sha256'  => [
            '48:AC:C8:87:E6:3B:CA:55:6D:7B:E3:C7:72:C0:A8:57:0F:FB:F8:7F:85:A0:E9:3E:D2:7E:DE:90:11:F9:65:75',
            '18:F0:3C:64:59:6A:BF:06:F6:35:A4:57:CA:50:E8:CF:65:27:DB:DD:66:0E:11:CC:BF:4A:4C:44:7A:F2:34:32',
        ],
    ],
    // Las historias duran 24 horas.
    'story_ttl' => 24 * 60 * 60,
    // Las notas duran 6 horas; como mucho 60 caracteres y una lista de hasta 200 mejores amigos.
    'notes' => [
        'ttl'               => 6 * 60 * 60,
        'max_length'        => 60,
        'close_friends_max' => 200,
    ],
    // Una persona aparece "en línea" si tuvo actividad en los últimos N segundos. La app y la web renuevan la
    // presencia cada ~25 s mientras están en primer plano y avisan al cerrarse (me/presence, api/presence.php).
    'presence_window' => 75,
];
