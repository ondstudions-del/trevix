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
            'story_create'      => ['max' => 20, 'window' => 60 * 60],
            'community_create'  => ['max' => 3, 'window' => 24 * 60 * 60],
            // Unirse, salir, responder solicitudes y moderar miembros (por usuario).
            'community_action'  => ['max' => 60, 'window' => 10 * 60],
            'report'            => ['max' => 20, 'window' => 60 * 60],
            // Canciones enviadas a revisión por artista.
            'song_submit'       => ['max' => 10, 'window' => 24 * 60 * 60],
            // Acciones del panel de administración (por moderador o administrador).
            'admin_action'      => ['max' => 120, 'window' => 10 * 60],
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
        'video' => [
            'max_bytes'  => 60 * 1024 * 1024,
            'mimes'      => ['video/mp4', 'video/webm', 'video/quicktime'],
            'extensions' => ['mp4', 'webm', 'mov'],
        ],
    ],

    'limits' => [
        'post_body'    => 2000,
        'comment_body' => 1000,
        'bio'          => 300,
        'display_name' => 60,
        'hashtags_per_post' => 10,
        'feed_page'         => 15,
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
        'song_title'        => 100,
        'song_featuring'    => 120,
        'songs_page'        => 24,
        // Fragmento de una canción en publicaciones e historias, y duración de una foto o texto con música.
        'song_clip_seconds' => 30,
        'story_song_seconds' => 15,
        // Días máximos de una suspensión impuesta por un moderador (los administradores pueden suspender sin fecha).
        'moderator_suspension_days' => 30,
    ],
    // API v1 de la app móvil: el token vence tras N días sin uso; cada cuenta conserva sus N sesiones más recientes.
    'api' => [
        'token_days'          => 90,
        'max_tokens_per_user' => 20,
        // Tamaño máximo de un cuerpo JSON (los archivos van en multipart/form-data).
        'max_json_bytes'      => 256 * 1024,
    ],
    // Las historias duran 24 horas.
    'story_ttl' => 24 * 60 * 60,
    // Una persona aparece "en línea" si tuvo actividad en los últimos N segundos.
    'presence_window' => 240,
];
