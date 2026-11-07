<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Comment;
use Trevix\Services\CommentService;

/** api/comments.php: action = create (por defecto) | delete. */
final class CommentController extends Controller
{
    public function api(): void
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $user = $this->requireUser();

        match (Request::text('action') ?: 'create') {
            'create' => $this->create($user),
            'delete' => $this->destroy($user),
            default  => $this->fail('Acción no válida.', 400, url('feed.php')),
        };
    }

    private function create(array $user): never
    {
        $postId = (int) Request::text('post_id');
        $back = $postId > 0 ? url('post.php', ['id' => $postId]) . '#comentarios' : url('feed.php');
        $result = $this->attempt(
            static fn () => CommentService::create($user, $postId, Request::text('body', false), (int) Request::text('parent_id')),
            $back
        );
        $id = $result['id'];

        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'id' => $id], 201);
        }
        Session::flash('success', $result['parent_id'] !== null ? 'Respuesta publicada.' : 'Comentario publicado.');
        $page = $result['parent_id'] !== null
            ? (int) Request::text('page')
            : (int) ceil(Comment::topLevelCount($postId) / max(1, (int) Config::get('app.limits.comments_page', 30)));
        Response::redirect(url('post.php', ['id' => $postId, 'page' => $page > 1 ? $page : null]) . '#comentario-' . $id);
    }

    private function destroy(array $user): never
    {
        $postId = $this->attempt(
            static fn () => CommentService::delete((int) $user['id'], (int) Request::text('comment_id')),
            url('feed.php')
        );

        if (Request::wantsJson()) {
            Response::json(['ok' => true]);
        }
        Session::flash('success', 'Comentario eliminado.');
        Response::redirect(url('post.php', ['id' => $postId]) . '#comentarios');
    }
}
