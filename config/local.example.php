<?php
declare(strict_types=1);

/*
 * Copia este archivo como config/local.php y ajusta los valores de tu servidor.
 * config/local.php está excluido de git.
 */

return [
    'app' => [
        'env'          => 'development', // development | production
        'preview_mode' => true,
        'url'          => '',            // Ej.: https://trevix.com (vacío = autodetectar)
        'mail' => [
            'driver'       => 'log',      // log (desarrollo) | mail | smtp
            'from_address' => 'no-reply@tudominio.com',
            'smtp' => [
                'host'       => 'smtp.tudominio.com',
                'port'       => 465,
                'encryption' => 'ssl',    // ssl (465) | tls (587)
                'username'   => 'no-reply@tudominio.com',
                'password'   => 'contraseña-del-buzón',
            ],
        ],
        'services' => [
            // Clave de https://developers.giphy.com (vacía = sin GIF ni stickers).
            'giphy' => ['api_key' => ''],
        ],
        // IX (soporte con IA): clave de https://aistudio.google.com/api-keys (vacía = avisos y bienvenidas sin IA).
        'ix' => ['api_key' => ''],
        // Google Play Billing: JSON de la cuenta de servicio (vacío = la app no ofrece recargas con Google Play).
        'google_play' => ['service_account' => 'storage/private/google-play.json'],
    ],
    'database' => [
        'host'     => '127.0.0.1',
        'port'     => 3306,
        'name'     => 'trevix_db',
        'user'     => 'trevix_user',
        'password' => 'cambia-esta-contraseña',
    ],
];
