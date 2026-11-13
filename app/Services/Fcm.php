<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;
use Trevix\Core\Database;

/**
 * Firebase Cloud Messaging (API HTTP v1, plan gratuito): entrega los avisos al teléfono aunque la app esté cerrada.
 * En Android llega un mensaje de datos que despierta la app (ella consulta GET me/push y muestra lo nuevo); en iPhone
 * Firebase lo entrega por APNs como notificación visible. Se autentica con la cuenta de servicio del proyecto de
 * Firebase (JWT firmado con su clave privada); ese JSON vive solo en el servidor, fuera del repositorio y de la web.
 * Los envíos van en paralelo (cURL multi sobre HTTP/2) y se reintentan una vez si Firebase pide esperar.
 */
final class Fcm
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';
    private const SEND_URL = 'https://fcm.googleapis.com/v1/projects/%s/messages:send';
    private const TOKEN_CACHE = '/storage/cache/fcm-token.json';
    private const MAX_BYTES = 64 * 1024;

    /** Errores de Firebase que significan que el token del teléfono ya no sirve (se borra). */
    public const DEAD = ['UNREGISTERED', 'INVALID_ARGUMENT_TOKEN', 'SENDER_ID_MISMATCH'];
    /** La cuenta de Apple (clave APNs) no está bien configurada en Firebase: el iPhone no recibirá nada. */
    public const APNS_AUTH = 'THIRD_PARTY_AUTH_ERROR';

    public static function configured(): bool
    {
        return self::projectId() !== '' && self::credentials() !== null;
    }

    public static function projectId(): string
    {
        $id = trim((string) Config::get('app.push.fcm.project_id', ''));
        return $id !== '' ? $id : (string) (self::credentials()['project_id'] ?? '');
    }

    /**
     * Datos públicos de Firebase para iniciar el SDK en el teléfono (identificadores de la app, no secretos: van en
     * cualquier app que use Firebase). null si FCM no está configurado: la app sigue con los avisos sin Firebase.
     */
    public static function clientConfig(): ?array
    {
        if (!self::configured()) {
            return null;
        }
        $sender = trim((string) Config::get('app.push.fcm.sender_id', ''));
        $out = ['project_id' => self::projectId(), 'sender_id' => $sender];
        foreach (['android', 'ios'] as $platform) {
            $appId = trim((string) Config::get("app.push.fcm.$platform.app_id", ''));
            $apiKey = trim((string) Config::get("app.push.fcm.$platform.api_key", ''));
            $out[$platform] = $appId !== '' && $apiKey !== '' && $sender !== '' ? ['app_id' => $appId, 'api_key' => $apiKey] : null;
        }
        return $out['android'] === null && $out['ios'] === null ? null : $out;
    }

    /**
     * Envía varios mensajes a la vez. Cada mensaje es el objeto «message» de la API (con su «token»).
     *
     * @param array<int|string, array> $messages
     * @return array<int|string, array{ok:bool, status:int, error:string}> por la misma clave
     */
    public static function sendMany(array $messages): array
    {
        if ($messages === []) {
            return [];
        }
        $results = self::dispatch($messages, self::accessToken());
        if (array_filter($results, static fn (array $r): bool => $r['status'] === 401) !== []) {
            @unlink(BASE_PATH . self::TOKEN_CACHE);
        }
        // Una sola pausa breve para lo que Firebase pidió reintentar (cuota o servicio ocupado).
        $retry = array_filter($results, static fn (array $r): bool => !$r['ok'] && ($r['status'] === 429 || $r['status'] >= 500 || $r['status'] === 0));
        if ($retry !== []) {
            usleep(800_000);
            foreach (self::dispatch(array_intersect_key($messages, $retry), self::accessToken()) as $key => $r) {
                $results[$key] = $r;
            }
        }
        Database::ensureAlive();
        return $results;
    }

    /** @return array<int|string, array{ok:bool, status:int, error:string}> */
    private static function dispatch(array $messages, string $accessToken): array
    {
        $url = sprintf(self::SEND_URL, rawurlencode(self::projectId()));
        $concurrency = max(1, min(100, (int) Config::get('app.push.concurrency', 40)));
        $results = [];
        $queue = $messages;
        $multi = curl_multi_init();
        if (defined('CURLPIPE_MULTIPLEX')) {
            curl_multi_setopt($multi, CURLMOPT_PIPELINING, CURLPIPE_MULTIPLEX);
        }
        $active = [];
        $bodies = [];
        $add = static function () use (&$queue, &$active, &$bodies, $multi, $url, $accessToken): void {
            $key = array_key_first($queue);
            $payload = json_encode(['message' => $queue[$key]], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
            unset($queue[$key]);
            $ch = curl_init($url);
            $id = (int) spl_object_id($ch);
            $bodies[$id] = '';
            curl_setopt_array($ch, [
                CURLOPT_POST           => true,
                CURLOPT_POSTFIELDS     => (string) $payload,
                CURLOPT_RETURNTRANSFER => false,
                CURLOPT_FOLLOWLOCATION => false,
                CURLOPT_CONNECTTIMEOUT => 6,
                CURLOPT_TIMEOUT        => 15,
                CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
                CURLOPT_SSL_VERIFYPEER => true,
                CURLOPT_SSL_VERIFYHOST => 2,
                CURLOPT_HTTP_VERSION   => defined('CURL_HTTP_VERSION_2TLS') ? CURL_HTTP_VERSION_2TLS : CURL_HTTP_VERSION_1_1,
                CURLOPT_PIPEWAIT       => true,
                CURLOPT_HTTPHEADER     => [
                    'Authorization: Bearer ' . $accessToken,
                    'Content-Type: application/json; charset=utf-8',
                    'Accept: application/json',
                ],
                CURLOPT_WRITEFUNCTION  => static function ($handle, string $chunk) use (&$bodies, $id): int {
                    if (strlen($bodies[$id]) + strlen($chunk) > self::MAX_BYTES) {
                        return 0;
                    }
                    $bodies[$id] .= $chunk;
                    return strlen($chunk);
                },
            ]);
            if (PHP_OS_FAMILY === 'Windows' && defined('CURLSSLOPT_NATIVE_CA') && ini_get('curl.cainfo') === '') {
                curl_setopt($ch, CURLOPT_SSL_OPTIONS, CURLSSLOPT_NATIVE_CA);
            }
            curl_multi_add_handle($multi, $ch);
            $active[$id] = [$ch, $key];
        };

        while ($queue !== [] && count($active) < $concurrency) {
            $add();
        }
        do {
            curl_multi_exec($multi, $running);
            while ($info = curl_multi_info_read($multi)) {
                $ch = $info['handle'];
                $id = (int) spl_object_id($ch);
                [, $key] = $active[$id];
                $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
                $results[$key] = [
                    'ok'     => $info['result'] === CURLE_OK && $status === 200,
                    'status' => $info['result'] === CURLE_OK ? $status : 0,
                    'error'  => self::errorCode($status, $bodies[$id]),
                ];
                curl_multi_remove_handle($multi, $ch);
                curl_close($ch);
                unset($active[$id], $bodies[$id]);
                if ($queue !== []) {
                    $add();
                    $running = 1;
                }
            }
            if ($running > 0) {
                curl_multi_select($multi, 0.5);
            }
        } while ($running > 0 || $active !== []);
        curl_multi_close($multi);
        return $results;
    }

    /**
     * Código de error de Firebase (errorCode de FcmError, o el estado general). INVALID_ARGUMENT solo cuenta como
     * token inválido si el mensaje lo dice (si no, el problema es del mensaje y el token se conserva).
     */
    private static function errorCode(int $status, string $body): string
    {
        if ($status === 200) {
            return '';
        }
        $data = json_decode($body, true);
        $error = is_array($data) ? (array) ($data['error'] ?? []) : [];
        $code = '';
        foreach ((array) ($error['details'] ?? []) as $detail) {
            if (is_array($detail) && !empty($detail['errorCode'])) {
                $code = (string) $detail['errorCode'];
            }
        }
        $code = $code !== '' ? $code : (string) ($error['status'] ?? ('HTTP_' . $status));
        if ($code === 'INVALID_ARGUMENT' && stripos((string) ($error['message'] ?? ''), 'registration token') !== false) {
            return 'INVALID_ARGUMENT_TOKEN';
        }
        return $code;
    }

    /** @return array{client_email:string, private_key:string, token_uri:string, project_id:string}|null */
    private static function credentials(): ?array
    {
        static $cached = false;
        if ($cached !== false) {
            return $cached;
        }
        $path = trim((string) Config::get('app.push.fcm.service_account', ''));
        if ($path !== '' && !preg_match('#^([A-Za-z]:)?[\\\\/]#', $path)) {
            $path = BASE_PATH . '/' . $path;
        }
        $data = $path !== '' && is_file($path) && is_readable($path)
            ? json_decode((string) file_get_contents($path), true)
            : null;
        if (!is_array($data) || empty($data['client_email']) || empty($data['private_key'])) {
            return $cached = null;
        }
        return $cached = [
            'client_email' => (string) $data['client_email'],
            'private_key'  => (string) $data['private_key'],
            'token_uri'    => (string) ($data['token_uri'] ?? self::TOKEN_URL),
            'project_id'   => (string) ($data['project_id'] ?? ''),
        ];
    }

    /** Token OAuth 2.0 de la cuenta de servicio; se guarda en storage/cache (0600) hasta poco antes de que caduque. */
    private static function accessToken(): string
    {
        $file = BASE_PATH . self::TOKEN_CACHE;
        if (is_file($file)) {
            $saved = json_decode((string) file_get_contents($file), true);
            if (is_array($saved) && ($saved['expires'] ?? 0) > time() + 120 && !empty($saved['token'])) {
                return (string) $saved['token'];
            }
        }
        $creds = self::credentials();
        if ($creds === null) {
            throw new RuntimeException('Firebase Cloud Messaging no está configurado en el servidor.');
        }
        $tokenUri = str_starts_with($creds['token_uri'], 'https://') ? $creds['token_uri'] : self::TOKEN_URL;
        $now = time();
        $segments = [
            self::base64Url(json_encode(['alg' => 'RS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR)),
            self::base64Url(json_encode([
                'iss'   => $creds['client_email'],
                'scope' => self::SCOPE,
                'aud'   => $tokenUri,
                'iat'   => $now,
                'exp'   => $now + 3600,
            ], JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR)),
        ];
        $key = openssl_pkey_get_private($creds['private_key']);
        if ($key === false || !openssl_sign(implode('.', $segments), $signature, $key, OPENSSL_ALGO_SHA256)) {
            throw new RuntimeException('No se pudo firmar con la clave de la cuenta de servicio de Firebase.');
        }
        $segments[] = self::base64Url($signature);

        $body = '';
        $ch = curl_init($tokenUri);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => http_build_query([
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion'  => implode('.', $segments),
            ]),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 6,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_HTTPHEADER     => ['Content-Type: application/x-www-form-urlencoded', 'Accept: application/json'],
        ]);
        if (PHP_OS_FAMILY === 'Windows' && defined('CURLSSLOPT_NATIVE_CA') && ini_get('curl.cainfo') === '') {
            curl_setopt($ch, CURLOPT_SSL_OPTIONS, CURLSSLOPT_NATIVE_CA);
        }
        $body = (string) curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        $data = json_decode($body, true);
        $token = is_array($data) ? (string) ($data['access_token'] ?? '') : '';
        if ($status !== 200 || $token === '') {
            throw new RuntimeException('Google rechazó la cuenta de servicio de Firebase (HTTP ' . $status . ').');
        }

        $dir = dirname($file);
        if (is_dir($dir) || @mkdir($dir, 0755, true)) {
            $tmp = $file . '.' . bin2hex(random_bytes(4));
            if (@file_put_contents($tmp, json_encode(['token' => $token, 'expires' => $now + (int) ($data['expires_in'] ?? 3600)])) !== false) {
                @chmod($tmp, 0600);
                @rename($tmp, $file);
            }
        }
        return $token;
    }

    private static function base64Url(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }
}
