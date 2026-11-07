<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\Comment;
use Trevix\Models\Post;
use Trevix\Models\Report;
use Trevix\Services\Moderation;

/** Revisión de publicaciones y comentarios: buscar, ocultar, restaurar y eliminar. */
final class ContentController extends AdminController
{
    public const TABS = ['posts' => 'Publicaciones', 'comments' => 'Comentarios'];
    public const POST_STATUSES = ['published' => 'Publicadas', 'hidden' => 'Ocultas'];

    public function handle(): void
    {
        $this->guard('content');
        if (Request::isPost()) {
            $this->act();
        }

        $tab = Request::queryIn('tab', array_keys(self::TABS), 'posts');
        $q = mb_substr(Request::query('q'), 0, 100);
        $status = $tab === 'posts' ? $this->filter('status', array_keys(self::POST_STATUSES)) : null;
        $page = $this->pageNumber();
        $staff = $this->staff();

        $items = [];
        $hasMore = false;
        if ($staff !== null) {
            $result = $tab === 'posts'
                ? Post::adminList($q, $status, $page, $this->perPage())
                : Comment::adminList($q, $page, $this->perPage());
            $items = $result[$tab];
            $hasMore = $result['hasMore'];
        }
        $query = ['tab' => $tab, 'q' => $q, 'status' => $status];

        $this->page('content', 'content', [
            'tab'     => $tab,
            'q'       => $q,
            'status'  => $status,
            'items'   => $items,
            'prevUrl' => $page > 1 ? $this->sectionUrl('content', $query + ['page' => $page - 1]) : null,
            'nextUrl' => $hasMore ? $this->sectionUrl('content', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('content');
        $staff = $this->beginAction('moderator', $fallback);
        $action = Request::text('action');
        $id = (int) Request::input('id', 0);
        $note = $this->note();

        try {
            if ($action === 'delete_comment') {
                $target = Report::preview('comment', $id);
                if ($target === null || $target['status'] !== 'published') {
                    throw new DomainException('El comentario ya no existe.');
                }
                Moderation::deleteComment($staff, $target, $note);
                $message = 'Comentario eliminado.';
            } else {
                $target = Report::preview('post', $id);
                if ($target === null) {
                    throw new DomainException('La publicación ya no existe.');
                }
                $message = match ($action) {
                    'hide'    => (static function () use ($staff, $target, $note): string {
                        Moderation::hidePost($staff, $target, $note);
                        return 'Publicación ocultada: ya no aparece en TREVIX.';
                    })(),
                    'restore' => (static function () use ($staff, $target, $note): string {
                        Moderation::restorePost($staff, $target, $note);
                        return 'Publicación restaurada.';
                    })(),
                    'delete'  => (static function () use ($staff, $target, $note): string {
                        Moderation::deletePost($staff, $target, $note);
                        return 'Publicación eliminada definitivamente.';
                    })(),
                    default   => Response::abort(400, 'Acción no válida.'),
                };
            }
            Session::flash('success', $message);
        } catch (DomainException $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }
}
