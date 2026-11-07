<?php
declare(strict_types=1);

namespace Trevix\Controllers\Admin;

use DomainException;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Models\Song;
use Trevix\Services\Moderation;

/** Música: revisar las canciones que envían los artistas (aprobar o rechazar) y retirar o restaurar publicadas. */
final class MusicController extends AdminController
{
    public const TABS = [
        'pending'   => 'Por revisar',
        'published' => 'Publicadas',
        'rejected'  => 'Rechazadas',
        'removed'   => 'Retiradas por moderación',
        'withdrawn' => 'Retiradas por el artista',
    ];

    public function handle(): void
    {
        $this->guard('music');
        if (Request::isPost()) {
            $this->act();
        }

        $status = $this->filter('status', array_keys(self::TABS)) ?? 'pending';
        $q = mb_substr(trim(Request::query('q')), 0, 100);
        $page = $this->pageNumber();
        $staff = $this->staff();
        $result = $staff !== null
            ? Song::adminList($status, $q, $page, $this->perPage())
            : ['songs' => [], 'hasMore' => false];
        $query = ['status' => $status === 'pending' ? null : $status, 'q' => $q];

        $this->page('music', 'music', [
            'status'  => $status,
            'q'       => $q,
            'counts'  => $staff !== null ? Song::adminCounts() : array_fill_keys(array_keys(Song::STATUSES), 0),
            'songs'   => $result['songs'],
            'prevUrl' => $page > 1 ? $this->sectionUrl('music', $query + ['page' => $page - 1]) : null,
            'nextUrl' => $result['hasMore'] ? $this->sectionUrl('music', $query + ['page' => $page + 1]) : null,
        ]);
    }

    private function act(): never
    {
        $fallback = $this->sectionUrl('music');
        $staff = $this->beginAction('moderator', $fallback);
        $song = Song::findRaw((int) Request::input('id', 0));
        if ($song === null) {
            $this->done($fallback, 'Esta canción ya no existe.', 'error');
        }

        try {
            $message = match (Request::text('action')) {
                'approve' => (function () use ($staff, $song): string {
                    Moderation::approveSong($staff, $song, $this->note());
                    return '«' . $song['title'] . '» ya está en la biblioteca. Avisamos a @' . $song['username'] . '.';
                })(),
                'reject'  => (function () use ($staff, $song): string {
                    Moderation::rejectSong($staff, $song, (string) $this->note('reason'));
                    return 'Rechazaste «' . $song['title'] . '». Avisamos a @' . $song['username'] . ' con el motivo.';
                })(),
                'remove'  => (function () use ($staff, $song): string {
                    Moderation::removeSong($staff, $song, (string) $this->note('reason'));
                    return 'Retiraste «' . $song['title'] . '» de la biblioteca.';
                })(),
                'restore' => (function () use ($staff, $song): string {
                    Moderation::restoreSong($staff, $song, $this->note());
                    return '«' . $song['title'] . '» vuelve a estar en la biblioteca.';
                })(),
                default   => Response::abort(400, 'Acción no válida.'),
            };
            Session::flash('success', $message);
        } catch (DomainException $e) {
            Session::flash('error', $e->getMessage());
        }
        $this->redirectBack($fallback);
    }
}
