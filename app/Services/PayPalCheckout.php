<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\ActionError;

/**
 * PayPal Checkout (Orders v2). Credenciales: archivo o panel (PayPalSettings).
 * Modo sandbox o live según paypal.mode.
 */
final class PayPalCheckout
{
    private const SANDBOX = 'https://api-m.sandbox.paypal.com';
    private const LIVE = 'https://api-m.paypal.com';

    public static function configured(): bool
    {
        return PayPalSettings::configured();
    }

    public static function clientId(): string
    {
        return PayPalSettings::clientId();
    }

    private static function base(): string
    {
        return PayPalSettings::mode() === 'live' ? self::LIVE : self::SANDBOX;
    }

    private static function token(): string
    {
        $c = PayPalSettings::resolve();
        $id = $c['client_id'];
        $secret = $c['secret'];
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
        $err = curl_error($ch);
        curl_close($ch);
        if ($raw === false) {
            throw new RuntimeException('No se pudo conectar con PayPal' . ($err !== '' ? ': ' . $err : '.'));
        }
        if ($code < 200 || $code >= 300) {
            throw new RuntimeException(self::friendlyError($raw, $code, 'No se pudo autenticar con PayPal. Revisa Client ID, Secret y el modo (Live/Sandbox).'));
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
        if ($amountCents < 1) {
            throw new RuntimeException('El monto mínimo para PayPal es 0.01 USD.');
        }
        $value = number_format($amountCents / 100, 2, '.', '');
        // Siempre dominio canónico: evita return_url en ond-s.com / http que rompe el checkout Live.
        $configured = rtrim((string) \Trevix\Core\Config::get('app.url', ''), '/');
        $returnBase = $configured !== ''
            ? $configured . '/paypal-return.php'
            : rtrim(absolute_url('paypal-return.php'), '/');
        $payload = json_encode([
            'intent' => 'CAPTURE',
            'purchase_units' => [[
                'reference_id' => mb_substr(preg_replace('/[^A-Za-z0-9:_-]/', '', $reference) ?: 'topup', 0, 120),
                'description'  => 'Recarga TREVIX',
                'amount'       => ['currency_code' => 'USD', 'value' => $value],
            ]],
            // Forma actual de Orders v2 (application_context está deprecado).
            'payment_source' => [
                'paypal' => [
                    'experience_context' => [
                        'brand_name'          => 'TREVIX',
                        'user_action'         => 'PAY_NOW',
                        'shipping_preference' => 'NO_SHIPPING',
                        // GUEST_CHECKOUT facilita pagar sin la sesión de la app nativa del comercio.
                        'landing_page'        => 'GUEST_CHECKOUT',
                        'payment_method_preference' => 'UNRESTRICTED',
                        'locale'              => 'es-CO',
                        'return_url'          => $returnBase,
                        'cancel_url'          => $returnBase . '?cancel=1',
                    ],
                ],
            ],
        ], JSON_THROW_ON_ERROR);
        $data = self::api('POST', '/v2/checkout/orders', $payload);
        $id = (string) ($data['id'] ?? '');
        $url = '';
        foreach ($data['links'] ?? [] as $link) {
            $rel = (string) ($link['rel'] ?? '');
            if ($rel === 'approve' || $rel === 'payer-action') {
                $url = (string) ($link['href'] ?? '');
                if ($url !== '') {
                    break;
                }
            }
        }
        if ($id === '' || $url === '') {
            throw new RuntimeException('PayPal no generó el pedido.');
        }
        return ['order_id' => $id, 'approval_url' => $url];
    }

    /** @return array<string, mixed> */
    public static function getOrder(string $orderId): array
    {
        return self::api('GET', '/v2/checkout/orders/' . rawurlencode($orderId));
    }

    /** @return array<string, mixed> */
    public static function capture(string $orderId): array
    {
        // Antes de capturar, comprobar estado para mensajes claros.
        try {
            $order = self::getOrder($orderId);
            $status = strtoupper((string) ($order['status'] ?? ''));
            if ($status === 'COMPLETED') {
                return $order;
            }
            if ($status === 'CREATED' || $status === 'PAYER_ACTION_REQUIRED') {
                throw new RuntimeException(
                    'Todavía no completaste el pago en PayPal. Abre el enlace, aprueba el pago y luego pulsa Confirmar.'
                );
            }
            if ($status === 'VOIDED' || $status === 'CANCELLED') {
                throw new RuntimeException('Este pago de PayPal fue cancelado. Inicia uno nuevo.');
            }
        } catch (RuntimeException $e) {
            if (str_contains($e->getMessage(), 'Todavía no') || str_contains($e->getMessage(), 'cancelado')) {
                throw $e;
            }
            // Si getOrder falla, intentamos capture igual (puede ser red puntual).
        }
        return self::api('POST', '/v2/checkout/orders/' . rawurlencode($orderId) . '/capture', '{}');
    }

    /**
     * Prueba OAuth + creación de pedido de 0.01 USD (no se captura).
     *
     * @return array{ok:bool, mode:string, source:string, client_id_prefix:string, oauth:bool, order_id?:string, approval_url?:string, error?:string}
     */
    public static function selfTest(): array
    {
        $c = PayPalSettings::resolve();
        $out = [
            'ok'               => false,
            'mode'             => $c['mode'],
            'source'           => $c['source'],
            'client_id_prefix' => $c['client_id'] !== '' ? substr($c['client_id'], 0, 8) . '…' : '',
            'oauth'            => false,
        ];
        if ($c['client_id'] === '' || $c['secret'] === '') {
            $out['error'] = 'PayPal no está configurado (falta Client ID o Secret).';
            return $out;
        }
        try {
            self::token();
            $out['oauth'] = true;
            $order = self::createOrder(1, 'diag:' . date('YmdHis'));
            $out['order_id'] = $order['order_id'];
            $out['approval_url'] = $order['approval_url'];
            $out['ok'] = true;
        } catch (\Throwable $e) {
            $out['error'] = $e->getMessage();
        }
        return $out;
    }

    /** @return array<string, mixed> */
    private static function api(string $method, string $path, ?string $body = null): array
    {
        $ch = curl_init(self::base() . $path);
        $headers = [
            'Content-Type: application/json',
            'Authorization: Bearer ' . self::token(),
            'Prefer: return=representation',
        ];
        // Idempotencia en create/capture evita doble cobro por reintentos.
        if ($method === 'POST') {
            $headers[] = 'PayPal-Request-Id: ' . bin2hex(random_bytes(16));
        }
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
        $err = curl_error($ch);
        curl_close($ch);
        if ($raw === false) {
            throw new RuntimeException('Error de red con PayPal' . ($err !== '' ? ': ' . $err : '.'));
        }
        $data = json_decode((string) $raw, true);
        if (!is_array($data) || $code < 200 || $code >= 300) {
            throw new RuntimeException(self::friendlyError((string) $raw, $code));
        }
        return $data;
    }

    private static function friendlyError(string $raw, int $code, string $fallback = 'PayPal rechazó la operación.'): string
    {
        $data = json_decode($raw, true);
        $name = '';
        $detail = '';
        $issue = '';
        $debugId = '';
        if (is_array($data)) {
            $name = (string) ($data['name'] ?? $data['error'] ?? '');
            $detail = (string) ($data['message'] ?? $data['error_description'] ?? '');
            $debugId = (string) ($data['debug_id'] ?? '');
            $details = $data['details'] ?? null;
            if (is_array($details) && isset($details[0]) && is_array($details[0])) {
                $issue = (string) ($details[0]['issue'] ?? '');
                if ($detail === '' && !empty($details[0]['description'])) {
                    $detail = (string) $details[0]['description'];
                }
            }
        }
        $suffix = $debugId !== '' ? " [debug_id: $debugId]" : ($code > 0 ? " (HTTP $code)" : '');

        $key = strtoupper($issue !== '' ? $issue : $name);
        return match (true) {
            $key === 'ORDER_NOT_APPROVED', $key === 'PAYER_ACTION_REQUIRED'
                => 'Todavía no completaste el pago en PayPal. Aprueba el pago en el navegador y luego pulsa Confirmar.',
            $key === 'INSTRUMENT_DECLINED'
                => 'PayPal rechazó el medio de pago. Prueba otra tarjeta o cuenta.',
            $key === 'ORDER_ALREADY_CAPTURED', $key === 'ORDER_ALREADY_COMPLETED'
                => 'Este pago ya fue confirmado. Revisa tu saldo.',
            $key === 'RESOURCE_NOT_FOUND'
                => 'El pedido de PayPal ya no existe. Inicia un pago nuevo.',
            $key === 'INVALID_RESOURCE_ID'
                => 'El identificador del pedido no es válido. Inicia un pago nuevo.',
            $key === 'AUTHENTICATION_FAILURE', $key === 'INVALID_CLIENT', $key === 'NOT_AUTHORIZED'
                => 'Credenciales PayPal inválidas o modo incorrecto (Live vs Sandbox). Revisa Admin › Monedero › PayPal.' . $suffix,
            $key === 'PAYEE_ACCOUNT_RESTRICTED', $key === 'PAYEE_ACCOUNT_LOCKED', $key === 'PAYEE_NOT_ENABLED'
                => 'PayPal rechaza recibir pagos en la cuenta vinculada a estas credenciales Live (recepción restringida). '
                    . 'Confirma en developer.paypal.com que Client ID + Secret son de la app Live de la misma cuenta Business, '
                    . 'que puede recibir pagos, y pásale a soporte este código' . $suffix . '.',
            $key === 'UNPROCESSABLE_ENTITY' && str_contains(strtolower($detail), 'currency')
                => 'PayPal no aceptó la moneda. TREVIX usa USD.' . $suffix,
            $detail !== ''
                => 'PayPal: ' . ($issue !== '' ? $issue . ' — ' : '') . $detail . $suffix,
            default
                => $fallback . $suffix,
        };
    }
}
