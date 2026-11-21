<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use RuntimeException;
use Trevix\Api\Present;
use Trevix\Core\ActionError;
use Trevix\Models\Conversation;
use Trevix\Models\Gift;
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

    /** Resumen público de un live activo (perfil / rail). */
    public static function presentActiveLive(?array $session): ?array
    {
        if ($session === null || ($session['kind'] ?? '') !== 'live' || ($session['status'] ?? '') !== 'active') {
            return null;
        }
        return [
            'id'         => (int) $session['id'],
            'title'      => $session['title'] !== null ? (string) $session['title'] : null,
            'cover_url'  => $session['cover_url'] !== null ? (string) $session['cover_url'] : null,
            'live_mode'  => (string) ($session['live_mode'] ?? 'camera'),
            'likes'      => (int) ($session['likes_count'] ?? 0),
            'started_at' => $session['started_at'] !== null ? (string) $session['started_at'] : (string) $session['created_at'],
        ];
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
        LiveKitNotify::incomingCall($peerId, $id, $kind, $caller);
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
        if (!in_array($session['kind'], ['audio', 'video'], true)) {
            throw new ActionError('Esta llamada ya no está disponible.', 409);
        }
        if ($session['status'] === 'active') {
            if ((int) $session['peer_user_id'] !== (int) $user['id']) {
                throw new ActionError('Solo quien recibe la llamada puede aceptarla.', 403);
            }
            $out = self::present($session, $user);
            $out['join'] = self::token($user, $sessionId);
            return $out;
        }
        if ($session['status'] !== 'ringing') {
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

    /**
     * @param array{title?:?string, description?:?string, hashtags?:?string, category?:?string, cover_url?:?string, live_mode?:string} $meta
     * @return array<string, mixed>
     */
    public static function startLive(array $host, array $meta = []): array
    {
        self::requireConfigured();
        if (!self::kindEnabled('live')) {
            throw new ActionError('El live está desactivado.', 403);
        }
        if (!User::isStreamer($host)) {
            throw new ActionError('Solo las cuentas Stream pueden emitir en vivo.', 403);
        }
        $liveMode = (string) ($meta['live_mode'] ?? 'camera');
        if (!in_array($liveMode, LiveSession::LIVE_MODES, true)) {
            throw ActionError::field('live_mode', 'El modo debe ser camera o voice_chat.');
        }
        $uid = (int) $host['id'];
        LiveSession::endActiveLivesForHost($uid);
        $room = self::roomName('live', $uid, null);
        $clean = self::cleanTitle($meta['title'] ?? null);
        $insertMeta = [
            'description' => self::cleanOptionalText($meta['description'] ?? null, 2000),
            'hashtags'    => self::cleanOptionalText($meta['hashtags'] ?? null, 255),
            'category'    => self::cleanOptionalText($meta['category'] ?? null, 64),
            'cover_url'   => self::cleanOptionalText($meta['cover_url'] ?? null, 512),
            'live_mode'   => $liveMode,
        ];
        $id = LiveSession::insert($room, 'live', $uid, null, 'active', $clean, $insertMeta);
        LiveSession::updateStatus($id, 'active', gmdate('Y-m-d H:i:s'), null);
        $session = LiveSession::find($id);
        if ($session === null) {
            throw new RuntimeException('No se pudo iniciar el live.');
        }
        try {
            LiveKitNotify::liveStarted($host, $id, $clean);
        } catch (\Throwable) {
        }
        $out = self::present($session, $host);
        $out['join'] = self::token($host, $id);
        return $out;
    }

    /** @return list<array<string, mixed>> */
    public static function listLives(array $viewer): array
    {
        self::requireConfigured();
        if (!self::kindEnabled('live')) {
            return [];
        }
        $rows = LiveSession::activeLives((int) $viewer['id']);
        $out = [];
        foreach ($rows as $row) {
            $item = self::present($row, $viewer);
            $item['is_following'] = !empty($row['is_following']);
            $out[] = $item;
        }
        return $out;
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
        if ($isLive && !$isHost) {
            $mode = (string) ($session['live_mode'] ?? 'camera');
            if ($mode === 'voice_chat' && LiveSession::speakerStatus($sessionId, (int) $user['id']) === 'active') {
                $canPublish = true;
            } else {
                $canPublish = false;
            }
        }
        $grant = [
            'roomJoin'       => true,
            'room'           => (string) $session['room_name'],
            'canPublish'     => $canPublish,
            'canSubscribe'   => true,
            'canPublishData' => true,
        ];

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
        $session = self::sessionForParticipant($user, $sessionId, true);
        $uid = (int) $user['id'];
        $isHost = (int) $session['host_user_id'] === $uid;
        $isPeer = $session['peer_user_id'] !== null && (int) $session['peer_user_id'] === $uid;
        if ($session['kind'] === 'live' && !$isHost) {
            // Espectador sale: no cierra el live para los demás.
            return self::present($session, $user);
        }
        if (!$isHost && !$isPeer) {
            throw new ActionError('No puedes terminar esta sesión.', 403);
        }
        if (in_array($session['status'], ['ended', 'declined', 'missed'], true)) {
            return self::present($session, $user);
        }
        if (in_array($session['kind'], ['audio', 'video'], true) && $session['status'] === 'ringing') {
            $isCaller = (int) $session['host_user_id'] === $uid;
            LiveSession::updateStatus($sessionId, $isCaller ? 'missed' : 'declined', null, gmdate('Y-m-d H:i:s'));
            $fresh = LiveSession::find($sessionId);
            return self::present($fresh ?? $session, $user);
        }
        LiveSession::updateStatus($sessionId, 'ended', null, gmdate('Y-m-d H:i:s'));
        if ($session['kind'] === 'live' && $isHost) {
            $gifts = Gift::totalCentsForLiveSession($sessionId);
            LiveSession::setGiftsTotal($sessionId, $gifts);
        }
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
        if (in_array($session['kind'], ['audio', 'video'], true) && $session['status'] === 'ringing') {
            self::expireStaleRinging();
            $session = LiveSession::find($sessionId) ?? $session;
        }
        if ($session['kind'] === 'live' && $session['status'] === 'active') {
            return self::present($session, $user);
        }
        return self::present(self::sessionForParticipant($user, $sessionId), $user);
    }

    /** @return array{likes:int} */
    public static function like(array $user, int $sessionId): array
    {
        self::requireConfigured();
        $session = LiveSession::find($sessionId);
        if ($session === null || $session['kind'] !== 'live' || $session['status'] !== 'active') {
            throw new ActionError('Este live ya no está disponible.', 404);
        }
        return ['likes' => LiveSession::bumpLikes($sessionId)];
    }

    /**
     * @return array{id:int, body:string, user:array, created_at:string}
     */
    public static function postMessage(array $user, int $sessionId, string $body, ?int $replyToId = null): array
    {
        self::requireConfigured();
        $session = LiveSession::find($sessionId);
        if ($session === null || $session['kind'] !== 'live' || $session['status'] !== 'active') {
            throw new ActionError('Este live ya no está disponible.', 404);
        }
        $body = trim(preg_replace('/\s+/u', ' ', $body) ?? '');
        if ($body === '') {
            throw ActionError::field('body', 'Escribe un comentario.');
        }
        if (mb_strlen($body) > 280) {
            throw ActionError::field('body', 'El comentario puede tener como máximo 280 caracteres.');
        }
        $id = LiveSession::addMessage($sessionId, (int) $user['id'], $body, $replyToId);
        return [
            'id'          => $id,
            'body'        => $body,
            'reply_to_id' => $replyToId,
            'user'        => Present::user($user),
            'created_at'  => gmdate('c'),
        ];
    }

    /** @return array<string, mixed> */
    public static function inviteSpeaker(array $host, int $sessionId, int $userId): array
    {
        self::requireConfigured();
        $session = self::requireActiveVoiceLive($host, $sessionId);
        if ($userId === (int) $host['id']) {
            throw new ActionError('El host ya está en el live.', 400);
        }
        $target = User::findActiveById($userId);
        if ($target === null) {
            throw new ActionError('Esta cuenta no existe.', 404);
        }
        LiveSession::inviteSpeaker($sessionId, $userId);
        return ['speakers' => self::presentSpeakers($sessionId)];
    }

    /** @return array<string, mixed> */
    public static function acceptSpeaker(array $user, int $sessionId): array
    {
        self::requireConfigured();
        $session = LiveSession::find($sessionId);
        if ($session === null || $session['kind'] !== 'live' || $session['status'] !== 'active') {
            throw new ActionError('Este live ya no está disponible.', 404);
        }
        if (($session['live_mode'] ?? 'camera') !== 'voice_chat') {
            throw new ActionError('Este live no admite invitados a micrófono.', 400);
        }
        $uid = (int) $user['id'];
        if (LiveSession::speakerStatus($sessionId, $uid) !== 'invited') {
            throw new ActionError('No tienes una invitación pendiente.', 403);
        }
        if (LiveSession::countActiveSpeakers($sessionId) >= LiveSession::MAX_VOICE_SPEAKERS) {
            throw new ActionError('Ya hay el máximo de participantes en micrófono.', 409);
        }
        LiveSession::setSpeakerActive($sessionId, $uid);
        return ['speakers' => self::presentSpeakers($sessionId)];
    }

    /** @return array<string, mixed> */
    public static function removeSpeaker(array $host, int $sessionId, int $userId): array
    {
        self::requireConfigured();
        self::requireActiveVoiceLive($host, $sessionId);
        LiveSession::removeSpeaker($sessionId, $userId);
        return ['speakers' => self::presentSpeakers($sessionId)];
    }

    /** @return list<array{id:int, body:string, user:array, created_at:string}> */
    public static function messages(array $user, int $sessionId, int $afterId = 0): array
    {
        self::requireConfigured();
        $session = LiveSession::find($sessionId);
        if ($session === null || $session['kind'] !== 'live') {
            throw new ActionError('Este live no existe.', 404);
        }
        // Solo participantes o live activo.
        if ($session['status'] !== 'active') {
            self::sessionForParticipant($user, $sessionId, true);
        }
        $rows = $afterId > 0
            ? LiveSession::messages($sessionId, $afterId)
            : LiveSession::recentMessages($sessionId);
        return array_map(static function (array $r): array {
            return [
                'id'          => (int) $r['id'],
                'body'        => (string) $r['body'],
                'reply_to_id' => $r['reply_to_id'] !== null ? (int) $r['reply_to_id'] : null,
                'created_at'  => (string) $r['created_at'],
                'user'        => Present::user([
                    'id'           => (int) $r['user_id'],
                    'username'     => $r['username'],
                    'display_name' => $r['display_name'],
                    'avatar_path'  => $r['avatar_path'],
                    'is_verified'  => $r['is_verified'],
                ]),
            ];
        }, $rows);
    }

    /** @param array<string, mixed> $session */
    private static function present(array $session, array $viewer): array
    {
        $host = isset($session['username'])
            ? [
                'id'           => (int) $session['host_user_id'],
                'username'     => $session['username'],
                'display_name' => $session['display_name'],
                'avatar_path'  => $session['avatar_path'],
                'is_verified'  => $session['is_verified'],
            ]
            : User::findActiveById((int) $session['host_user_id']);
        $peer = $session['peer_user_id'] !== null ? User::findActiveById((int) $session['peer_user_id']) : null;
        $isLive = ($session['kind'] ?? '') === 'live';
        $out = [
            'id'          => (int) $session['id'],
            'room'        => (string) $session['room_name'],
            'kind'        => (string) $session['kind'],
            'status'      => (string) $session['status'],
            'title'       => $session['title'] !== null ? (string) $session['title'] : null,
            'likes'       => (int) ($session['likes_count'] ?? 0),
            'host'        => $host !== null ? Present::user($host) : null,
            'peer'        => $peer !== null ? Present::user($peer) : null,
            'is_host'     => (int) $session['host_user_id'] === (int) $viewer['id'],
            'created_at'  => (string) $session['created_at'],
            'started_at'  => $session['started_at'] !== null ? (string) $session['started_at'] : null,
            'ended_at'    => $session['ended_at'] !== null ? (string) $session['ended_at'] : null,
        ];
        if ($isLive) {
            $out['description']       = $session['description'] !== null ? (string) $session['description'] : null;
            $out['hashtags']          = $session['hashtags'] !== null ? (string) $session['hashtags'] : null;
            $out['category']          = $session['category'] !== null ? (string) $session['category'] : null;
            $out['cover_url']         = $session['cover_url'] !== null ? (string) $session['cover_url'] : null;
            $out['live_mode']         = (string) ($session['live_mode'] ?? 'camera');
            $out['viewers_peak']      = (int) ($session['viewers_peak'] ?? 0);
            $out['gifts_total_cents'] = (int) ($session['gifts_total_cents'] ?? 0);
            $out['unique_viewers']    = (int) ($session['unique_viewers'] ?? 0);
            $out['join_count']        = (int) ($session['join_count'] ?? 0);
            if (($session['status'] ?? '') === 'ended') {
                $out['duration_seconds'] = self::durationSeconds($session);
            }
        }
        return $out;
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

    private static function cleanOptionalText(?string $text, int $max): ?string
    {
        if ($text === null) {
            return null;
        }
        $text = trim(preg_replace('/\s+/u', ' ', $text) ?? '');
        if ($text === '') {
            return null;
        }
        if (mb_strlen($text) > $max) {
            throw new DomainException('El texto puede tener como máximo ' . $max . ' caracteres.');
        }
        return $text;
    }

    /** @return array<string, mixed> */
    private static function requireActiveVoiceLive(array $host, int $sessionId): array
    {
        $session = LiveSession::find($sessionId);
        if ($session === null || $session['kind'] !== 'live' || $session['status'] !== 'active') {
            throw new ActionError('Este live ya no está disponible.', 404);
        }
        if ((int) $session['host_user_id'] !== (int) $host['id']) {
            throw new ActionError('Solo el host puede gestionar invitados.', 403);
        }
        if (($session['live_mode'] ?? 'camera') !== 'voice_chat') {
            throw new ActionError('Este live no admite invitados a micrófono.', 400);
        }
        return $session;
    }

    /** @return list<array<string, mixed>> */
    private static function presentSpeakers(int $sessionId): array
    {
        return array_map(static function (array $r): array {
            return [
                'status' => (string) $r['status'],
                'user'   => Present::user([
                    'id'           => (int) $r['user_id'],
                    'username'     => $r['username'],
                    'display_name' => $r['display_name'],
                    'avatar_path'  => $r['avatar_path'],
                    'is_verified'  => $r['is_verified'],
                ]),
            ];
        }, LiveSession::listSpeakers($sessionId));
    }

    /** @param array<string, mixed> $session */
    private static function durationSeconds(array $session): ?int
    {
        $start = $session['started_at'] ?? $session['created_at'] ?? null;
        $end = $session['ended_at'] ?? null;
        if ($start === null || $end === null) {
            return null;
        }
        $t0 = strtotime((string) $start);
        $t1 = strtotime((string) $end);
        if ($t0 === false || $t1 === false || $t1 < $t0) {
            return null;
        }
        return $t1 - $t0;
    }
}
