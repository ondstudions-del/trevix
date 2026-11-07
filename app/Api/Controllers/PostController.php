<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Controllers\FeedController;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Models\Comment;
use Trevix\Models\Post;
use Trevix\Services\CommentService;
use Trevix\Services\MediaUpload;
use Trevix\Services\PostService;

/** Feeds, publicaciones, me gusta, guardados y comentarios. */
final class PostController extends ApiController
{
    /** GET /feed?tab=foryou|following|friends|trending&before=|page= */
    public function feed(): never
    {
        $uid = $this->uid();
        $tab = Request::queryIn('tab', array_keys(FeedController::FEEDS), 'foryou');
        $result = Post::feed($uid, FeedController::query($tab, $uid) + $this->paging());
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /**
     * POST /posts — JSON o multipart con archivos en «media[]».
     * {body?, format?: post|thread, visibility?: public|followers|private, community_id?, shared_post_id?,
     *  song_id?, song_start?}
     */
    public function create(): never
    {
        $this->rejectOversized();
        $user = $this->user();
        $result = PostService::create($user, [
            'format'         => Input::str('format'),
            'visibility'     => Input::str('visibility'),
            'community_id'   => Input::int('community_id'),
            'shared_post_id' => Input::int('shared_post_id'),
            'body'           => Input::str('body', false),
            'song_id'        => Input::int('song_id'),
            'song_start'     => Input::int('song_start'),
        ], MediaUpload::collect('media'));
        $post = Post::findVisible($result['id'], (int) $user['id']);
        $this->created($post !== null ? Present::post($post) : ['id' => $result['id']]);
    }

    /** GET /posts/{id} */
    public function show(string $id): never
    {
        Reply::ok(Present::post($this->visible((int) $id)));
    }

    /** PATCH /posts/{id} {body?, visibility?, song_id?, song_start?} — solo la propia publicación; song_id 0 quita la canción. */
    public function update(string $id): never
    {
        $uid = $this->uid();
        $post = PostService::findOwnEditable((int) $id, $uid);
        $song = null;
        if (Input::has('song_id')) {
            $song = ['id' => Input::int('song_id'), 'start' => Input::has('song_start') ? Input::int('song_start') : (int) ($post['song']['start'] ?? 0)];
        } elseif (Input::has('song_start') && $post['song'] !== null) {
            $song = ['id' => (int) $post['song']['id'], 'start' => Input::int('song_start')];
        }
        PostService::update(
            $post,
            Input::has('body') ? Input::str('body', false) : $post['body'],
            Input::has('visibility') ? Input::str('visibility') : $post['visibility'],
            $song
        );
        Reply::ok(Present::post(Post::findVisible((int) $id, $uid) ?? $post));
    }

    /** DELETE /posts/{id} */
    public function destroy(string $id): never
    {
        PostService::delete($this->uid(), (int) $id);
        Reply::ok(['message' => 'Eliminaste la publicación.']);
    }

    /** POST|DELETE /posts/{id}/like · /posts/{id}/save */
    public function interact(string $id, string $kind): never
    {
        $result = PostService::interact($kind, $this->uid(), (int) $id, Request::method() !== 'DELETE');
        Reply::ok([$kind === 'like' ? 'liked' : 'saved' => $result['active'], 'count' => $result['count']]);
    }

    /** GET /posts/{id}/comments?page= */
    public function comments(string $id): never
    {
        $post = $this->visible((int) $id);
        $page = $this->pageNumber();
        $result = Comment::forPost((int) $id, $this->uid(), $page, $this->limit('comments_page', 30));
        $ownerId = (int) $post['user']['id'];
        Reply::ok(
            array_map(static fn (array $c) => Present::comment($c, $ownerId), $result['comments']),
            $this->nextPage($result['hasMore'])
        );
    }

    /** POST /posts/{id}/comments {body, parent_id?} */
    public function comment(string $id): never
    {
        $user = $this->user();
        $result = CommentService::create($user, (int) $id, Input::str('body', false), Input::int('parent_id'));
        $this->created(Present::comment([
            'id'         => $result['id'],
            'post_id'    => $result['post_id'],
            'user_id'    => (int) $user['id'],
            'parent_id'  => $result['parent_id'],
            'body'       => $result['body'],
            'created_at' => date('Y-m-d H:i:s'),
            'user'       => $user,
        ], $result['post_owner_id']));
    }

    /** DELETE /comments/{id} — el autor del comentario o el de la publicación. */
    public function deleteComment(string $id): never
    {
        $postId = CommentService::delete($this->uid(), (int) $id);
        Reply::ok(['message' => 'Comentario eliminado.', 'post_id' => $postId]);
    }

    private function visible(int $id): array
    {
        $post = $id > 0 ? Post::findVisible($id, $this->uid()) : null;
        if ($post === null) {
            $this->notFound('Esta publicación no existe o ya no está disponible.');
        }
        return $post;
    }

    /** Si el cuerpo supera post_max_size, PHP descarta los datos y los archivos. */
    private function rejectOversized(): void
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === [] && !str_contains(strtolower((string) ($_SERVER['CONTENT_TYPE'] ?? '')), 'json')) {
            throw new ActionError('Los archivos superan el tamaño total que acepta el servidor.', 413);
        }
    }
}
