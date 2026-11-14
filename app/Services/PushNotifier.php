<?php
declare(strict_types=1);

namespace Trevix\Services;

use Throwable;
use Trevix\Core\Config;
use Trevix\Core\Database;
use Trevix\Core\Deferred;
use Trevix\Core\Lang;
use Trevix\Models\Push;
use Trevix\Models\PushCampaign;
use Trevix\Models\PushDevice;

/**
 * Avisa por Firebase a los teléfonos de quien recibió algo (un aviso, un mensaje, una reacción o una solicitud).
 * Durante la petición solo se anota a quién avisar; el envío corre después de entregar la respuesta (Deferred), todo
 * junto y en paralelo, así quien actúa no espera a Firebase.
 *
 * Android: mensaje de datos de alta prioridad que despierta la app aunque esté cerrada; la app consulta GET me/push y
 * muestra lo nuevo con sus cursores (los avisos que se juntan se colapsan en uno y nada se muestra dos veces).
 * iPhone: el servidor arma cada aviso (los mismos textos que Android) desde los cursores guardados del teléfono y
 * Firebase lo entrega por APNs; cada aviso lleva su clave como apns-collapse-id para que nunca se vea repetido.
 */
final class PushNotifier
{
    /** Máximo de avisos visibles por iPhone en un envío (si se juntan más, se envían los más recientes). */
    private const IOS_MAX = 6;

    /** @var array<int, true> */
    private static array $users = [];
    /** @var array<int, int> conversación => quien envió */
    private static array $conversations = [];
    /** @var array<int, int> conversación => primer mensaje nuevo de este envío */
    private static array $firstMessage = [];
    /** @var array<int, true> mensajes que recibieron una reacción */
    private static array $reactions = [];
    private static bool $scheduled = false;
    private static bool $slow = false;

    /** Personas con algo nuevo. $slow: lo nuevo es una reacción, que GET me/push incluye con un segundo de retraso. */
    public static function users(array $userIds, bool $slow = false): void
    {
        if (!self::enabled()) {
            return;
        }
        foreach ($userIds as $id) {
            if ((int) $id > 0) {
                self::$users[(int) $id] = true;
            }
        }
        self::$slow = self::$slow || $slow;
        self::schedule();
    }

    public static function user(int $userId, bool $slow = false): void
    {
        self::users([$userId], $slow);
    }

    /** Mensaje nuevo en una conversación: se avisa a las demás personas que siguen en ella. */
    public static function conversation(int $conversationId, int $senderId, int $messageId = 0): void
    {
        if (!self::enabled() || $conversationId < 1) {
            return;
        }
        self::$conversations[$conversationId] = $senderId;
        if ($messageId > 0 && !isset(self::$firstMessage[$conversationId])) {
            self::$firstMessage[$conversationId] = $messageId;
        }
        self::schedule();
    }

    /** Reacción a un mensaje: se avisa a quien lo envió (GET me/push ya descarta las propias y los bloqueos). */
    public static function reaction(int $messageId): void
    {
        if (!self::enabled() || $messageId < 1) {
            return;
        }
        self::$reactions[$messageId] = true;
        self::$slow = true;
        self::schedule();
    }

    private static function enabled(): bool
    {
        static $enabled = null;
        return $enabled ??= Fcm::configured();
    }

    private static function schedule(): void
    {
        if (!self::$scheduled) {
            self::$scheduled = true;
            Deferred::run([self::class, 'flush']);
        }
    }

    /** @internal Corre después de entregar la respuesta. */
    public static function flush(): void
    {
        self::$scheduled = false;
        if (self::$slow) {
            usleep(1_200_000);
        }
        $users = self::$users;
        $firstMessage = [];
        foreach (self::$conversations as $conversationId => $senderId) {
            $from = self::$firstMessage[$conversationId] ?? 0;
            foreach (PushDevice::conversationRecipients($conversationId, $senderId) as $id) {
                $users[$id] = true;
                if ($from > 0) {
                    $firstMessage[$id] = min($firstMessage[$id] ?? PHP_INT_MAX, $from);
                }
            }
        }
        foreach (PushDevice::messageSenders(array_keys(self::$reactions)) as $id) {
            $users[$id] = true;
        }
        self::$users = [];
        self::$conversations = [];
        self::$firstMessage = [];
        self::$reactions = [];
        self::$slow = false;
        if ($users === []) {
            return;
        }
        Database::ensureAlive();
        $locale = Lang::locale();
        try {
            foreach (array_chunk(array_keys($users), 500) as $chunk) {
                self::deliver(PushDevice::forUsers($chunk), $firstMessage);
            }
        } finally {
            Lang::use($locale);
        }
    }

    /**
     * @param list<array> $devices
     * @param array<int, int> $firstMessage persona => primer mensaje nuevo que va dentro del aviso de Android
     */
    private static function deliver(array $devices, array $firstMessage = []): void
    {
        $messages = [];
        $owner = [];
        foreach ($devices as $device) {
            $id = (int) $device['id'];
            if ($device['platform'] === 'android') {
                $from = $firstMessage[(int) $device['user_id']] ?? 0;
                $messages['a' . $id] = self::androidSync((string) $device['fcm_token'], $from > 0 ? self::androidItems($device, $from) : '');
                $owner['a' . $id] = $id;
                continue;
            }
            foreach (self::iosAlerts($device) as $n => $message) {
                $messages['i' . $id . '-' . $n] = $message;
                $owner['i' . $id . '-' . $n] = $id;
            }
        }
        if ($messages === []) {
            return;
        }
        self::record(Fcm::sendMany($messages), $owner);
    }

    /**
     * Resultado del envío por teléfono: los tokens que Firebase da por muertos se borran (desinstalaron la app o
     * cambió el token) y los demás errores se anotan para el panel.
     *
     * @param array<string, array{ok:bool, status:int, error:string}> $results
     * @param array<string, int> $owner
     * @return array{sent:int, failed:int}
     */
    public static function record(array $results, array $owner): array
    {
        $ok = [];
        $errors = [];
        $dead = [];
        foreach ($results as $key => $result) {
            $device = $owner[$key] ?? 0;
            if ($result['ok']) {
                $ok[$device] = $device;
            } elseif (in_array($result['error'], Fcm::DEAD, true)) {
                $dead[$device] = $device;
            } else {
                $errors[$device] = $result['error'] !== '' ? $result['error'] : 'HTTP_' . $result['status'];
            }
        }
        PushDevice::delete(array_values($dead));
        PushDevice::markResults(array_values(array_diff_key($ok, $errors, $dead)), array_diff_key($errors, $dead));
        $sent = count(array_filter($results, static fn (array $r): bool => $r['ok']));
        return ['sent' => $sent, 'failed' => count($results) - $sent];
    }

    /**
     * Mensaje de datos que despierta la app de Android; collapse_key junta los que no alcanzaron a llegar. $items: los
     * mensajes nuevos ya armados (JSON), para mostrarlos sin esperar a GET me/push.
     */
    private static function androidSync(string $token, string $items = ''): array
    {
        return [
            'token'   => $token,
            'data'    => $items !== '' ? ['type' => 'sync', 'items' => $items] : ['type' => 'sync'],
            'android' => ['priority' => 'HIGH', 'collapse_key' => 'sync', 'ttl' => '86400s'],
        ];
    }

    /** Firebase admite 4 KB de datos: si los mensajes no caben, el teléfono los pide con GET me/push como siempre. */
    private static function androidItems(array $device, int $fromMessage): string
    {
        try {
            Lang::use((string) ($device['locale'] ?? Lang::DEFAULT) ?: Lang::DEFAULT);
            $items = PushFeed::messagesFrom((int) $device['user_id'], $fromMessage);
            while ($items !== []) {
                $json = (string) json_encode($items, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
                if (strlen($json) <= 3200) {
                    return $json;
                }
                array_shift($items);
            }
        } catch (Throwable $e) {
            error_log('[Push] ' . $e::class . ': ' . $e->getMessage());
        }
        return '';
    }

    /**
     * Avisos visibles para un iPhone desde sus cursores. Los cursores se reclaman antes de enviar: si otro envío los
     * tomó primero, este no manda nada (no se repiten avisos).
     *
     * @return list<array>
     */
    private static function iosAlerts(array $device): array
    {
        $raw = $device['cursor_json'] !== null ? (string) $device['cursor_json'] : null;
        $cursor = $raw !== null ? json_decode($raw, true) : null;
        $uid = (int) $device['user_id'];
        if (!is_array($cursor) || !PushFeed::validDate((string) ($cursor['r'] ?? ''))) {
            PushDevice::claimCursor((int) $device['id'], $raw, Push::cursors($uid));
            return [];
        }
        Lang::use((string) ($device['locale'] ?? Lang::DEFAULT) ?: Lang::DEFAULT);
        $feed = PushFeed::collect($uid, [
            'n' => (int) ($cursor['n'] ?? 0),
            'm' => (int) ($cursor['m'] ?? 0),
            'f' => (int) ($cursor['f'] ?? 0),
            'r' => (string) $cursor['r'],
        ]);
        if (!PushDevice::claimCursor((int) $device['id'], $raw, $feed['cursor']) || $feed['items'] === []) {
            return [];
        }
        $out = [];
        foreach (array_slice($feed['items'], -self::IOS_MAX) as $item) {
            $out[] = self::iosMessage((string) $device['fcm_token'], $item);
        }
        return $out;
    }

    /** Aviso visible de iPhone. thread-id agrupa por chat; apns-collapse-id evita verlo dos veces. */
    public static function iosMessage(string $token, array $item): array
    {
        $thread = isset($item['conversation_id']) ? 'chat-' . (int) $item['conversation_id'] : (string) ($item['kind'] ?? 'trevix');
        $private = ($item['kind'] ?? '') === 'private';
        $chat = $private || isset($item['conversation_id']);
        return [
            'token'        => $token,
            'notification' => [
                'title' => mb_strimwidth((string) $item['title'], 0, 80, '…'),
                'body'  => mb_strimwidth((string) $item['text'], 0, 240, '…'),
            ],
            'data' => [
                'trevix_link' => (string) ($item['link'] ?? ''),
                'trevix_key'  => (string) $item['key'],
            ],
            'apns' => [
                'headers' => [
                    'apns-priority'    => '10',
                    'apns-push-type'   => 'alert',
                    'apns-collapse-id' => $private ? 'private' : substr((string) $item['key'], 0, 64),
                    'apns-expiration'  => (string) (time() + 86400),
                ],
                // Tonos propios que la app copia a Library/Sounds; si aún no están (app antigua), suena el del sistema.
                'payload' => ['aps' => ['sound' => $chat ? 'trevix_mensaje.wav' : 'trevix_aviso.wav', 'thread-id' => $thread]],
            ],
        ];
    }

    /** Aviso del panel de administración para Android: lo muestra la app tal cual, sin consultar nada. */
    public static function androidShow(string $token, string $key, string $title, string $body, string $link): array
    {
        return [
            'token'   => $token,
            'data'    => ['type' => 'show', 'key' => $key, 'title' => $title, 'body' => $body, 'link' => $link],
            'android' => ['priority' => 'HIGH', 'collapse_key' => $key, 'ttl' => '259200s'],
        ];
    }

    /** Envío del panel, por tandas (continúa desde last_device_id si se interrumpió). */
    public static function campaign(int $campaignId): void
    {
        @set_time_limit(600);
        $campaign = PushCampaign::find($campaignId);
        if ($campaign === null || $campaign['status'] !== 'sending') {
            return;
        }
        $platform = in_array($campaign['audience'], PushDevice::PLATFORMS, true) ? (string) $campaign['audience'] : null;
        $userId = $campaign['audience'] === 'user' ? (int) $campaign['target_user_id'] : null;
        if ($campaign['audience'] === 'user' && $userId < 1) {
            PushCampaign::finish($campaignId, 'failed', 'La persona ya no existe.');
            return;
        }
        $after = (int) $campaign['last_device_id'];
        $key = 'p' . $campaignId;
        $link = (string) ($campaign['link'] ?? '');
        $batch = max(50, min(1000, (int) Config::get('app.push.batch', 500)));
        try {
            while (true) {
                $devices = PushDevice::batch($platform, $after, $batch, $userId);
                if ($devices === []) {
                    break;
                }
                $messages = [];
                $owner = [];
                foreach ($devices as $device) {
                    $id = (int) $device['id'];
                    $token = (string) $device['fcm_token'];
                    $messages['d' . $id] = $device['platform'] === 'android'
                        ? self::androidShow($token, $key, (string) $campaign['title'], (string) $campaign['body'], $link)
                        : self::iosMessage($token, ['key' => $key, 'kind' => 'trevix', 'title' => $campaign['title'], 'text' => $campaign['body'], 'link' => $link]);
                    $owner['d' . $id] = $id;
                    $after = $id;
                }
                $result = self::record(Fcm::sendMany($messages), $owner);
                PushCampaign::progress($campaignId, $after, $result['sent'], $result['failed']);
            }
            PushCampaign::finish($campaignId, 'done');
        } catch (Throwable $e) {
            error_log('[Push] ' . $e::class . ': ' . $e->getMessage());
            PushCampaign::finish($campaignId, 'failed', mb_substr($e->getMessage(), 0, 250));
        }
    }
}
