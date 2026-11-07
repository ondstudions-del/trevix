<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Services\RelationshipService;

/** Seguir, solicitudes de seguimiento y bloqueos. Responde JSON con JavaScript y redirige sin él. */
final class RelationshipController extends Controller
{
    /** api/follows.php: action = follow | unfollow | cancel | accept | reject | remove. */
    public function follows(): void
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $uid = (int) $this->requireUser()['id'];
        $action = Request::text('action');
        $fallback = $action === 'accept' ? url('notifications.php', ['filter' => 'requests']) : url('feed.php');
        $result = $this->attempt(
            static fn () => RelationshipService::follow($uid, (int) Request::text('user_id'), $action),
            $fallback
        );
        $target = $result['target'];

        if (Request::wantsJson()) {
            Response::json([
                'ok'              => true,
                'user_id'         => (int) $target['id'],
                'state'           => $result['state'],
                'followers_count' => $result['followers_count'],
                'message'         => $result['message'],
            ]);
        }
        Session::flash('success', $result['message']);
        $this->redirectBack(url('profile.php', ['u' => $target['username']]));
    }

    /** api/blocks.php: action = block | unblock. */
    public function blocks(): void
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $uid = (int) $this->requireUser()['id'];
        $action = Request::text('action');
        $result = $this->attempt(
            static fn () => RelationshipService::block($uid, (int) Request::text('user_id'), $action),
            url('settings.php', ['section' => 'privacy'])
        );

        Session::flash('success', $result['message']);
        if ($action === 'block') {
            Response::redirect(url('profile.php', ['u' => $result['target']['username']]));
        }
        $this->redirectBack(url('settings.php', ['section' => 'privacy']));
    }
}
