<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\User;
use Trevix\Services\ProfilePhotoService;

final class ProfilePhotoController extends ApiController
{
    /** GET /users/{id}/profile-photos/{kind} */
    public function show(string $id, string $kind): never
    {
        $owner = User::findActiveById((int) $id);
        if ($owner === null) {
            Reply::error(404, 'Esta cuenta no existe.');
        }
        Reply::ok(ProfilePhotoService::present($owner, $this->user(), $kind));
    }

    /** PATCH /me/profile-photos/{kind} */
    public function update(string $kind): never
    {
        $input = [];
        foreach (['caption', 'alt_text', 'privacy'] as $key) {
            if (Input::has($key)) {
                $input[$key] = Input::str($key);
            }
        }
        if (Input::bool('notify_muted') !== null) {
            $input['notify_muted'] = Input::bool('notify_muted');
        }
        Reply::ok(ProfilePhotoService::updateMeta($this->user(), $kind, $input));
    }

    /** PUT /users/{id}/profile-photos/{kind}/like */
    public function like(string $id, string $kind): never
    {
        Reply::ok(ProfilePhotoService::toggleLike($this->user(), (int) $id, $kind, true));
    }

    /** DELETE /users/{id}/profile-photos/{kind}/like */
    public function unlike(string $id, string $kind): never
    {
        Reply::ok(ProfilePhotoService::toggleLike($this->user(), (int) $id, $kind, false));
    }

    /** GET /users/{id}/profile-photos/{kind}/comments?before= */
    public function comments(string $id, string $kind): never
    {
        $owner = User::findActiveById((int) $id);
        if ($owner === null) {
            Reply::error(404, 'Esta cuenta no existe.');
        }
        $access = ProfilePhotoService::access($owner, $this->user(), $kind);
        if (!$access['can_view']) {
            Reply::error(403, 'No puedes ver los comentarios de esta foto.');
        }
        $before = max(0, (int) Request::query('before'));
        $rows = array_reverse(\Trevix\Models\ProfilePhoto::comments((int) $id, $kind, $before, 30));
        Reply::ok(array_map([Present::class, 'profilePhotoComment'], $rows));
    }

    /** POST /users/{id}/profile-photos/{kind}/comments {body} */
    public function comment(string $id, string $kind): never
    {
        Reply::ok(ProfilePhotoService::comment($this->user(), (int) $id, $kind, Input::str('body')));
    }
}