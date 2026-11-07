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
    ],
    'database' => [
        'host'     => '127.0.0.1',
        'port'     => 3306,
        'name'     => 'trevix_db',
        'user'     => 'trevix_user',
        'password' => 'cambia-esta-contraseña',
    ],
];
