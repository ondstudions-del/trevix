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
    private const HEADERS = ['Accept: application/json', 'User-Agent: TREVIX/1.0 (+https://trevix.ond-s.com)'];

    /**
     * @param int $ttl segundos de caché (0 = sin caché)
     * @throws RuntimeException si el servicio no responde o la respuesta no es JSON.
     */
    public static function getJson(string $url, int $ttl = 0): array
    {
        if (!str_starts_with($url, 'https://')) {
            throw new RuntimeException('URL no permitida.');
        }
        $cached = self::cached($url, $ttl);
        if ($cached !== null) {
            return $cached;
        }

        [$status, $body] = self::fetch($url, self::timeout());
        return self::decode($url, $ttl, $status, $body);
    }

    /**
     * Varias peticiones GET a la vez (curl_multi): tarda lo que la más lenta, no la suma de todas.
     * Una que falle no afecta a las demás.
     *
     * @param array<string, string> $urls clave => URL
     * @return array<string, array|RuntimeException> clave => datos o el error de esa petición
     */
    public static function getJsonMany(array $urls, int $ttl = 0): array
    {
        $out = [];
        $pending = [];
        foreach ($urls as $key => $url) {
            if (!str_starts_with($url, 'https://')) {
                $out[$key] = new RuntimeException('URL no permitida.');
                continue;
            }
            $cached = self::cached($url, $ttl);
            if ($cached !== null) {
                $out[$key] = $cached;
            } else {
                $pending[$key] = $url;
            }
        }
        if (count($pending) < 2 || !function_exists('curl_multi_init')) {
            foreach ($pending as $key => $url) {
                try {
                    $out[$key] = self::getJson($url, $ttl);
                } catch (RuntimeException $e) {
                    $out[$key] = $e;
                }
            }
            return $out;
        }

        $multi = curl_multi_init();
        $handles = [];
        $bodies = [];
        foreach ($pending as $key => $url) {
            $bodies[$key] = '';
            $handles[$key] = self::handle($url, self::timeout(), $bodies[$key]);
            curl_multi_add_handle($multi, $handles[$key]);
        }
        do {
            $code = curl_multi_exec($multi, $running);
            if ($running > 0) {
                curl_multi_select($multi, 1.0);
            }
        } while ($running > 0 && $code === CURLM_OK);

        foreach ($handles as $key => $ch) {
            $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            try {
                if ($status === 0) {
                    throw new RuntimeException('No se pudo conectar con el servicio externo: ' . curl_error($ch));
                }
                $out[$key] = self::decode($pending[$key], $ttl, $status, $bodies[$key]);
            } catch (RuntimeException $e) {
                $out[$key] = $e;
            }
            curl_multi_remove_handle($multi, $ch);
            curl_close($ch);
        }
        curl_multi_close($multi);
        return $out;
    }

    private static function timeout(): int
    {
        return (int) Config::get('app.services.timeout', 8);
    }

    private static function cacheFile(string $url): string
    {
        return BASE_PATH . self::CACHE_DIR . '/' . hash('sha256', $url) . '.json';
    }

    private static function cached(string $url, int $ttl): ?array
    {
        if ($ttl <= 0) {
            return null;
        }
        $file = self::cacheFile($url);
        if (!is_file($file) || filemtime($file) <= time() - $ttl) {
            return null;
        }
        $data = json_decode((string) file_get_contents($file), true);
        return is_array($data) ? $data : null;
    }

    /** Valida la respuesta, la guarda en caché y la devuelve decodificada. */
    private static function decode(string $url, int $ttl, int $status, string $body): array
    {
        $data = json_decode($body, true);
        if ($status < 200 || $status >= 300 || !is_array($data)) {
            throw new RuntimeException('El servicio externo no respondió correctamente (HTTP ' . $status . ').');
        }
        if ($ttl > 0) {
            self::store(self::cacheFile($url), $body);
        }
        return $data;
    }

    /** Petición cURL preparada: solo HTTPS, certificado verificado, sin redirecciones y con tamaño máximo. */
    private static function handle(string $url, int $timeout, string &$body): \CurlHandle
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => false,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_CONNECTTIMEOUT => min(5, $timeout),
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_HTTPHEADER     => self::HEADERS,
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
        return $ch;
    }

    /** @return array{0:int, 1:string} [código HTTP, cuerpo] */
    private static function fetch(string $url, int $timeout): array
    {
        $headers = self::HEADERS;
        if (function_exists('curl_init')) {
            $body = '';
            $ch = self::handle($url, $timeout, $body);
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
