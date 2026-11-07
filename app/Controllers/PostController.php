<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Core\View;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Comment;
use Trevix\Models\Community;
use Trevix\Models\Post;
use Trevix\Services\MediaUpload;
use Trevix\Services\PostService;

/** Crear, ver, editar y eliminar publicaciones; me gusta y guardados. */
final class PostController extends Controller
{
    /** api/posts.php: action = create (por defecto) | delete. */
    public function api(): void
    {
        $this->onlyPost();
        $this->rejectOversizedRequest();
        VerifyCsrf::handle();
        $user = $this->requireUser();

        match (Request::text('action') ?: 'create') {
            'create' => $this->create($user),
            'delete' => $this->destroy($user),
            default  => $this->fail('Acción no válida.', 400, url('feed.php')),
        };
    }

    /** api/likes.php y api/saves.php. */
    public function toggle(string $kind): void
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $postId = (int) Request::text('post_id');
        $result = $this->attempt(static fn () => PostService::interact($kind, (int) $user['id'], $postId), url('feed.php'));
        if (Request::wantsJson()) {
            Response::json(['ok' => true] + $result);
        }
        $this->redirectBack(url('post.php', ['id' => $postId]));
    }

    /** post.php?id= : publicación con sus comentarios paginados. */
    public function show(): void
    {
        Authenticate::handle();
        $id = (int) Request::query('id');
        $viewer = $this->viewer();

        if ($this->isPreview()) {
            $post = null;
            foreach (DemoData::posts() as $demo) {
                if ($demo['id'] === $id) {
                    $post = $demo;
                }
            }
            if ($post === null) {
                Response::abort(404, 'Esta publicación no existe o ya no está disponible.');
            }
            $comments = array_map(static fn (array $r) => $r + ['id' => 0, 'user_id' => 0, 'replies' => []], $post['replies']);
            $post['replies'] = [];
            $this->renderPost($post, ['comments' => $comments, 'hasMore' => false], 1);
            return;
        }

        $uid = (int) $viewer['id'];
        $post = $id > 0 ? Post::findVisible($id, $uid) : null;
        if ($post === null) {
            Response::abort(404, 'Esta publicación no existe o ya no está disponible.');
        }
        $page = max(1, (int) Request::query('page', '1'));
        $comments = Comment::forPost($id, $uid, $page, (int) Config::get('app.limits.comments_page', 30));
        $this->renderPost($post, $comments, $page);
    }

    /** edit-post.php?id= : editar texto y visibilidad de una publicación propia. */
    public function edit(): void
    {
        Authenticate::handle();
        $user = $this->requireUser();
        $uid = (int) $user['id'];
        $id = (int) Request::query('id');

        try {
            $post = PostService::findOwnEditable($id, $uid);
        } catch (ActionError $e) {
            Response::abort($e->status, $e->getMessage());
        }

        if (Request::isPost()) {
            VerifyCsrf::handle();
            $this->saveEdit($post);
        }

        $this->render('pages/edit-post', [
            'title'        => 'Editar publicación · TREVIX',
            'activeNav'    => '',
            'post'         => $post,
            'visibilities' => Post::VISIBILITIES,
            'errors'       => Session::pull('_errors', []),
            'old'          => Session::pull('_old', []),
            'aside'        => $this->asideData(),
        ]);
    }

    // -------------------------------------------------------------------------

    private function create(array $user): never
    {
        $uid = (int) $user['id'];
        $fallback = url('feed.php');
        $communityParam = (int) Request::text('community_id');
        if ($communityParam > 0 && ($community = Community::find($communityParam, $uid)) !== null) {
            $fallback = community_url($community);
        }

        $result = $this->attempt(static fn () => PostService::create($user, [
            'format'         => Request::text('format'),
            'visibility'     => Request::text('visibility'),
            'community_id'   => $communityParam,
            'shared_post_id' => (int) Request::text('shared_post_id'),
            'body'           => Request::text('body', false),
            'song_id'        => (int) Request::text('song_id'),
            'song_start'     => (int) Request::text('song_start'),
        ], MediaUpload::collect('media')), $fallback);

        $postId = $result['id'];
        $postUrl = url('post.php', ['id' => $postId]);
        if (Request::wantsJson()) {
            $post = Post::findVisible($postId, $uid);
            Response::json([
                'ok'     => true,
                'id'     => $postId,
                'format' => $result['format'],
                'url'    => $postUrl,
                'community_id' => $result['community_id'],
                'html'   => $post !== null ? View::capture('partials/post-card', ['post' => $post, 'viewer' => $user]) : '',
            ], 201);
        }
        Session::flash('success', $result['shared_id'] !== null ? 'Compartiste la publicación.' : 'Tu publicación se compartió.');
        Response::redirect($postUrl);
    }

    private function destroy(array $user): never
    {
        $postId = (int) Request::text('post_id');
        $this->attempt(static fn () => PostService::delete((int) $user['id'], $postId), url('feed.php'));

        if (Request::wantsJson()) {
            Response::json(['ok' => true]);
        }
        Session::flash('success', 'Eliminaste la publicación.');
        $referer = (string) ($_SERVER['HTTP_REFERER'] ?? '');
        if (str_contains($referer, 'post.php') || str_contains($referer, 'edit-post.php')) {
            Response::redirect(url('profile.php'));
        }
        $this->redirectBack(url('profile.php'));
    }

    private function saveEdit(array $post): never
    {
        $body = Request::text('body', false);
        $visibility = Request::text('visibility');
        // Sin campo song_id (p. ej. la canción ya no está disponible y no se tocó) la canción no cambia.
        $song = Request::input('song_id') !== null ? ['id' => (int) Request::text('song_id'), 'start' => (int) Request::text('song_start')] : null;
        try {
            PostService::update($post, $body, $visibility, $song);
        } catch (ActionError $e) {
            $this->backWithErrors(url('edit-post.php', ['id' => $post['id']]), $e->fields ?: ['body' => $e->getMessage()], [
                'body'       => $this->cleanText($body),
                'visibility' => $post['community'] !== null ? 'public' : $visibility,
            ]);
        }
        Session::flash('success', 'Guardaste los cambios.');
        Response::redirect(url('post.php', ['id' => $post['id']]));
    }

    private function renderPost(array $post, array $comments, int $page): void
    {
        $viewer = $this->viewer();
        $this->render('pages/post', [
            'title'       => $post['user']['display_name'] . ' en TREVIX',
            'activeNav'   => '',
            'post'        => $post,
            'comments'    => $comments['comments'],
            'page'        => $page,
            'hasMore'     => $comments['hasMore'],
            'canModerate' => $viewer !== null && (int) $viewer['id'] === (int) $post['user']['id'],
            'aside'       => $this->asideData(),
        ]);
    }

    /**
     * Si el cuerpo supera post_max_size, PHP descarta $_POST y $_FILES (incluido el token CSRF):
     * se responde con un mensaje claro en lugar de un falso "sesión expirada".
     */
    private function rejectOversizedRequest(): void
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === []) {
            $this->fail('Los archivos superan el tamaño total que acepta el servidor. Prueba con menos archivos o más livianos.', 413, url('feed.php'));
        }
    }
}
