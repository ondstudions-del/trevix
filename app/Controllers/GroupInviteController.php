<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Services\GroupService;

/**
 * Invitación a un grupo por enlace (g.php?c=CÓDIGO): muestra el grupo y permite unirse (públicos) o pedir entrar
 * (privados). Quien tenga el enlace puede ver el nombre, la foto y el número de participantes, nunca los mensajes.
 */
final class GroupInviteController extends Controller
{
    public function show(): void
    {
        $code = strtolower(trim(Request::query('c')));
        if (Request::isPost()) {
            $this->join($code);
        }

        try {
            $preview = GroupService::preview((int) Auth::id(), $code);
        } catch (ActionError $e) {
            Response::abort(404, $e->getMessage());
        }

        $this->render('pages/group-invite', [
            'title'   => $preview['group']['title'] . ' · Grupo de TREVIX',
            'code'    => $code,
            'group'   => $preview['group'],
            'members' => $preview['members_count'],
            'state'   => $preview['state'],
        ]);
    }

    private function join(string $code): never
    {
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $back = url('g.php', ['c' => $code]);
        $result = $this->attempt(static fn () => GroupService::join($user, $code), $back);
        Session::flash('success', $result['message']);
        Response::redirect($result['state'] === 'member' ? url('messages.php', ['c' => $result['conversation_id']]) : $back);
    }
}
