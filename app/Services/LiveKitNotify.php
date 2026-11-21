<?php
declare(strict_types=1);

namespace Trevix\Services;

use Trevix\Models\Community;
use Trevix\Models\Follow;
use Trevix\Models\PushDevice;
use Trevix\Models\User;

/** Avisos Firebase para llamadas LiveKit y lives. */
final class LiveKitNotify
{
    public static function incomingCall(int $peerId, int $sessionId, string $kind, array $caller): void
    {
        if (!Fcm::configured() || $peerId < 1 || $sessionId < 1) {
            return;
        }
        $devices = PushDevice::forUsers([$peerId]);
        if ($devices === []) {
            return;
        }
        $name = (string) ($caller['display_name'] ?: $caller['username'] ?? 'Alguien');
        $username = (string) ($caller['username'] ?? '');
        $avatar = !empty($caller['avatar_path']) ? absolute_url((string) $caller['avatar_path']) : '';
        $link = 'livekit-call.php?id=' . $sessionId;
        $body = $kind === 'video' ? 'Videollamada entrante' : 'Llamada entrante';
        $messages = [];
        foreach ($devices as $i => $device) {
            $messages['lk' . $i] = [
                'token' => (string) $device['fcm_token'],
                'notification' => [
                    'title' => $name,
                    'body'  => $body,
                ],
                'data'  => [
                    'type'             => 'livekit_call',
                    'session_id'       => (string) $sessionId,
                    'kind'             => $kind,
                    'caller_name'      => $name,
                    'caller_username'  => $username,
                    'caller_avatar'    => $avatar,
                    'trevix_link'      => $link,
                ],
                'android' => [
                    'priority'     => 'HIGH',
                    'ttl'          => '120s',
                    'notification' => [
                        'channel_id' => 'trevix_llamadas_tono',
                        'sound'      => 'trevix_llamada',
                    ],
                ],
                'apns' => [
                    'headers' => ['apns-priority' => '10', 'apns-push-type' => 'alert'],
                    'payload' => [
                        'aps' => [
                            'alert' => [
                                'title' => $name,
                                'body'  => $body,
                            ],
                            'sound'             => 'default',
                            'content-available' => 1,
                        ],
                        'trevix_link'     => $link,
                        'type'            => 'livekit_call',
                        'session_id'      => (string) $sessionId,
                        'kind'            => $kind,
                        'caller_name'     => $name,
                        'caller_username' => $username,
                        'caller_avatar'   => $avatar,
                    ],
                ],
            ];
        }
        PushNotifier::record(Fcm::sendMany($messages), []);
    }

    /** Avisa a seguidores (hasta 200 dispositivos) de que alguien está en vivo. */
    public static function liveStarted(array $host, int $sessionId, ?string $title): void
    {
        if (!Fcm::configured() || $sessionId < 1) {
            return;
        }
        $hostId = (int) ($host['id'] ?? 0);
        if ($hostId < 1) {
            return;
        }
        $followerIds = Follow::followerIds($hostId, 120);
        $memberIds = [];
        foreach (Community::activeCommunityIdsForUser($hostId) as $communityId) {
            $memberIds = array_merge($memberIds, Community::activeMemberIds($communityId, $hostId, 120));
        }
        $targetIds = array_values(array_unique(array_merge($followerIds, $memberIds)));
        if ($targetIds === []) {
            return;
        }
        $devices = PushDevice::forUsers($targetIds);
        if ($devices === []) {
            return;
        }
        $name = (string) ($host['display_name'] ?: $host['username'] ?? 'Alguien');
        $username = (string) ($host['username'] ?? '');
        $link = 'livekit-live.php?id=' . $sessionId . '&u=' . rawurlencode($username);
        $body = $title !== null && $title !== ''
            ? $title
            : 'Está en vivo ahora';
        $messages = [];
        foreach (array_slice($devices, 0, 200) as $i => $device) {
            $messages['ll' . $i] = [
                'token' => (string) $device['fcm_token'],
                'data'  => [
                    'type'        => 'livekit_live',
                    'session_id'  => (string) $sessionId,
                    'username'    => $username,
                    'trevix_link' => $link,
                ],
                'android' => ['priority' => 'HIGH', 'ttl' => '600s'],
                'apns'    => [
                    'headers' => ['apns-priority' => '10', 'apns-push-type' => 'alert'],
                    'payload' => [
                        'aps' => [
                            'alert' => ['title' => $name . ' · EN VIVO', 'body' => $body],
                            'sound' => 'default',
                        ],
                        'trevix_link' => $link,
                    ],
                ],
            ];
        }
        PushNotifier::record(Fcm::sendMany($messages), []);
    }
}
