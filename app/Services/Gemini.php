<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;

/**
 * Cliente de la API de Gemini (Google AI Studio): generateContent con salida JSON según un esquema. Solo HTTPS con
 * certificado verificado; la clave viaja en la cabecera x-goog-api-key, nunca en la URL.
 */
final class Gemini
{
    private const ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent';
    private const MAX_BYTES = 1024 * 1024;

    public static function configured(): bool
    {
        return self::key() !== '';
    }

    /**
     * @param list<array{role:string, parts:list<array>}> $contents turnos de la conversación (user / model)
     * @param array $schema esquema de la respuesta (subconjunto de OpenAPI que acepta Gemini)
     * @return array la respuesta del modelo ya decodificada según el esquema
     * @throws RuntimeException si no hay clave, el servicio falla o la respuesta no es JSON válido.
     */
    public static function json(string $system, array $contents, array $schema, float $temperature = 0.7): array
    {
        $key = self::key();
        if ($key === '') {
            throw new RuntimeException('IX no tiene configurada la clave de Gemini.');
        }
        $payload = json_encode([
            'systemInstruction' => ['parts' => [['text' => $system]]],
            'contents'          => $contents,
            'generationConfig'  => [
                'temperature'      => $temperature,
                'responseMimeType' => 'application/json',
                'responseSchema'   => $schema,
            ],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);

        $model = (string) Config::get('app.ix.model', 'gemini-flash-latest');
        if (!preg_match('/^[a-z0-9.\-]+$/', $model)) {
            throw new RuntimeException('Modelo de Gemini no válido.');
        }
        [$status, $body] = self::post(sprintf(self::ENDPOINT, $model), $key, $payload);
        $data = json_decode($body, true);
        if ($status < 200 || $status >= 300 || !is_array($data)) {
            $reason = is_array($data) ? (string) ($data['error']['status'] ?? $data['error']['message'] ?? '') : '';
            throw new RuntimeException('Gemini respondió HTTP ' . $status . ($reason !== '' ? ' (' . mb_substr($reason, 0, 120) . ')' : '') . '.');
        }

        $candidate = $data['candidates'][0] ?? null;
        $text = '';
        foreach ((array) ($candidate['content']['parts'] ?? []) as $part) {
            if (is_array($part) && empty($part['thought']) && isset($part['text'])) {
                $text .= (string) $part['text'];
            }
        }
        if ($text === '') {
            $why = (string) ($candidate['finishReason'] ?? $data['promptFeedback']['blockReason'] ?? 'sin texto');
            throw new RuntimeException('Gemini no devolvió respuesta (' . $why . ').');
        }
        $result = json_decode(trim($text), true);
        if (!is_array($result)) {
            throw new RuntimeException('Gemini devolvió una respuesta que no es JSON.');
        }
        return $result;
    }

    private static function key(): string
    {
        return trim((string) Config::get('app.ix.api_key', ''));
    }

    /** @return array{0:int, 1:string} */
    private static function post(string $url, string $key, string $payload): array
    {
        if (!function_exists('curl_init')) {
            throw new RuntimeException('El servidor no tiene cURL.');
        }
        $timeout = max(5, (int) Config::get('app.ix.timeout', 30));
        $body = '';
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $payload,
            CURLOPT_RETURNTRANSFER => false,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_PROTOCOLS      => CURLPROTO_HTTPS,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_ENCODING       => '',
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'Accept: application/json',
                'x-goog-api-key: ' . $key,
                'User-Agent: TREVIX/1.0 (+https://trevix.ond-s.com)',
            ],
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
            throw new RuntimeException('No se pudo conectar con Gemini: ' . $error);
        }
        return [$status, $body];
    }
}
