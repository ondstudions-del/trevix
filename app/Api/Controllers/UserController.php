<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\Block;
use Trevix\Models\Collaborator;
use Trevix\Models\Conversation;
use Trevix\Models\Follow;
use Trevix\Models\Note;
use Trevix\Models\Playlist;
use Trevix\Models\Post;
use Trevix\Models\ProfileAlert;
use Trevix\Models\Story;
use Trevix\Models\User;
use Trevix\Models\UserProfile;
use Trevix\Services\CollaboratorService;
use Trevix\Services\ProfileDetailsService;
use Trevix\Services\RelationshipService;

/** Perfiles de otras cuentas, sus publicaciones y conexiones, seguir y bloquear. */
final class UserController extends ApiController
{
    /** GET /users/{username} */
    public function show(string $username): never
    {
        [$profile, $context] = $this->load($username);
        $uid = $this->uid();
        $data = Present::profile($profile) + $context;
        $details = $context['is_blocked'] ? null
            : ProfileDetailsService::visibleTo($profile, UserProfile::forUser((int) $profile['id']), $uid, $context['relation']);
        if ($details !== null && !$context['can_view']) {
            $details = ['song' => $details['song']];
        }
        $data['details'] = $details !== null ? Present::details($details) : null;
        if (!$context['is_own'] && !$context['is_blocked']) {
            $conversationId = Conversation::findDirectId($uid, (int) $profile['id']);
            $data['message'] = [
                'conversation_id' => $conversationId,
                'blocked_reason'  => Conversation::cannotMessage($uid, $profile, $conversationId),
            ];
            // Campana del perfil: avisos de sus publicaciones, notas e historias (PUT/DELETE /users/{id}/alerts).
            $data['alerts'] = ProfileAlert::isOn($uid, (int) $profile['id']);
        }
        $ring = $context['is_blocked'] ? null : Story::ringFor((int) $profile['id'], $uid);
        $data['stories'] = $ring !== null ? ['active' => true, 'unseen' => $ring['unseen']] : ['active' => false, 'unseen' => false];
        $note = $context['is_blocked'] ? null : (Note::forAuthors([(int) $profile['id']], $uid)[(int) $profile['id']] ?? null);
        $data['note'] = $note !== null ? Present::note($note) : null;
        $data['web_url'] = absolute_url('profile.php?u=' . rawurlencode((string) $profile['username']));
        $data['collaborator'] = $context['is_blocked'] ? null : CollaboratorService::profileOffer((int) $profile['id'], $uid);
        Reply::ok($data);
    }

    /** GET /users/{username}/posts?tab=posts|threads|media&before= */
    public function posts(string $username): never
    {
        [$profile, $context] = $this->load($username);
        // En una cuenta privada, quien tiene una suscripción vigente ve las publicaciones para suscriptores.
        if (!$context['can_view'] && ($context['is_blocked'] || Collaborator::accessUntil($this->uid(), (int) $profile['id']) === null)) {
            Reply::ok([], ['next' => null, 'private' => true]);
        }
        $tab = Request::queryIn('tab', ['posts', 'threads', 'media', 'exclusive'], 'posts');
        $result = Post::feed($this->uid(), [
            'where'  => 'p.user_id = ?' . match ($tab) {
                'threads'   => " AND p.format = 'thread'",
                'media'     => ' AND EXISTS (SELECT 1 FROM post_media pm WHERE pm.post_id = p.id)',
                'exclusive' => " AND p.visibility = 'subscribers'",
                default     => '',
            },
            'params' => [(int) $profile['id']],
        ] + $this->paging());
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /** GET /users/{username}/playlists — listas de reproducción de reels de un creador de contenido. */
    public function playlists(string $username): never
    {
        [$profile, $context] = $this->load($username);
        if ($context['is_blocked'] || (!$context['is_own'] && !User::isCreator($profile))) {
            Reply::ok([]);
        }
        Reply::ok(array_map([Present::class, 'playlist'], Playlist::forUser((int) $profile['id'])));
    }

    /** GET /users/{username}/followers · /following ?page= */
    public function connections(string $username, string $type): never
    {
        [$profile, $context] = $this->load($username);
        if (!$context['can_view']) {
            Reply::ok([], ['next' => null, 'private' => true]);
        }
        $result = Follow::connections($type, (int) $profile['id'], $this->uid(), $this->pageNumber(), $this->limit('people_page', 30));
        Reply::ok(array_map([Present::class, 'user'], $result['users']), $this->nextPage($result['hasMore']));
    }

    /** GET /users/{username}/stories — historias activas visibles de esa cuenta. */
    public function stories(string $username): never
    {
        [$profile] = $this->load($username);
        $uid = $this->uid();
        $groups = Story::groupsFor([(int) $profile['id']], $uid);
        $notes = Note::forAuthors([(int) $profile['id']], $uid);
        foreach ($groups as &$group) {
            $group['note'] = $notes[(int) $group['user']['id']] ?? null;
            $group['replyBlocked'] = (int) $group['user']['id'] === $uid ? null
                : Conversation::cannotMessage($uid, $group['user'], Conversation::findDirectId($uid, (int) $group['user']['id']));
        }
        unset($group);
        Reply::ok($groups !== [] ? Present::storyGroup($groups[0]) : null);
    }

    /** POST /users/{id}/follow — sigue o envía solicitud (cuentas privadas). */
    public function follow(string $id): never
    {
        $this->relationship((int) $id, 'follow');
    }

    /** DELETE /users/{id}/follow — deja de seguir o cancela la solicitud. */
    public function unfollow(string $id): never
    {
        $this->relationship((int) $id, 'unfollow');
    }

    /** DELETE /users/{id}/follower — quita a esa persona de tus seguidores. */
    public function removeFollower(string $id): never
    {
        $this->relationship((int) $id, 'remove');
    }

    /** POST /users/{id}/block · DELETE /users/{id}/block */
    public function block(string $id): never
    {
        $result = RelationshipService::block($this->uid(), (int) $id, Request::method() === 'DELETE' ? 'unblock' : 'block');
        Reply::ok(['message' => $result['message'], 'blocked' => Request::method() !== 'DELETE']);
    }

    private function relationship(int $id, string $action): never
    {
        $uid = $this->uid();
        $result = RelationshipService::follow($uid, $id, $action);
        Reply::ok([
            'message'         => $result['message'],
            'state'           => $result['state'],
            'relation'        => Present::relation(Follow::relation($uid, $id)),
            'followers_count' => $result['followers_count'],
        ]);
    }

    /**
     * Perfil visible para quien mira. Si esa cuenta te bloqueó, para ti no existe; si la bloqueaste tú,
     * la ves para poder desbloquearla, sin su contenido.
     *
     * @return array{0: array, 1: array{is_own: bool, is_blocked: bool, can_view: bool, relation: ?array}}
     */
    private function load(string $username): array
    {
        $username = mb_strtolower($username);
        $profile = preg_match('/^[a-z0-9_.]{3,30}$/', $username) ? User::findByUsername($username) : null;
        $uid = $this->uid();
        $isOwn = $profile !== null && (int) $profile['id'] === $uid;
        if ($profile === null || (!$isOwn && ($profile['status'] !== 'active' || Block::exists((int) $profile['id'], $uid)))) {
            $this->notFound(t('No encontramos a @{username}.', ['username' => $username]));
        }
        $isBlocked = !$isOwn && Block::exists($uid, (int) $profile['id']);
        $relation = $isOwn ? null : Follow::relation($uid, (int) $profile['id']);
        return [$profile, [
            'is_own'     => $isOwn,
            'is_blocked' => $isBlocked,
            'can_view'   => !$isBlocked && ($isOwn || empty($profile['is_private']) || !empty($relation['following'])),
            'relation'   => $relation !== null ? Present::relation($relation) : null,
        ]];
    }
}
