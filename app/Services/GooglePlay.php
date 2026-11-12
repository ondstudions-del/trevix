<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;
use Trevix\Core\Database;

/**
 * Google Play Billing: comprueba con la Google Play Developer API las compras de saldo hechas en la app de Android y
 * las consume. Se autentica con una cuenta de servicio de Google Cloud (JWT firmado con su clave privada); el JSON de
 * esa cuenta vive en el servidor, fuera del repositorio. Solo HTTPS con certificado verificado.
 */
final class GooglePlay
{
    /** Productos de compra única (consumibles) creados en Play Console => precio en centavos de USD. */
    public const PRODUCTS = [
        'trevix_recarga_1'  => 100,
        'trevix_recarga_3'  => 300,
        'trevix_recarga_5'  => 500,
        'trevix_recarga_10' => 1000,
        'trevix_recarga_20' => 2000,
        'trevix_recarga_50' => 5000,
    ];
    /** Lo que se queda Google (programa de cargos del servicio del 15 %); el monedero recibe el resto. */
    public const FEE_PERCENT = 15;

    private const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
    private const TOKEN_URL = 'https://oauth2.googleapis.com/token';
    private const PURCHASE_URL = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/%s/purchases/products/%s/tokens/%s';
    private const TOKEN_CACHE = '/storage/cache/google-play-token.json';
    private const MAX_BYTES = 256 * 1024;

    public static function configured(): bool
    {
        return self::packageName() !== '' && self::credentials() !== null;
    }

    public static function packageName(): string
    {
        return trim((string) Config::get('app.google_play.package', ''));
    }

    public static function credited(int $priceCents): int
    {
        return intdiv($priceCents * (100 - self::FEE_PERCENT), 100);
    }

    /**
     * Identificador de la cuenta que viaja con la compra (obfuscatedAccountId): así una compra no puede acreditarse
     * a otra cuenta de TREVIX.
     */
    public static function accountId(int $userId): string
    {
        return hash('sha256', 'trevix-play:' . $userId);
    }

    /**
     * Estado de una compra (ProductPurchase de la API): purchaseState 0 = pagada, 1 = cancelada, 2 = pendiente;
     * consumptionState 1 = ya consumida; purchaseType 0 = compra de prueba.
     *
     * @throws RuntimeException si Google no responde o la compra no existe.
     */
    public static function purchase(string $productId, string $token): array
    {
        [$status, $data] = self::call('GET', self::purchaseUrl($productId, $token));
        if ($status === 404 || $status === 400 || $status === 410) {
            throw new RuntimeException('Google Play no reconoce esa compra.', 404);
        }
        if ($status < 200 || $status >= 300) {
            throw new RuntimeException('Google Play respondió HTTP ' . $status . self::reason($data) . '.');
        }
        return $data;
    }

    /** Consume la compra (también la confirma), para que se pueda volver a comprar el mismo paquete. */
    public static function consume(string $productId, string $token): void
    {
        [$status, $data] = self::call('POST', self::purchaseUrl($productId, $token) . ':consume');
        if ($status < 200 || $status >= 300) {
            throw new RuntimeException('Google Play no consumió la compra (HTTP ' . $status . self::reason($data) . ').');
        }
    }

    private static function purchaseUrl(string $productId, string $token): string
    {
        return sprintf(self::PURCHASE_URL, rawurlencode(self::packageName()), rawurlencode($productId), rawurlencode($token));
    }

    private static function reason(array $data): string
    {
        $message = (string) ($data['error']['message'] ?? '');
        return $message !== '' ? ' (' . mb_substr($message, 0, 160) . ')' : '';
    }

    /** @return array{client_email:string, private_key:string, token_uri:string}|null */
    private static function credentials(): ?array
    {
        static $cached = false;
        if ($cached !== false) {
            return $cached;
        }
        $path = trim((string) Config::get('app.google_play.service_account', ''));
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
        ];
    }

    /** Token OAuth 2.0 de la cuenta de servicio; se guarda en storage/cache hasta poco antes de que caduque. */
    private static function accessToken(): string
    {
        $file = BASE_PATH . self::TOKEN_CACHE;
        if (is_file($file)) {
            $saved = json_decode((string) file_get_contents($file), true);
            if (is_array($saved) && ($saved['expires'] ?? 0) > time() + 60 && !empty($saved['token'])) {
                return (string) $saved['token'];
            }
        }

        $creds = self::credentials();
        if ($creds === null) {
            throw new RuntimeException('Google Play Billing no está configurado en el servidor.');
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
            throw new RuntimeException('No se pudo firmar con la clave de la cuenta de servicio de Google Play.');
        }
        $segments[] = self::base64Url($signature);

        [$status, $data] = self::request('POST', $tokenUri, http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion'  => implode('.', $segments),
        ]), ['Content-Type: application/x-www-form-urlencoded']);
        $token = (string) ($data['access_token'] ?? '');
        if ($status !== 200 || $token === '') {
            throw new RuntimeException('Google rechazó la cuenta de servicio (HTTP ' . $status . ', ' . mb_substr((string) ($data['error'] ?? ''), 0, 60) . ').');
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

    /** @return array{0:int, 1:array} */
    private static function call(string $method, string $url): array
    {
        try {
            return self::request($method, $url, $method === 'POST' ? '' : null, [
                'Authorization: Bearer ' . self::accessToken(),
            ]);
        } finally {
            Database::ensureAlive();
        }
    }

    /** @return array{0:int, 1:array} [código HTTP, respuesta decodificada] */
    private static function request(string $method, string $url, ?string $payload, array $headers): array
    {
        if (!function_exists('curl_init')) {
            throw new RuntimeException('El servidor no tiene cURL.');
        }
        $body = '';
        $ch = curl_init($url);
        $options = [
            CURLOPT_RETURNTRANSFER => false,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_TIMEOUT        => 20,
            CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_ENCODING       => '',
            CURLOPT_HTTPHEADER     => array_merge($headers, [
                'Accept: application/json',
                'User-Agent: TREVIX/1.0 (+https://trevix.ond-s.com)',
            ]),
            CURLOPT_WRITEFUNCTION  => static function ($handle, string $chunk) use (&$body): int {
                if (strlen($body) + strlen($chunk) > self::MAX_BYTES) {
                    return 0;
                }
                $body .= $chunk;
                return strlen($chunk);
            },
        ];
        if ($method === 'POST') {
            $options[CURLOPT_POST] = true;
            $options[CURLOPT_POSTFIELDS] = (string) $payload;
        }
        curl_setopt_array($ch, $options);
        if (PHP_OS_FAMILY === 'Windows' && defined('CURLSSLOPT_NATIVE_CA') && ini_get('curl.cainfo') === '') {
            curl_setopt($ch, CURLOPT_SSL_OPTIONS, CURLSSLOPT_NATIVE_CA);
        }
        $ok = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $error = curl_error($ch);
        curl_close($ch);
        if ($ok === false) {
            throw new RuntimeException('No se pudo conectar con Google Play: ' . $error);
        }
        $data = json_decode($body, true);
        return [$status, is_array($data) ? $data : []];
    }

    private static function base64Url(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }
}
