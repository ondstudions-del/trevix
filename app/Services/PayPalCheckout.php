<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Core\Config;

/**
 * PayPal Checkout (Orders v2). Credenciales en config/local.php → app.paypal.
 * Modo sandbox o live según paypal.mode.
 */
final class PayPalCheckout
{
    private const SANDBOX = 'https://api-m.sandbox.paypal.com';
    private const LIVE = 'https://api-m.paypal.com';

    public static function configured(): bool
    {
        $c = (array) Config::get('app.paypal', []);
        return trim((string) ($c['client_id'] ?? '')) !== '' && trim((string) ($c['secret'] ?? '')) !== '';
    }

    public static function clientId(): string
    {
        return trim((string) Config::get('app.paypal.client_id', ''));
    }

    private static function base(): string
    {
        return (Config::get('app.paypal.mode', 'sandbox') === 'live') ? self::LIVE : self::SANDBOX;
    }

    private static function token(): string
    {
        $id = trim((string) Config::get('app.paypal.client_id', ''));
        $secret = trim((string) Config::get('app.paypal.secret', ''));
        if ($id === '' || $secret === '') {
            throw new ActionError('PayPal no está configurado en el servidor.', 503);
        }
        $ch = curl_init(self::base() . '/v1/oauth2/token');
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_USERPWD        => $id . ':' . $secret,
            CURLOPT_POSTFIELDS     => 'grant_type=client_credentials',
            CURLOPT_HTTPHEADER     => ['Accept: application/json', 'Accept-Language: en_US'],
            CURLOPT_TIMEOUT        => 30,
        ]);
        $raw = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($raw === false || $code < 200 || $code >= 300) {
            throw new RuntimeException('No se pudo conectar con PayPal.');
        }
        $data = json_decode((string) $raw, true);
        $token = is_array($data) ? (string) ($data['access_token'] ?? '') : '';
        if ($token === '') {
            throw new RuntimeException('PayPal no devolvió un token válido.');
        }
        return $token;
    }

    /**
     * @return array{order_id: string, approval_url: string}
     */
    public static function createOrder(int $amountCents, string $reference): array
    {
        $value = number_format($amountCents / 100, 2, '.', '');
        $payload = json_encode([
            'intent' => 'CAPTURE',
            'purchase_units' => [[
                'reference_id' => mb_substr($reference, 0, 120),
                'amount'       => ['currency_code' => 'USD', 'value' => $value],
            ]],
            'application_context' => [
                'brand_name'          => 'TREVIX',
                'user_action'         => 'PAY_NOW',
                'shipping_preference' => 'NO_SHIPPING',
            ],
        ], JSON_THROW_ON_ERROR);
        $data = self::api('POST', '/v2/checkout/orders', $payload);
        $id = (string) ($data['id'] ?? '');
        $url = '';
        foreach ($data['links'] ?? [] as $link) {
            if (($link['rel'] ?? '') === 'approve') {
                $url = (string) ($link['href'] ?? '');
                break;
            }
        }
        if ($id === '' || $url === '') {
            throw new RuntimeException('PayPal no generó el pedido.');
        }
        return ['order_id' => $id, 'approval_url' => $url];
    }

    /** @return array<string, mixed> */
    public static function capture(string $orderId): array
    {
        return self::api('POST', '/v2/checkout/orders/' . rawurlencode($orderId) . '/capture', '{}');
    }

    /** @return array<string, mixed> */
    private static function api(string $method, string $path, ?string $body = null): array
    {
        $ch = curl_init(self::base() . $path);
        $headers = [
            'Content-Type: application/json',
            'Authorization: Bearer ' . self::token(),
        ];
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_TIMEOUT        => 45,
        ]);
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
        }
        $raw = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($raw === false) {
            throw new RuntimeException('Error de red con PayPal.');
        }
        $data = json_decode((string) $raw, true);
        if (!is_array($data) || $code < 200 || $code >= 300) {
            throw new RuntimeException('PayPal rechazó la operación.');
        }
        return $data;
    }
}