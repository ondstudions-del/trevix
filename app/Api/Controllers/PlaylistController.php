<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\Block;
use Trevix\Models\Playlist;
use Trevix\Services\PlaylistService;

/** Listas de reproducción de reels de los creadores de contenido (se ven en el orden en que se agregaron). */
final class PlaylistController extends ApiController
{
    /** GET /me/playlists?post_id= — listas propias; con post_id, cada una indica si ya tiene esa publicación. */
    public function mine(): never
    {
        $postId = max(0, (int) Request::query('post_id', '0'));
        Reply::ok(array_map([Present::class, 'playlist'], Playlist::forUser($this->uid(), $postId)));
    }

    /** GET /playlists/{id} */
    public function show(string $id): never
    {
        Reply::ok(Present::playlist($this->visible((int) $id)));
    }

    /** GET /playlists/{id}/posts?page= — videos en el orden en que se agregaron (el primero, el más antiguo). */
    public function posts(string $id): never
    {
        $list = $this->visible((int) $id);
        $result = Playlist::posts($list['id'], $this->uid(), $this->pageNumber(), $this->limit('reels_page', 8));
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /** POST /playlists {title, description?} — solo cuentas de creador de contenido. */
    public function create(): never
    {
        $id = PlaylistService::create($this->user(), Input::str('title'), Input::str('description', false));
        $list = Playlist::find($id);
        $this->created($list !== null ? Present::playlist($list) : ['id' => $id]);
    }

    /** PATCH /playlists/{id} {title, description?} */
    public function update(string $id): never
    {
        PlaylistService::update($this->user(), (int) $id, Input::str('title'), Input::str('description', false));
        Reply::ok(Present::playlist($this->visible((int) $id)));
    }

    /** DELETE /playlists/{id} — borra la lista (los videos siguen publicados). */
    public function destroy(string $id): never
    {
        PlaylistService::delete($this->user(), (int) $id);
        Reply::ok(['deleted' => true]);
    }

    /** POST /playlists/{id}/posts {post_id} — agrega un video propio al final de la lista. */
    public function addPost(string $id): never
    {
        $added = PlaylistService::addPost($this->user(), (int) $id, Input::int('post_id'));
        Reply::ok(['added' => $added, 'playlist' => Present::playlist($this->visible((int) $id))]);
    }

    /** DELETE /playlists/{id}/posts/{id2} */
    public function removePost(string $id, string $postId): never
    {
        PlaylistService::removePost($this->user(), (int) $id, (int) $postId);
        Reply::ok(['removed' => true, 'playlist' => Present::playlist($this->visible((int) $id))]);
    }

    /** Lista que el lector puede ver: no existe para quien bloqueó al autor o fue bloqueado por él. */
    private function visible(int $id): array
    {
        $list = $id > 0 ? Playlist::find($id) : null;
        $uid = $this->uid();
        if ($list === null || ($list['user_id'] !== $uid
            && (Block::exists($list['user_id'], $uid) || Block::exists($uid, $list['user_id'])))) {
            $this->notFound('Esta lista de reproducción no existe.');
        }
        return $list;
    }
}
