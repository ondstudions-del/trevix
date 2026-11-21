<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Reply;
use Trevix\Services\LiveKitService;
use Trevix\Services\LiveKitSettings;

final class LiveKitController extends ApiController
{
    /** GET /livekit */
    public function config(): never
    {
        Reply::ok([
            'configured' => LiveKitSettings::configured(),
            'client'     => LiveKitSettings::clientConfig(),
        ]);
    }

    /** GET /livekit/incoming — llamada que está sonando para esta cuenta */
    public function incoming(): never
    {
        $call = LiveKitService::incoming($this->user());
        Reply::ok(['call' => $call]);
    }

    /** POST /livekit/calls {user_id, kind: audio|video} */
    public function startCall(): never
    {
        Reply::ok(LiveKitService::startCall($this->user(), Input::int('user_id'), Input::str('kind')));
    }

    /** POST /livekit/calls/{id}/accept */
    public function acceptCall(string $id): never
    {
        Reply::ok(LiveKitService::acceptCall($this->user(), (int) $id));
    }

    /** POST /livekit/calls/{id}/decline */
    public function declineCall(string $id): never
    {
        Reply::ok(LiveKitService::declineCall($this->user(), (int) $id));
    }

    /** POST /livekit/calls/{id}/end */
    public function endCall(string $id): never
    {
        Reply::ok(LiveKitService::end($this->user(), (int) $id));
    }

    /** POST /livekit/live {title?, description?, hashtags?, category?, cover_url?, live_mode?} */
    public function startLive(): never
    {
        $meta = [];
        foreach (['title', 'description', 'hashtags', 'category', 'cover_url', 'live_mode'] as $field) {
            if (Input::has($field)) {
                $meta[$field] = Input::str($field);
            }
        }
        Reply::ok(LiveKitService::startLive($this->user(), $meta));
    }

    /** GET /livekit/lives — lives activos (seguidos primero). */
    public function lives(): never
    {
        Reply::ok(LiveKitService::listLives($this->user()));
    }

    /** POST /livekit/sessions/{id}/end */
    public function endSession(string $id): never
    {
        Reply::ok(LiveKitService::end($this->user(), (int) $id));
    }

    /** POST /livekit/sessions/{id}/token */
    public function token(string $id): never
    {
        Reply::ok(LiveKitService::token($this->user(), (int) $id));
    }

    /** GET /livekit/sessions/{id} */
    public function show(string $id): never
    {
        Reply::ok(LiveKitService::show($this->user(), (int) $id));
    }

    /** POST /livekit/sessions/{id}/like */
    public function like(string $id): never
    {
        Reply::ok(LiveKitService::like($this->user(), (int) $id));
    }

    /** GET /livekit/sessions/{id}/messages?after= */
    public function messages(string $id): never
    {
        $after = max(0, (int) (\Trevix\Core\Request::query('after') ?: 0));
        Reply::ok(LiveKitService::messages($this->user(), (int) $id, $after));
    }

    /** POST /livekit/sessions/{id}/messages {body, reply_to_id?} */
    public function postMessage(string $id): never
    {
        $replyTo = Input::has('reply_to_id') ? Input::int('reply_to_id') : null;
        Reply::ok(LiveKitService::postMessage($this->user(), (int) $id, Input::str('body'), $replyTo ?: null), [], 201);
    }

    /** POST /livekit/sessions/{id}/speakers/invite {user_id} */
    public function inviteSpeaker(string $id): never
    {
        Reply::ok(LiveKitService::inviteSpeaker($this->user(), (int) $id, Input::int('user_id')));
    }

    /** POST /livekit/sessions/{id}/speakers/accept */
    public function acceptSpeaker(string $id): never
    {
        Reply::ok(LiveKitService::acceptSpeaker($this->user(), (int) $id));
    }

    /** POST /livekit/sessions/{id}/speakers/remove {user_id} */
    public function removeSpeaker(string $id): never
    {
        Reply::ok(LiveKitService::removeSpeaker($this->user(), (int) $id, Input::int('user_id')));
    }
}