<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use RuntimeException;
use Trevix\Core\Config;
use Trevix\Models\AppSetting;

/**
 * Credenciales PayPal: config/local.php o paypal.credentials.php tienen prioridad; si no, app_settings (panel).
 */
final class PayPalSettings
{
    private const CIPHER = 'AES-256-CBC';

    /** @return array{client_id: string, secret: string, mode: string, source: string} */
    public static function resolve(): array
    {
        $file = (array) Config::get('app.paypal', []);
        $cid = trim((string) ($file['client_id'] ?? ''));
        $sec = trim((string) ($file['secret'] ?? ''));
        $mode = self::normalizeMode((string) ($file['mode'] ?? 'sandbox'));
        if ($cid !== '' && $sec !== '') {
            return ['client_id' => $cid, 'secret' => $sec, 'mode' => $mode, 'source' => 'file'];
        }

        $cid = trim(AppSetting::get('paypal_client_id'));
        $sec = self::decrypt(AppSetting::get('paypal_secret'));
        $mode = self::normalizeMode(AppSetting::get('paypal_mode') ?: $mode);
        return ['client_id' => $cid, 'secret' => $sec, 'mode' => $mode, 'source' => $cid !== '' || $sec !== '' ? 'panel' : 'none'];
    }

    public static function configured(): bool
    {
        $c = self::resolve();
        return $c['client_id'] !== '' && $c['secret'] !== '';
    }

    public static function clientId(): string
    {
        return self::resolve()['client_id'];
    }

    public static function mode(): string
    {
        return self::resolve()['mode'];
    }

    /**
     * Guarda credenciales en app_settings y verifica OAuth. $secret vacío conserva el actual.
     *
     * @return array{client_id: string, mode: string, source: string}
     */
    public static function saveFromPanel(string $clientId, string $secret, string $mode): array
    {
        $clientId = trim($clientId);
        if (strlen($clientId) < 20) {
            throw new DomainException('El Client ID de PayPal no es válido.');
        }
        $mode = self::normalizeMode($mode);
        $current = self::decrypt(AppSetting::get('paypal_secret'));
        $newSecret = trim($secret) !== '' ? trim($secret) : $current;
        if ($newSecret === '') {
            throw new DomainException('Escribe el Secret de PayPal (o déjalo vacío solo si ya lo guardaste antes).');
        }
        if ($clientId === $newSecret) {
            throw new DomainException('El Secret no puede ser igual al Client ID. En Developer copia «Secret key», no el Client ID otra vez.');
        }
        self::verifyOAuth($clientId, $newSecret, $mode);

        AppSetting::set('paypal_client_id', $clientId);
        AppSetting::set('paypal_secret', self::encrypt($newSecret));
        AppSetting::set('paypal_mode', $mode);

        return ['client_id' => $clientId, 'mode' => $mode, 'source' => 'panel'];
    }

    public static function verifyOAuth(string $clientId, string $secret, string $mode): void
    {
        $base = $mode === 'live' ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com';
        $ch = curl_init($base . '/v1/oauth2/token');
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_USERPWD        => $clientId . ':' . $secret,
            CURLOPT_POSTFIELDS     => 'grant_type=client_credentials',
            CURLOPT_HTTPHEADER     => ['Accept: application/json', 'Accept-Language: en_US'],
            CURLOPT_TIMEOUT        => 30,
        ]);
        $raw = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($raw === false || $code < 200 || $code >= 300) {
            throw new DomainException('PayPal rechazó las credenciales. Revisa Client ID, Secret y si elegiste Live o Sandbox.');
        }
        $data = json_decode((string) $raw, true);
        if (!is_array($data) || trim((string) ($data['access_token'] ?? '')) === '') {
            throw new RuntimeException('PayPal no devolvió un token válido.');
        }
    }

    private static function normalizeMode(string $mode): string
    {
        return $mode === 'live' ? 'live' : 'sandbox';
    }

    private static function cryptoKey(): string
    {
        $parts = [
            (string) Config::get('database.password', ''),
            (string) Config::get('app.url', ''),
            (string) Config::get('app.name', 'TREVIX'),
        ];
        return hash('sha256', implode('|', $parts), true);
    }

    private static function encrypt(string $plain): string
    {
        $iv = random_bytes(16);
        $enc = openssl_encrypt($plain, self::CIPHER, self::cryptoKey(), OPENSSL_RAW_DATA, $iv);
        if ($enc === false) {
            throw new RuntimeException('No se pudo cifrar el secret de PayPal.');
        }
        return base64_encode($iv . $enc);
    }

    private static function decrypt(string $stored): string
    {
        $stored = trim($stored);
        if ($stored === '') {
            return '';
        }
        $raw = base64_decode($stored, true);
        if ($raw === false || strlen($raw) < 17) {
            return '';
        }
        $iv = substr($raw, 0, 16);
        $payload = substr($raw, 16);
        $plain = openssl_decrypt($payload, self::CIPHER, self::cryptoKey(), OPENSSL_RAW_DATA, $iv);
        return is_string($plain) ? $plain : '';
    }
}