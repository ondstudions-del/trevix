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
        $before = max(0, (int) Request::query('before'));
        $rows = ProfilePhotoService::listComments($this->user(), (int) $id, $kind, $before);
        Reply::ok(array_map(
            static fn (array $c) => Present::profilePhotoComment($c, (int) $id),
            $rows
        ));
    }

    /** POST /users/{id}/profile-photos/{kind}/comments — texto, GIF o imagen (multipart «image»). */
    public function comment(string $id, string $kind): never
    {
        $media = null;
        if (!empty($_FILES['image']['error']) && (int) $_FILES['image']['error'] !== UPLOAD_ERR_NO_FILE) {
            try {
                $stored = \Trevix\Services\MediaUpload::storeCommentImage('image');
                $media = [
                    'path'   => (string) $stored['path'],
                    'width'  => (int) $stored['width'],
                    'height' => (int) $stored['height'],
                ];
            } catch (\RuntimeException $e) {
                throw \Trevix\Core\ActionError::field('image', $e->getMessage());
            }
        }
        $row = ProfilePhotoService::comment(
            $this->user(),
            (int) $id,
            $kind,
            Input::str('body', false),
            Input::int('parent_id'),
            Input::str('gif_id'),
            Input::str('gif_kind'),
            $media
        );
        $this->created(Present::profilePhotoComment($row, (int) $id));
    }

    /** POST /profile-photo-comments/{id}/reaction {value: like|dislike|none} */
    public function reactComment(string $id): never
    {
        $value = Input::in('value', ['like', 'dislike', 'none'], 'none', 'Elige like, dislike o none.');
        $result = ProfilePhotoService::reactComment($this->user(), (int) $id, $value === 'none' ? null : $value);
        Reply::ok([
            'reaction'       => $result['reaction'],
            'likes_count'    => $result['likes'],
            'dislikes_count' => $result['dislikes'],
        ]);
    }

    /** DELETE /profile-photo-comments/{id} */
    public function deleteComment(string $id): never
    {
        ProfilePhotoService::deleteComment($this->user(), (int) $id);
        Reply::ok(['message' => 'Comentario eliminado.']);
    }
}
