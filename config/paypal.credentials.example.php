<?php
declare(strict_types=1);

/*
 * Copia en el servidor como config/paypal.credentials.php (no va al repo).
 * Obtén client_id y secret en https://developer.paypal.com/dashboard/applications
 */

return [
    'app' => [
        'paypal' => [
            'client_id' => 'TU_CLIENT_ID',
            'secret'    => 'TU_SECRET',
            'mode'      => 'sandbox', // sandbox | live
        ],
    ],
];