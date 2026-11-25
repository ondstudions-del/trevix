<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\ActionError;
use Trevix\Core\Request;
use Trevix\Models\Community;
use Trevix\Models\Post;
use Trevix\Models\PostListing;
use Trevix\Services\AdService;
use Trevix\Services\CommunityRecommendService;
use Trevix\Services\CommunityService;

/**
 * Comunidades: descubrir, crear, ver, publicaciones y miembros, unirse y salir, moderar y administrar.
 * Las rutas de lectura aceptan el id o el slug; las acciones, el id numérico.
 */
final class CommunityController extends ApiController
{
    /** GET /communities?tab=discover|mine&q=&category=&page= */
    public function index(): never
    {
        $uid = $this->uid();
        $tab = Request::queryIn('tab', ['discover', 'mine'], 'discover');
        $category = Request::query('category');
        $kind = Request::query('kind');
        $limit = $this->limit('communities_page', 24);
        $kindOk = in_array($kind, array_keys(Community::KINDS), true) ? $kind : null;
        $result = $tab === 'mine'
            ? Community::mine($uid, $this->pageNumber(), $limit)
            : Community::discover(
                $uid,
                mb_substr(trim(Request::query('q')), 0, 80),
                in_array($category, Community::CATEGORIES, true) ? $category : null,
                $this->pageNumber(),
                $limit,
                $kindOk,
            );
        Reply::ok(array_map([Present::class, 'community'], $result['communities']), $this->nextPage($result['hasMore']));
    }

    /** GET /communities/hubs — carriles: cerca, recomendadas, populares, nuevas, intereses */
    public function hubs(): never
    {
        $uid = $this->uid();
        $h = CommunityRecommendService::hubs($uid);
        $map = static fn (array $rows) => array_map([Present::class, 'community'], $rows);
        Reply::ok([
            'near'        => $map($h['near']),
            'recommended' => $map($h['recommended']),
            'popular'     => $map($h['popular']),
            'recent'      => $map($h['recent']),
            'interests'   => $map($h['interests']),
        ]);
    }

    /** POST /communities {name, description?, category, visibility?, kind?, location?, location_city?, ...} */
    public function create(): never
    {
        $created = CommunityService::create(
            $this->user(),
            Input::str('name'),
            Input::str('description', false),
            Input::str('category'),
            Input::str('visibility'),
            Input::str('kind') ?: 'club',
            Input::has('location') ? Input::str('location') : null,
            Input::has('location_city') ? Input::str('location_city') : null,
            Input::has('location_region') ? Input::str('location_region') : null,
            Input::has('location_lat') ? (float) Input::raw('location_lat') : null,
            Input::has('location_lng') ? (float) Input::raw('location_lng') : null,
        );
        $community = Community::findBySlug($created['slug'], $this->uid());
        $this->created($community !== null ? Present::community($community, CommunityService::access($community)) : $created);
    }

    /** GET /communities/{key} */
    public function show(string $key): never
    {
        $community = $this->find($key);
        $access = CommunityService::access($community);
        $data = Present::community($community, $access);
        $data['pending_requests'] = $access['manager'] ? Community::pendingCount($community['id']) : null;
        $data['rules'] = CommunityService::rules($community);
        Reply::ok($data);
    }

    /** PATCH /communities/{id}/settings — ajustes avanzados (quién publica, formatos, color…). */
    public function settings(string $id): never
    {
        $uid = $this->uid();
        $community = CommunityService::load($uid, (int) $id);
        $input = [
            'settings'         => Input::has('settings') ? Input::raw('settings') : null,
            'color'            => Input::has('color') ? Input::str('color') : null,
            'location'         => Input::has('location') ? Input::str('location') : null,
            'welcome_message'  => Input::has('welcome_message') ? Input::str('welcome_message', false) : null,
            'hidden'           => Input::has('hidden') ? Input::raw('hidden') : null,
        ];
        // Solo pasa claves presentes.
        $payload = array_filter($input, static fn ($v) => $v !== null);
        if (Input::has('hidden')) {
            $payload['hidden'] = filter_var(Input::raw('hidden'), FILTER_VALIDATE_BOOLEAN);
        }
        $this->respond(CommunityService::saveSettings($community, $payload), (int) $id);
    }

    /** GET /communities/{key}/rules */
    public function rules(string $key): never
    {
        Reply::ok(CommunityService::rules($this->find($key)));
    }

    /** POST /communities/{id}/rules {title, body} */
    public function addRule(string $id): never
    {
        $uid = $this->uid();
        $community = CommunityService::load($uid, (int) $id);
        $rule = CommunityService::addRule($community, Input::str('title'), Input::str('body', false));
        Reply::ok(['message' => 'Regla agregada.', 'rule' => $rule, 'rules' => CommunityService::rules($community)]);
    }

    /** PATCH /communities/{id}/rules/{id2} {title, body} */
    public function updateRule(string $id, string $ruleId): never
    {
        $uid = $this->uid();
        $community = CommunityService::load($uid, (int) $id);
        CommunityService::updateRule($community, (int) $ruleId, Input::str('title'), Input::str('body', false));
        Reply::ok(['message' => 'Regla actualizada.', 'rules' => CommunityService::rules($community)]);
    }

    /** DELETE /communities/{id}/rules/{id2} */
    public function deleteRule(string $id, string $ruleId): never
    {
        $uid = $this->uid();
        $community = CommunityService::load($uid, (int) $id);
        CommunityService::deleteRule($community, (int) $ruleId);
        Reply::ok(['message' => 'Regla eliminada.', 'rules' => CommunityService::rules($community)]);
    }

    /** GET /communities/{key}/posts?sort=recent|popular&before=|page= */
    public function posts(string $key): never
    {
        $community = $this->find($key);
        $access = CommunityService::access($community);
        if (!$access['canView']) {
            Reply::ok([], ['next' => null, 'private' => true]);
        }
        $result = Post::feed($this->uid(), [
            'where'  => 'p.community_id = ?',
            'params' => [$community['id']],
            'order'  => Request::queryIn('sort', ['recent', 'popular'], 'recent') === 'popular' ? 'score' : 'recent',
        ] + $this->paging());
        if ($access['manager']) {
            foreach ($result['posts'] as &$post) {
                $post['community']['can_moderate'] = CommunityService::canModeratePost($community, $access, (int) $post['user']['id']);
            }
            unset($post);
        }
        $posts = $result['posts'];
        $page = $this->pageNumber();
        $meta = ['next' => $result['next']];
        if ($page === 1) {
            $sponsored = AdService::sponsoredMeta($this->uid(), 'community', count($posts), 3);
            if ($sponsored !== null) {
                $meta['sponsored'] = ['position' => $sponsored['position'], 'ad' => Present::ad($sponsored['ad'])];
            }
        }
        Reply::ok(Present::posts($posts), $meta);
    }

    /** GET /communities/{key}/products — catálogo en comunidades de ventas (q, category, min_price, max_price, page). */
    public function products(string $key): never
    {
        $community = $this->find($key);
        $access = CommunityService::access($community);
        if (($community['kind'] ?? 'club') !== 'sales') {
            throw new ActionError('Esta comunidad no tiene catálogo de productos.', 404);
        }
        if (!$access['canView']) {
            Reply::ok([], ['next' => null, 'private' => true]);
        }
        $min = Request::query('min_price') !== '' ? (int) round((float) Request::query('min_price') * 100) : null;
        $max = Request::query('max_price') !== '' ? (int) round((float) Request::query('max_price') * 100) : null;
        $cat = Request::query('category');
        $result = PostListing::discoverInCommunity(
            $community['id'],
            $this->uid(),
            mb_substr(trim(Request::query('q')), 0, 80),
            in_array($cat, PostListing::PRODUCT_CATEGORIES, true) ? $cat : null,
            $min,
            $max,
            $this->pageNumber(),
            $this->limit('communities_page', 24),
        );
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /** GET /communities/{key}/members?status=active|pending|banned&page= — pending y banned solo para quien modera. */
    public function members(string $key): never
    {
        $community = $this->find($key);
        $access = CommunityService::access($community);
        $status = Request::queryIn('status', ['active', 'pending', 'banned'], 'active');
        if ($status !== 'active' && !$access['manager']) {
            throw new ActionError('Solo quienes moderan la comunidad pueden ver esa lista.', 403);
        }
        if (!$access['canView'] && $status === 'active') {
            Reply::ok([], ['next' => null, 'private' => true]);
        }
        $result = Community::members($community['id'], $status, $this->pageNumber(), $this->limit('members_page', 30));
        Reply::ok(array_map(static fn (array $m) => Present::user($m) + [
            'role'      => $m['role'],
            'status'    => $m['status'],
            'joined_at' => Present::date($m['joined_at']),
        ], $result['users']), $this->nextPage($result['hasMore']));
    }

    /** POST /communities/{id}/join — en las privadas queda como solicitud. */
    public function join(string $id): never
    {
        $uid = $this->uid();
        $this->respond(CommunityService::join($uid, CommunityService::load($uid, (int) $id)), (int) $id);
    }

    /** DELETE /communities/{id}/membership — salir o cancelar la solicitud. */
    public function leave(string $id): never
    {
        $uid = $this->uid();
        $this->respond(CommunityService::leave($uid, CommunityService::load($uid, (int) $id)), (int) $id);
    }

    /** POST /communities/{id}/requests/{id2}/approve · /reject */
    public function resolveRequest(string $id, string $userId, string $action): never
    {
        $uid = $this->uid();
        $this->respond(CommunityService::resolveRequest($uid, CommunityService::load($uid, (int) $id), (int) $userId, $action === 'approve'), (int) $id);
    }

    /** POST /communities/{id}/bans/{id2} · DELETE /communities/{id}/bans/{id2} */
    public function ban(string $id, string $userId): never
    {
        $uid = $this->uid();
        $community = CommunityService::load($uid, (int) $id);
        $this->respond(Request::method() === 'DELETE'
            ? CommunityService::unban($community, (int) $userId)
            : CommunityService::ban($uid, $community, (int) $userId), (int) $id);
    }

    /** POST /communities/{id}/moderators/{id2} · DELETE /communities/{id}/moderators/{id2} (solo el administrador). */
    public function moderator(string $id, string $userId): never
    {
        $uid = $this->uid();
        $this->respond(CommunityService::setRole(CommunityService::load($uid, (int) $id), (int) $userId, Request::method() !== 'DELETE'), (int) $id);
    }

    /** DELETE /communities/{id}/posts/{id2} — quitar una publicación de la comunidad. */
    public function removePost(string $id, string $postId): never
    {
        $uid = $this->uid();
        $this->respond(CommunityService::removePost(CommunityService::load($uid, (int) $id), (int) $postId), (int) $id);
    }

    /** PATCH /communities/{id} {name?, description?, category?, visibility?} (solo el administrador). */
    public function update(string $id): never
    {
        $uid = $this->uid();
        $community = CommunityService::load($uid, (int) $id);
        $info = [];
        foreach (['name', 'description', 'category', 'visibility'] as $field) {
            $info[$field] = Input::has($field) ? Input::str($field, $field !== 'description') : (string) $community[$field];
        }
        $_FILES = [];
        $this->respond(CommunityService::update($uid, $community, $info, false, false), (int) $id);
    }

    /** POST /communities/{id}/avatar · /cover (multipart, campo «avatar» o «cover») · DELETE para quitarla. */
    public function image(string $id, string $kind): never
    {
        $uid = $this->uid();
        $community = CommunityService::load($uid, (int) $id);
        $remove = Request::method() === 'DELETE';
        if ($remove) {
            $_FILES = [];
        } elseif (!isset($_FILES[$kind]) || (int) ($_FILES[$kind]['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
            throw ActionError::field($kind, t('Adjunta la imagen en el campo «{field}» (multipart/form-data).', ['field' => $kind]));
        }
        $info = [];
        foreach (['name', 'description', 'category', 'visibility'] as $field) {
            $info[$field] = (string) $community[$field];
        }
        CommunityService::update($uid, $community, $info, $remove && $kind === 'avatar', $remove && $kind === 'cover');
        $this->respond($remove ? 'Quitaste la imagen.' : 'Guardaste la imagen.', (int) $id);
    }

    /** POST /communities/{id}/transfer {username, password} */
    public function transfer(string $id): never
    {
        $user = $this->user();
        $target = CommunityService::transfer(
            $user,
            CommunityService::load((int) $user['id'], (int) $id),
            Input::str('username'),
            Input::str('password', false),
            'username',
            'password'
        );
        $this->respond(t('Ahora @{username} administra la comunidad. Tú sigues como moderador.', ['username' => $target['username']]), (int) $id);
    }

    /** DELETE /communities/{id} {confirm: slug, password} */
    public function destroy(string $id): never
    {
        $user = $this->user();
        $community = CommunityService::load((int) $user['id'], (int) $id);
        CommunityService::delete($user, $community, Input::str('confirm'), Input::str('password', false), 'confirm', 'password');
        Reply::ok(['message' => t('Eliminaste la comunidad «{name}» y todas sus publicaciones.', ['name' => $community['name']])]);
    }

    /** Respuesta de las acciones: el mensaje y la comunidad como queda (null si ya no se puede ver). */
    private function respond(string $message, int $id): never
    {
        $community = Community::find($id, $this->uid());
        Reply::ok([
            'message'   => $message,
            'community' => $community !== null ? Present::community($community, CommunityService::access($community)) : null,
        ]);
    }

    private function find(string $key): array
    {
        $uid = $this->uid();
        if (ctype_digit($key)) {
            $byId = Community::find((int) $key, $uid);
            $community = Community::findBySlug($byId !== null ? (string) $byId['slug'] : $key, $uid);
        } else {
            $community = Community::findBySlug(mb_strtolower($key), $uid);
        }
        if ($community === null) {
            $this->notFound('Esta comunidad no existe o ya no está disponible.');
        }
        return $community;
    }
}
