<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Models\PushDevice;

/** Avisa por Firebase que hay una llamada LiveKit entrante (Android se despierta y la app hace poll). */
final class LiveKitNotify
{
    public static function incomingCall(int $peerId, int $sessionId, string $kind): void
    {
        if (!Fcm::configured() || $peerId < 1 || $sessionId < 1) {
            return;
        }
        $devices = PushDevice::forUsers([$peerId]);
        if ($devices === []) {
            return;
        }
        $messages = [];
        foreach ($devices as $i => $device) {
            $messages['lk' . $i] = [
                'token' => (string) $device['fcm_token'],
                'data'  => [
                    'type'        => 'livekit_call',
                    'session_id'  => (string) $sessionId,
                    'kind'        => $kind,
                ],
                'android' => ['priority' => 'HIGH', 'ttl' => '120s'],
                'apns'    => [
                    'headers' => ['apns-priority' => '10', 'apns-push-type' => 'alert'],
                    'payload' => [
                        'aps' => [
                            'alert' => [
                                'title' => 'TREVIX',
                                'body'  => $kind === 'video' ? 'Videollamada entrante' : 'Llamada entrante',
                            ],
                            'sound' => 'default',
                        ],
                    ],
                ],
            ];
        }
        PushNotifier::record(Fcm::sendMany($messages), []);
    }
}