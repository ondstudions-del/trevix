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

    /** POST /livekit/live {title?} */
    public function startLive(): never
    {
        $title = Input::has('title') ? Input::str('title') : null;
        Reply::ok(LiveKitService::startLive($this->user(), $title));
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
}