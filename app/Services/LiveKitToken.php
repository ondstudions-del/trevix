<?php
declare(strict_types=1);

namespace Trevix\Services;

/**
 * JWT de acceso a LiveKit (HS256). Sin dependencias externas.
 *
 * @see https://docs.livekit.io/frontends/reference/tokens-grants/
 */
final class LiveKitToken
{
    /** @param array<string, mixed> $videoGrant */
    public static function create(
        string $apiKey,
        string $apiSecret,
        string $identity,
        ?string $name,
        array $videoGrant,
        int $ttl = 3600,
    ): string {
        $now = time();
        $payload = [
            'exp'   => $now + max(60, min(86400, $ttl)),
            'iss'   => $apiKey,
            'nbf'   => $now - 5,
            'sub'   => $identity,
            'video' => $videoGrant,
        ];
        if ($name !== null && $name !== '') {
            $payload['name'] = $name;
        }
        $header = self::base64Url(json_encode(['alg' => 'HS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR));
        $body = self::base64Url(json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
        $sig = self::base64Url(hash_hmac('sha256', $header . '.' . $body, $apiSecret, true));
        return $header . '.' . $body . '.' . $sig;
    }

    private static function base64Url(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}