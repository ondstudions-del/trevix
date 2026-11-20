<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use RuntimeException;
use Trevix\Api\Present;
use Trevix\Core\ActionError;
use Trevix\Models\Conversation;
use Trevix\Models\LiveSession;
use Trevix\Models\User;

final class LiveKitService
{
    public static function requireConfigured(): void
    {
        if (!LiveKitSettings::configured()) {
            throw new RuntimeException('LiveKit no está configurado en el servidor.');
        }
    }

    public static function kindEnabled(string $kind): bool
    {
        return match ($kind) {
            'audio' => \Trevix\Models\AppSetting::flag('livekit_calls_audio'),
            'video' => \Trevix\Models\AppSetting::flag('livekit_calls_video'),
            'live'  => \Trevix\Models\AppSetting::flag('livekit_live_broadcast'),
            default => false,
        };
    }

    /** @return array<string, mixed> */
    public static function startCall(array $caller, int $peerId, string $kind): array
    {
        self::requireConfigured();
        if (!in_array($kind, ['audio', 'video'], true)) {
            throw new ActionError('El tipo de llamada debe ser audio o video.', 400);
        }
        if (!self::kindEnabled($kind)) {
            throw new ActionError('Este tipo de llamada está desactivado.', 403);
        }
        $uid = (int) $caller['id'];
        if ($peerId === $uid) {
            throw new ActionError('No puedes llamarte a ti mismo.', 400);
        }
        $peer = User::findActiveById($peerId);
        if ($peer === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        $reason = Conversation::cannotMessage($uid, $peer, Conversation::findDirectId($uid, $peerId));
        if ($reason !== null) {
            throw new ActionError($reason, 403);
        }
        if (LiveSession::activeRingingForPeer($peerId) !== null) {
            throw new ActionError('Esta persona ya tiene una llamada entrante.', 409);
        }

        $room = self::roomName('call', $uid, $peerId);
        $id = LiveSession::insert($room, $kind, $uid, $peerId, 'ringing', null);
        $session = LiveSession::find($id);
        if ($session === null) {
            throw new RuntimeException('No se pudo crear la llamada.');
        }
        LiveKitNotify::incomingCall($peerId, $id, $kind);
        $out = self::present($session, $caller);
        $out['join'] = self::token($caller, $id);
        return $out;
    }

    /** @return array<string, mixed>|null */
    public static function incoming(array $user): ?array
    {
        self::requireConfigured();
        self::expireStaleRinging();
        $session = LiveSession::ringingForPeer((int) $user['id']);
        if ($session === null) {
            return null;
        }
        return self::present($session, $user);
    }

    /** @return array<string, mixed> */
    public static function acceptCall(array $user, int $sessionId): array
    {
        self::requireConfigured();
        $session = self::sessionForParticipant($user, $sessionId);
        if ($session['status'] !== 'ringing' || !in_array($session['kind'], ['audio', 'video'], true)) {
            throw new ActionError('Esta llamada ya no está disponible.', 409);
        }
        if ((int) $session['peer_user_id'] !== (int) $user['id']) {
            throw new ActionError('Solo quien recibe la llamada puede aceptarla.', 403);
        }
        LiveSession::updateStatus($sessionId, 'active', gmdate('Y-m-d H:i:s'), null);
        $fresh = LiveSession::find($sessionId);
        $out = self::present($fresh ?? $session, $user);
        $out['join'] = self::token($user, $sessionId);
        return $out;
    }

    /** @return array<string, mixed> */
    public static function declineCall(array $user, int $sessionId): array
    {
        $session = self::sessionForParticipant($user, $sessionId);
        if ($session['status'] !== 'ringing') {
            throw new ActionError('Esta llamada ya no está sonando.', 409);
        }
        LiveSession::updateStatus($sessionId, 'declined', null, gmdate('Y-m-d H:i:s'));
        $fresh = LiveSession::find($sessionId);
        return self::present($fresh ?? $session, $user);
    }

    /** @return array<string, mixed> */
    public static function startLive(array $host, ?string $title): array
    {
        self::requireConfigured();
        if (!self::kindEnabled('live')) {
            throw new ActionError('El live está desactivado.', 403);
        }
        $uid = (int) $host['id'];
        $room = self::roomName('live', $uid, null);
        $id = LiveSession::insert($room, 'live', $uid, null, 'active', self::cleanTitle($title));
        LiveSession::updateStatus($id, 'active', gmdate('Y-m-d H:i:s'), null);
        $session = LiveSession::find($id);
        if ($session === null) {
            throw new RuntimeException('No se pudo iniciar el live.');
        }
        return self::present($session, $host);
    }

    /** @return array{token: string, url: string, session: array} */
    public static function token(array $user, int $sessionId): array
    {
        self::requireConfigured();
        $session = self::sessionForParticipant($user, $sessionId, true);
        if (in_array($session['status'], ['ended', 'declined', 'missed'], true)) {
            throw new ActionError('Esta sesión ya terminó.', 410);
        }
        $creds = LiveKitSettings::resolve();
        $identity = 'u' . (int) $user['id'];
        $name = (string) ($user['display_name'] ?: $user['username']);
        $isHost = (int) $session['host_user_id'] === (int) $user['id'];
        $isLive = $session['kind'] === 'live';

        $canPublish = $isLive ? $isHost : true;
        $grant = [
            'roomJoin'     => true,
            'room'         => (string) $session['room_name'],
            'canPublish'   => $canPublish,
            'canSubscribe' => true,
            'canPublishData' => true,
        ];
        if ($isLive && !$isHost) {
            $grant['canPublish'] = false;
        }

        $jwt = LiveKitToken::create(
            $creds['api_key'],
            $creds['api_secret'],
            $identity,
            $name,
            $grant,
            6 * 3600,
        );

        return [
            'url'     => $creds['url'],
            'token'   => $jwt,
            'session' => self::present($session, $user),
        ];
    }

    /** @return array<string, mixed> */
    public static function end(array $user, int $sessionId): array
    {
        $session = self::sessionForParticipant($user, $sessionId);
        if (in_array($session['status'], ['ended', 'declined', 'missed'], true)) {
            return self::present($session, $user);
        }
        LiveSession::updateStatus($sessionId, 'ended', null, gmdate('Y-m-d H:i:s'));
        $fresh = LiveSession::find($sessionId);
        return self::present($fresh ?? $session, $user);
    }

    /** @return array<string, mixed> */
    public static function show(array $user, int $sessionId): array
    {
        $session = LiveSession::find($sessionId);
        if ($session === null) {
            throw new ActionError('Esta sesión no existe.', 404);
        }
        if ($session['kind'] === 'live' && $session['status'] === 'active') {
            return self::present($session, $user);
        }
        return self::present(self::sessionForParticipant($user, $sessionId), $user);
    }

    /** @param array<string, mixed> $session */
    private static function present(array $session, array $viewer): array
    {
        $host = User::findActiveById((int) $session['host_user_id']);
        $peer = $session['peer_user_id'] !== null ? User::findActiveById((int) $session['peer_user_id']) : null;
        return [
            'id'          => (int) $session['id'],
            'room'        => (string) $session['room_name'],
            'kind'        => (string) $session['kind'],
            'status'      => (string) $session['status'],
            'title'       => $session['title'] !== null ? (string) $session['title'] : null,
            'host'        => $host !== null ? Present::user($host) : null,
            'peer'        => $peer !== null ? Present::user($peer) : null,
            'is_host'     => (int) $session['host_user_id'] === (int) $viewer['id'],
            'created_at'  => (string) $session['created_at'],
            'started_at'  => $session['started_at'] !== null ? (string) $session['started_at'] : null,
            'ended_at'    => $session['ended_at'] !== null ? (string) $session['ended_at'] : null,
        ];
    }

    /** @return array<string, mixed> */
    private static function sessionForParticipant(array $user, int $sessionId, bool $allowLiveViewer = false): array
    {
        $session = LiveSession::find($sessionId);
        if ($session === null) {
            throw new ActionError('Esta sesión no existe.', 404);
        }
        $uid = (int) $user['id'];
        $host = (int) $session['host_user_id'];
        $peer = $session['peer_user_id'] !== null ? (int) $session['peer_user_id'] : null;
        if ($uid !== $host && $uid !== $peer) {
            if ($allowLiveViewer && $session['kind'] === 'live' && $session['status'] === 'active') {
                return $session;
            }
            throw new ActionError('No tienes acceso a esta sesión.', 403);
        }
        return $session;
    }

    private static function expireStaleRinging(): void
    {
        LiveSession::expireStaleRinging();
    }

    private static function roomName(string $prefix, int $a, ?int $b): string
    {
        $suffix = bin2hex(random_bytes(6));
        if ($prefix === 'live') {
            return 'trevix-live-' . $a . '-' . $suffix;
        }
        $lo = min($a, (int) $b);
        $hi = max($a, (int) $b);
        return 'trevix-call-' . $lo . '-' . $hi . '-' . $suffix;
    }

    private static function cleanTitle(?string $title): ?string
    {
        $title = $title !== null ? trim(preg_replace('/\s+/u', ' ', $title) ?? '') : '';
        if ($title === '') {
            return null;
        }
        if (mb_strlen($title) > 120) {
            throw new DomainException('El título del live puede tener como máximo 120 caracteres.');
        }
        return $title;
    }
}