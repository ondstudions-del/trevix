<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\Community;
use Trevix\Services\Moderation;

/** Comunidades (solo administradores): suspender, reactivar y eliminar. */
final class CommunitiesController extends AdminController
{
    public function handle(): void
    {
        $this->guard('communities');
        if (Request::isPost()) {
            $this->act();
        }

        $q = mb_substr(Request::query('q'), 0, 100);
        $status = $this->filter('status', array_keys(Community::STATUS_LABELS));
        $page = $this->pageNumber();
        $result = $this->staff() !== null
            ? Community::adminList($q, $status, $page, $this->perPage())
            : ['communities' => [], 'hasMore' => false];
        $query = ['q' => $q, 'status' => $status];

        $this->page('communities', 'communities', [
            'q'           => $q,
            'status'      => $status,
            'communities' => $result['communities'],
            'prevUrl'     => $page > 1 ? $this->sectionUrl('communities', $query + ['page' => $page - 1]) : null,
            'nextUrl'     => $result['hasMore'] ? $this->sectionUrl('communities', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('communities');
        $staff = $this->beginAction('admin', $fallback);
        $community = Community::findAny((int) Request::input('id', 0));
        if ($community === null) {
            $this->done($fallback, 'Esta comunidad ya no existe.', 'error');
        }

        try {
            $message = match (Request::text('action')) {
                'suspend' => (static function () use ($staff, $community): string {
                    Moderation::suspendCommunity($staff, $community, (string) self::reason());
                    return 'Comunidad suspendida: deja de ser visible y nadie puede publicar en ella.';
                })(),
                'restore' => (function () use ($staff, $community): string {
                    Moderation::restoreCommunity($staff, $community, $this->note());
                    return 'Comunidad reactivada.';
                })(),
                'delete'  => (static function () use ($staff, $community): string {
                    Moderation::deleteCommunity($staff, $community, (string) self::reason());
                    return 'Comunidad eliminada junto con sus publicaciones.';
                })(),
                default   => Response::abort(400, 'Acción no válida.'),
            };
            Session::flash('success', $message);
        } catch (DomainException $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }

    private static function reason(): ?string
    {
        $text = trim((string) preg_replace('/\s+/u', ' ', Request::text('reason')));
        return $text !== '' ? mb_substr($text, 0, 255) : null;
    }
}
