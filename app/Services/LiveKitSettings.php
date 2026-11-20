<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use Trevix\Core\Config;
use Trevix\Models\AppSetting;

/**
 * LiveKit: URL WebSocket y API key/secret (config/local.php, livekit.credentials.php o panel admin).
 */
final class LiveKitSettings
{
    private const CIPHER = 'AES-256-CBC';

    /** @return array{url: string, api_key: string, api_secret: string, source: string} */
    public static function resolve(): array
    {
        $file = (array) Config::get('app.livekit', []);
        $url = self::normalizeUrl((string) ($file['url'] ?? ''));
        $key = trim((string) ($file['api_key'] ?? ''));
        $sec = trim((string) ($file['api_secret'] ?? ''));
        if ($url !== '' && $key !== '' && $sec !== '') {
            return ['url' => $url, 'api_key' => $key, 'api_secret' => $sec, 'source' => 'file'];
        }

        $url = self::normalizeUrl(AppSetting::get('livekit_url'));
        $key = trim(AppSetting::get('livekit_api_key'));
        $sec = self::decrypt(AppSetting::get('livekit_api_secret'));
        $source = $url !== '' || $key !== '' || $sec !== '' ? 'panel' : 'none';
        return ['url' => $url, 'api_key' => $key, 'api_secret' => $sec, 'source' => $source];
    }

    public static function configured(): bool
    {
        $c = self::resolve();
        return $c['url'] !== '' && $c['api_key'] !== '' && $c['api_secret'] !== '';
    }

    /** Datos públicos para la app (sin secretos). */
    public static function clientConfig(): ?array
    {
        if (!self::configured()) {
            return null;
        }
        $c = self::resolve();
        return [
            'url'         => $c['url'],
            'audio_calls' => AppSetting::flag('livekit_calls_audio'),
            'video_calls' => AppSetting::flag('livekit_calls_video'),
            'live'        => AppSetting::flag('livekit_live_broadcast'),
        ];
    }

    /**
     * @param array{audio_calls?:bool, video_calls?:bool, live?:bool} $flags
     * @return array{url: string, api_key: string, source: string}
     */
    public static function saveFromPanel(
        string $url,
        string $apiKey,
        string $apiSecret,
        array $flags,
    ): array {
        $url = self::normalizeUrl($url);
        $apiKey = trim($apiKey);
        if ($url === '' || strlen($apiKey) < 6) {
            throw new DomainException('Indica la URL WebSocket de LiveKit y el API Key.');
        }
        $current = self::decrypt(AppSetting::get('livekit_api_secret'));
        $newSecret = trim($apiSecret) !== '' ? trim($apiSecret) : $current;
        if ($newSecret === '' || strlen($newSecret) < 16) {
            throw new DomainException('Escribe el API Secret de LiveKit (o déjalo vacío solo si ya lo guardaste).');
        }
        self::verifyCredentials($url, $apiKey, $newSecret);

        AppSetting::set('livekit_url', $url);
        AppSetting::set('livekit_api_key', $apiKey);
        AppSetting::set('livekit_api_secret', self::encrypt($newSecret));
        AppSetting::set('livekit_calls_audio', ($flags['audio_calls'] ?? true) ? '1' : '0');
        AppSetting::set('livekit_calls_video', ($flags['video_calls'] ?? true) ? '1' : '0');
        AppSetting::set('livekit_live_broadcast', ($flags['live'] ?? true) ? '1' : '0');

        return ['url' => $url, 'api_key' => $apiKey, 'source' => 'panel'];
    }

    private static function verifyCredentials(string $url, string $apiKey, string $secret): void
    {
        $identity = 'trevix-verify-' . bin2hex(random_bytes(4));
        $room = 'trevix-verify-' . bin2hex(random_bytes(4));
        try {
            LiveKitToken::create($apiKey, $secret, $identity, 'TREVIX', [
                'roomJoin'     => true,
                'room'         => $room,
                'canPublish'   => false,
                'canSubscribe' => true,
            ], 120);
        } catch (\Throwable) {
            throw new DomainException('No se pudo generar un token de prueba. Revisa API Key y Secret.');
        }
        if ($url === '') {
            throw new DomainException('La URL de LiveKit no es válida.');
        }
    }

    public static function normalizeUrl(string $url): string
    {
        $url = trim($url);
        if ($url === '') {
            return '';
        }
        if (!preg_match('#^wss?://#i', $url)) {
            throw new DomainException('La URL debe empezar por wss:// (por ejemplo wss://tu-proyecto.livekit.cloud).');
        }
        return rtrim($url, '/');
    }

    private static function cryptoKey(): string
    {
        $parts = [
            (string) Config::get('database.password', ''),
            (string) Config::get('app.url', ''),
            (string) Config::get('app.name', 'TREVIX'),
            'livekit-v1',
        ];
        return hash('sha256', implode('|', $parts), true);
    }

    private static function encrypt(string $plain): string
    {
        $iv = random_bytes(16);
        $raw = openssl_encrypt($plain, self::CIPHER, self::cryptoKey(), OPENSSL_RAW_DATA, $iv);
        if ($raw === false) {
            throw new DomainException('No se pudo cifrar el secret de LiveKit.');
        }
        return base64_encode($iv . $raw);
    }

    private static function decrypt(string $enc): string
    {
        if ($enc === '') {
            return '';
        }
        $bin = base64_decode($enc, true);
        if ($bin === false || strlen($bin) < 17) {
            return '';
        }
        $plain = openssl_decrypt(substr($bin, 16), self::CIPHER, self::cryptoKey(), OPENSSL_RAW_DATA, substr($bin, 0, 16));
        return $plain === false ? '' : $plain;
    }
}