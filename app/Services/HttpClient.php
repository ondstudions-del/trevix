<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;

/**
 * Peticiones GET a las API de los catálogos externos (Audius, Free To Use, GIPHY), con caché en disco
 * (storage/cache) para no repetir la misma búsqueda. Solo HTTPS con verificación de certificado.
 */
final class HttpClient
{
    private const MAX_BYTES = 2 * 1024 * 1024;
    private const CACHE_DIR = '/storage/cache/http';

    /**
     * @param int $ttl segundos de caché (0 = sin caché)
     * @throws RuntimeException si el servicio no responde o la respuesta no es JSON.
     */
    public static function getJson(string $url, int $ttl = 0): array
    {
        if (!str_starts_with($url, 'https://')) {
            throw new RuntimeException('URL no permitida.');
        }
        $cacheFile = $ttl > 0 ? BASE_PATH . self::CACHE_DIR . '/' . hash('sha256', $url) . '.json' : null;
        if ($cacheFile !== null && is_file($cacheFile) && filemtime($cacheFile) > time() - $ttl) {
            $cached = json_decode((string) file_get_contents($cacheFile), true);
            if (is_array($cached)) {
                return $cached;
            }
        }

        [$status, $body] = self::fetch($url, (int) Config::get('app.services.timeout', 8));
        $data = json_decode($body, true);
        if ($status < 200 || $status >= 300 || !is_array($data)) {
            throw new RuntimeException('El servicio externo no respondió correctamente (HTTP ' . $status . ').');
        }

        if ($cacheFile !== null) {
            self::store($cacheFile, $body);
        }
        return $data;
    }

    /** @return array{0:int, 1:string} [código HTTP, cuerpo] */
    private static function fetch(string $url, int $timeout): array
    {
        $headers = ['Accept: application/json', 'User-Agent: TREVIX/1.0 (+https://trevix.ond-s.com)'];
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            $body = '';
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => false,
                CURLOPT_FOLLOWLOCATION => false,
                CURLOPT_CONNECTTIMEOUT => min(5, $timeout),
                CURLOPT_TIMEOUT        => $timeout,
                CURLOPT_HTTPHEADER     => $headers,
                CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
                CURLOPT_SSL_VERIFYPEER => true,
                CURLOPT_SSL_VERIFYHOST => 2,
                CURLOPT_ENCODING       => '',
                CURLOPT_WRITEFUNCTION  => static function ($handle, string $chunk) use (&$body): int {
                    if (strlen($body) + strlen($chunk) > self::MAX_BYTES) {
                        return 0;
                    }
                    $body .= $chunk;
                    return strlen($chunk);
                },
            ]);
            if (PHP_OS_FAMILY === 'Windows' && defined('CURLSSLOPT_NATIVE_CA') && ini_get('curl.cainfo') === '') {
                curl_setopt($ch, CURLOPT_SSL_OPTIONS, CURLSSLOPT_NATIVE_CA);
            }
            $ok = curl_exec($ch);
            $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            $error = curl_error($ch);
            curl_close($ch);
            if ($ok === false) {
                throw new RuntimeException('No se pudo conectar con el servicio externo: ' . $error);
            }
            return [$status, $body];
        }

        $context = stream_context_create([
            'http' => ['method' => 'GET', 'header' => implode("\r\n", $headers), 'timeout' => $timeout, 'follow_location' => 0, 'ignore_errors' => true],
            'ssl'  => ['verify_peer' => true, 'verify_peer_name' => true],
        ]);
        $body = @file_get_contents($url, false, $context, 0, self::MAX_BYTES);
        if ($body === false) {
            throw new RuntimeException('No se pudo conectar con el servicio externo.');
        }
        $status = 0;
        foreach ($http_response_header ?? [] as $line) {
            if (preg_match('#^HTTP/\S+\s+(\d{3})#', $line, $m)) {
                $status = (int) $m[1];
            }
        }
        return [$status, $body];
    }

    private static function store(string $file, string $body): void
    {
        $dir = dirname($file);
        if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
            return;
        }
        $tmp = $file . '.' . bin2hex(random_bytes(4));
        if (@file_put_contents($tmp, $body) !== false) {
            @rename($tmp, $file);
        }
        // Limpieza ocasional: borra respuestas de más de un día.
        if (random_int(1, 50) === 1) {
            foreach (glob($dir . '/*.json') ?: [] as $old) {
                if (filemtime($old) < time() - 86400) {
                    @unlink($old);
                }
            }
        }
    }
}
