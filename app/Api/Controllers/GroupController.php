<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Models\Conversation;
use Trevix\Models\Group;
use Trevix\Services\GroupService;

/**
 * Grupos de mensajes: crear, ajustes del administrador (nombre, foto, portada, estilo, descripción, visibilidad),
 * participantes, administradores, enlace de invitación, solicitudes y búsqueda de grupos públicos.
 * Los mensajes del grupo usan las rutas de /conversations/{id}.
 */
final class GroupController extends ApiController
{
    /** POST /groups {title, description?, visibility: private|public, members: [usuarios]} + «avatar» opcional. */
    public function create(): never
    {
        $user = $this->user();
        $members = Input::raw('members');
        if (is_string($members)) {
            $members = explode(',', $members);
        }
        $result = GroupService::create(
            $user,
            Input::str('title'),
            Input::str('description', false),
            Input::str('visibility') ?: 'private',
            is_array($members) ? array_map('strval', array_filter($members, 'is_scalar')) : []
        );
        $this->created([
            'conversation' => Present::conversation($this->conversation($result['id'])),
            'failed'       => $result['failed'],
            'message'      => 'Creaste el grupo.',
        ]);
    }

    /** GET /groups?q= — grupos públicos por nombre o descripción. */
    public function search(): never
    {
        $term = trim(mb_substr(Request::query('q'), 0, 80));
        if (mb_strlen($term) < 2) {
            Reply::ok([]);
        }
        Reply::ok(array_map(static fn (array $g): array => [
            'id'            => (int) $g['id'],
            'title'         => (string) $g['title'],
            'description'   => (string) ($g['description'] ?? ''),
            'avatar_url'    => Present::file($g['avatar_path']),
            'members_count' => (int) $g['members_count'],
            'is_member'     => (bool) $g['is_member'],
            'invite_code'   => (string) $g['invite_code'],
        ], Group::searchPublic($term, $this->uid(), 30)));
    }

    /** PATCH /groups/{id} {title?, description?, theme?, visibility?, disappear_seconds?} — administradores. */
    public function update(string $id): never
    {
        $uid = $this->uid();
        $group = GroupService::load($uid, (int) $id);
        $changes = [];
        foreach (['title', 'description', 'theme', 'visibility'] as $key) {
            if (Input::has($key)) {
                $changes[$key] = Input::str($key, $key !== 'description');
            }
        }
        if (Input::has('disappear_seconds')) {
            $changes['disappear_seconds'] = Input::int('disappear_seconds');
        }
        if ($changes === []) {
            throw new ActionError('No hay cambios que guardar.');
        }
        $this->respond(GroupService::update($uid, $group, $changes), (int) $id);
    }

    /** POST|DELETE /groups/{id}/avatar y /groups/{id}/cover (multipart, campo «avatar» o «cover»). */
    public function image(string $id, string $kind): never
    {
        $uid = $this->uid();
        $group = GroupService::load($uid, (int) $id);
        $this->respond(GroupService::image($uid, $group, $kind, Request::method() === 'DELETE'), (int) $id);
    }

    /** GET /groups/{id}/members?page= */
    public function members(string $id): never
    {
        $uid = $this->uid();
        GroupService::load($uid, (int) $id);
        $result = Group::members((int) $id, $this->pageNumber(), $this->limit('members_page', 30));
        Reply::ok(array_map(static fn (array $m): array => Present::user($m) + [
            'role'      => $m['role'],
            'is_me'     => (int) $m['id'] === $uid,
            'has_key'   => (bool) $m['has_key'],
            'available' => $m['status'] === 'active',
            'joined_at' => Present::date($m['joined_at']),
        ], $result['users']), $this->nextPage($result['hasMore']) + [
            'count'    => Group::memberCount((int) $id),
            'requests' => Group::isManager(Group::role((int) $id, $uid)) ? Group::requestCount((int) $id) : 0,
        ]);
    }

    /** POST /groups/{id}/members {members: [usuarios]} — administradores. */
    public function addMembers(string $id): never
    {
        $uid = $this->uid();
        $group = GroupService::load($uid, (int) $id);
        $members = Input::raw('members');
        if (is_string($members)) {
            $members = explode(',', $members);
        }
        $result = GroupService::addMembers($uid, $group, is_array($members) ? array_map('strval', array_filter($members, 'is_scalar')) : []);
        $count = count($result['added']);
        Reply::ok($result + [
            'message'      => $count === 1 ? 'Añadiste a @' . $result['added'][0] . '.' : 'Añadiste a ' . $count . ' personas.',
            'conversation' => Present::conversation($this->conversation((int) $id)),
        ]);
    }

    /** DELETE /groups/{id}/members/{id2} — quitar a alguien (administradores). */
    public function removeMember(string $id, string $userId): never
    {
        $uid = $this->uid();
        GroupService::removeMember($uid, GroupService::load($uid, (int) $id), (int) $userId);
        $this->respond('Quitaste a esa persona del grupo.', (int) $id);
    }

    /** DELETE /groups/{id}/membership — salir del grupo. */
    public function leave(string $id): never
    {
        $uid = $this->uid();
        GroupService::leave($uid, GroupService::load($uid, (int) $id));
        Reply::ok(['message' => 'Saliste del grupo.', 'unread' => Conversation::unreadCount($uid)]);
    }

    /** POST|DELETE /groups/{id}/admins/{id2} — nombrar o quitar administrador (solo el creador). */
    public function admin(string $id, string $userId): never
    {
        $uid = $this->uid();
        $admin = Request::method() !== 'DELETE';
        GroupService::setAdmin($uid, GroupService::load($uid, (int) $id), (int) $userId, $admin);
        $this->respond($admin ? 'Ahora es administrador.' : 'Ya no es administrador.', (int) $id);
    }

    /** POST /groups/{id}/invite — restablecer el enlace de invitación (administradores). */
    public function resetInvite(string $id): never
    {
        $uid = $this->uid();
        GroupService::resetInvite($uid, GroupService::load($uid, (int) $id));
        $this->respond('Restableciste el enlace: el anterior ya no funciona.', (int) $id);
    }

    /** GET /groups/{id}/requests — solicitudes para entrar (administradores). */
    public function requests(string $id): never
    {
        $uid = $this->uid();
        $group = GroupService::load($uid, (int) $id);
        if (!Group::isManager($group['viewer_role'])) {
            throw new ActionError('Solo los administradores del grupo ven las solicitudes.', 403);
        }
        Reply::ok(array_map(static fn (array $r): array => Present::user($r) + [
            'requested_at' => Present::date($r['created_at']),
        ], Group::requests((int) $id)));
    }

    /** POST /groups/{id}/requests/{id2}/approve|reject */
    public function resolve(string $id, string $userId, string $action): never
    {
        $uid = $this->uid();
        $message = GroupService::resolveRequest($uid, GroupService::load($uid, (int) $id), (int) $userId, $action === 'approve');
        $this->respond($message, (int) $id);
    }

    /** GET /invites/{key} — vista previa del enlace de invitación. */
    public function invite(string $code): never
    {
        $preview = GroupService::preview($this->uid(), $code);
        $g = $preview['group'];
        Reply::ok([
            'id'            => (int) $g['id'],
            'title'         => (string) $g['title'],
            'description'   => (string) ($g['description'] ?? ''),
            'avatar_url'    => Present::file($g['avatar_path']),
            'cover_url'     => Present::file($g['cover_path']),
            'visibility'    => $g['visibility'] ?: 'private',
            'members_count' => $preview['members_count'],
            'state'         => $preview['state'],
        ]);
    }

    /** POST /invites/{key}/join — público: entrar; privado: pedir unirse. */
    public function join(string $code): never
    {
        $result = GroupService::join($this->user(), $code);
        $data = $result;
        if ($result['state'] === 'member') {
            $data['conversation'] = Present::conversation($this->conversation($result['conversation_id']));
        }
        Reply::ok($data);
    }

    private function conversation(int $id): array
    {
        return Conversation::findFor($id, $this->uid()) ?? throw new ActionError('Este grupo ya no está disponible.', 404);
    }

    private function respond(string $message, int $groupId): never
    {
        Reply::ok(['message' => $message, 'conversation' => Present::conversation($this->conversation($groupId))]);
    }
}
