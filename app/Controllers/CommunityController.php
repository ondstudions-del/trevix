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
use Trevix\Models\Community;
use Trevix\Models\Post;
use Trevix\Services\CommunityService;

/** Listado, creación, página de cada comunidad y todas sus acciones (api/communities.php). */
final class CommunityController extends Controller
{
    private const TABS = [
        'posts'    => 'Publicaciones',
        'popular'  => 'Populares',
        'members'  => 'Miembros',
        'requests' => 'Solicitudes',
        'settings' => 'Ajustes',
    ];

    /** communities.php?tab=discover|mine&q=&category=&page=  ·  communities.php?new=1 (crear). */
    public function index(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Usa el formulario para crear una comunidad.');
        }
        if (Request::query('new') === '1') {
            $this->renderCreate();
            return;
        }

        $tab = Request::queryIn('tab', ['discover', 'mine'], 'discover');
        $term = mb_substr(trim((string) Request::query('q', '')), 0, 80);
        $category = Request::query('category', '');
        $category = in_array($category, Community::CATEGORIES, true) ? $category : null;
        $page = max(1, (int) Request::query('page', '1'));
        $limit = (int) Config::get('app.limits.communities_page', 24);

        if ($this->isPreview()) {
            $result = ['communities' => $this->demoCommunities($tab, $term, $category), 'hasMore' => false];
        } else {
            $uid = (int) $this->viewer()['id'];
            $result = $tab === 'mine'
                ? Community::mine($uid, $page, $limit)
                : Community::discover($uid, $term, $category, $page, $limit);
        }

        $this->render('pages/communities', [
            'title'       => 'Comunidades · TREVIX',
            'activeNav'   => 'communities',
            'tab'         => $tab,
            'term'        => $term,
            'category'    => $category,
            'categories'  => Community::CATEGORIES,
            'communities' => $result['communities'],
            'nextUrl'     => $result['hasMore']
                ? url('communities.php', ['tab' => $tab === 'discover' ? null : $tab, 'q' => $term, 'category' => $category, 'page' => $page + 1])
                : null,
            'aside'       => $this->asideData(),
        ]);
    }

    /** community.php?c=slug&tab=posts|popular|members|requests|settings */
    public function show(): void
    {
        Authenticate::handle();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Las acciones de la comunidad se envían a api/communities.php.');
        }
        $slug = (string) Request::query('c', '');

        if ($this->isPreview()) {
            $this->showDemo($slug);
            return;
        }

        $viewer = $this->viewer();
        $uid = (int) $viewer['id'];
        $community = Community::findBySlug($slug, $uid);
        if ($community === null) {
            Response::abort(404, 'Esta comunidad no existe o ya no está disponible.');
        }

        $access = $this->access($community);
        $allowed = ['posts', 'popular', 'members'];
        if ($access['manager']) {
            $allowed[] = 'requests';
        }
        if ($access['owner']) {
            $allowed[] = 'settings';
        }
        $tab = Request::queryIn('tab', $allowed, 'posts');
        $page = max(1, (int) Request::query('page', '1'));
        $data = [
            'list'     => null,
            'members'  => null,
            'status'   => 'active',
            'nextUrl'  => null,
        ];

        if (in_array($tab, ['posts', 'popular'], true) && $access['canView']) {
            $result = Post::feed($uid, [
                'where'  => 'p.community_id = ?',
                'params' => [$community['id']],
                'order'  => $tab === 'popular' ? 'score' : 'recent',
            ] + $this->paging());
            if ($access['manager']) {
                foreach ($result['posts'] as &$post) {
                    $post['community']['can_moderate'] = $this->canModeratePost($community, $access, (int) $post['user']['id']);
                }
                unset($post);
            }
            $data['list'] = $this->listData($result, 'community.php', ['c' => $community['slug'], 'tab' => $tab === 'posts' ? null : $tab]);
            if ($this->isPartial()) {
                $this->renderList($data['list'], 'Ya viste todas las publicaciones de esta comunidad.');
            }
        } elseif (in_array($tab, ['members', 'requests'], true) && ($access['canView'] || $tab === 'requests')) {
            $status = $tab === 'requests' ? 'pending' : ($access['manager'] && Request::query('status') === 'banned' ? 'banned' : 'active');
            $members = Community::members($community['id'], $status, $page, (int) Config::get('app.limits.members_page', 30));
            $data['members'] = $members['users'];
            $data['status'] = $status;
            $data['nextUrl'] = $members['hasMore']
                ? community_url($community, ['tab' => $tab, 'status' => $status === 'banned' ? 'banned' : null, 'page' => $page + 1])
                : null;
        }

        $this->render('pages/community', $data + [
            'title'        => $community['name'] . ' · Comunidades · TREVIX',
            'activeNav'    => 'communities',
            'community'    => $community,
            'access'       => $access,
            'tab'          => $tab,
            'tabs'         => array_intersect_key(self::TABS, array_flip($allowed)),
            'pendingCount' => $access['manager'] ? Community::pendingCount($community['id']) : 0,
            'categories'   => Community::CATEGORIES,
            'errors'       => Session::pull('_errors', []),
            'old'          => Session::pull('_old', []),
            'aside'        => $this->asideData(),
        ]);
    }

    /** api/communities.php: crear, unirse, salir, moderar y administrar. */
    public function api(): void
    {
        $this->onlyPost();
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === []) {
            $this->fail('Las imágenes superan el tamaño que acepta el servidor.', 413, url('communities.php'));
        }
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $action = Request::text('action');

        if ($action === 'create') {
            $this->create($user);
        }

        $uid = (int) $user['id'];
        $community = $this->attempt(
            static fn () => CommunityService::load($uid, (int) Request::text('community_id')),
            url('communities.php')
        );
        $targetId = (int) Request::text('user_id');

        match ($action) {
            'join'        => $this->membershipResponse($community, $uid, $this->attempt(static fn () => CommunityService::join($uid, $community), community_url($community))),
            'leave'       => $this->membershipResponse($community, $uid, $this->attempt(static fn () => CommunityService::leave($uid, $community), community_url($community, ['tab' => 'settings']))),
            'approve',
            'reject'      => $this->run(static fn () => CommunityService::resolveRequest($uid, $community, $targetId, $action === 'approve'), community_url($community, ['tab' => 'requests'])),
            'ban'         => $this->run(static fn () => CommunityService::ban($uid, $community, $targetId), community_url($community, ['tab' => 'members'])),
            'unban'       => $this->run(static fn () => CommunityService::unban($community, $targetId), community_url($community, ['tab' => 'members', 'status' => 'banned'])),
            'promote',
            'demote'      => $this->run(static fn () => CommunityService::setRole($community, $targetId, $action === 'promote'), community_url($community, ['tab' => 'members'])),
            'remove_post' => $this->run(static fn () => CommunityService::removePost($community, (int) Request::text('post_id')), community_url($community)),
            'update'      => $this->update($uid, $community),
            'transfer'    => $this->transfer($user, $community),
            'delete'      => $this->destroy($user, $community),
            default       => $this->fail('Acción no válida.', 400, community_url($community)),
        };
    }

    // -------------------------------------------------------------------------
    // Acciones
    // -------------------------------------------------------------------------

    private function create(array $user): never
    {
        $name = Request::text('name');
        $description = Request::text('description', false);
        $category = Request::text('category');
        $visibility = Request::text('visibility');
        $created = $this->settle(
            static fn () => CommunityService::create($user, $name, $description, $category, $visibility),
            url('communities.php', ['new' => 1]),
            compact('name', 'description', 'category', 'visibility')
        );

        $url = url('community.php', ['c' => $created['slug']]);
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'url' => $url], 201);
        }
        Session::flash('success', 'Creaste la comunidad «' . trim((string) preg_replace('/\s+/u', ' ', $this->cleanText($name))) . '». Invita a otras personas a unirse.');
        Response::redirect($url);
    }

    /** Datos, imágenes y visibilidad (solo el administrador). */
    private function update(int $uid, array $community): never
    {
        $back = community_url($community, ['tab' => 'settings']);
        $info = [
            'name'        => Request::text('name'),
            'description' => Request::text('description', false),
            'category'    => Request::text('category'),
            'visibility'  => Request::text('visibility'),
        ];
        $message = $this->settle(
            static fn () => CommunityService::update($uid, $community, $info, Request::text('remove_avatar') === '1', Request::text('remove_cover') === '1'),
            $back,
            $info
        );
        Session::flash('success', $message);
        Response::redirect($back);
    }

    private function transfer(array $user, array $community): never
    {
        $username = Request::text('transfer_username');
        $target = $this->settle(
            static fn () => CommunityService::transfer($user, $community, $username, Request::text('transfer_password', false), 'transfer_username', 'transfer_password'),
            community_url($community, ['tab' => 'settings']),
            ['transfer_username' => ltrim(mb_strtolower($username), '@')]
        );
        Session::flash('success', 'Ahora @' . $target['username'] . ' administra la comunidad. Tú sigues como moderador.');
        Response::redirect(community_url($community));
    }

    private function destroy(array $user, array $community): never
    {
        $this->settle(
            static fn () => CommunityService::delete($user, $community, Request::text('delete_confirm'), Request::text('delete_password', false), 'delete_confirm', 'delete_password'),
            community_url($community, ['tab' => 'settings'])
        );
        Session::flash('success', 'Eliminaste la comunidad «' . $community['name'] . '» y todas sus publicaciones.');
        Response::redirect(url('communities.php', ['tab' => 'mine']));
    }

    // -------------------------------------------------------------------------
    // Apoyo
    // -------------------------------------------------------------------------

    private function access(array $community): array
    {
        return CommunityService::access($community);
    }

    private function canModeratePost(array $community, array $access, int $authorId): bool
    {
        return CommunityService::canModeratePost($community, $access, $authorId);
    }

    /** Acción de moderación: responde con su mensaje o con el error del servicio. */
    private function run(callable $action, string $back): never
    {
        $this->done($this->attempt($action, $back), $back);
    }

    /** Formularios de la comunidad: los errores de campo vuelven al formulario y los generales se muestran como aviso. */
    private function settle(callable $action, string $back, array $old = []): mixed
    {
        try {
            return $action();
        } catch (ActionError $e) {
            if ($e->fields === []) {
                $this->fail($e->getMessage(), $e->status, $back);
            }
            if (Request::wantsJson()) {
                Response::json(['ok' => false, 'error' => $e->getMessage(), 'errors' => $e->fields], $e->status);
            }
            $this->backWithErrors($back, $e->fields, $old);
        }
    }

    /** Respuesta de unirse/salir: JSON con el botón actualizado o aviso y vuelta atrás. */
    private function membershipResponse(array $community, int $uid, string $message): never
    {
        $fresh = Community::find($community['id'], $uid) ?? $community;
        if (Request::wantsJson()) {
            Response::json([
                'ok'      => true,
                'message' => $message,
                'state'   => $fresh['membership']['status'] ?? 'none',
                'members' => $fresh['members_count'],
                'html'    => View::capture('partials/community-join', ['community' => $fresh, 'block' => Request::text('block') === '1']),
            ]);
        }
        Session::flash('success', $message);
        $this->redirectBack(community_url($community));
    }

    private function done(string $message, string $back): never
    {
        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'message' => $message]);
        }
        Session::flash('success', $message);
        $this->redirectBack($back);
    }

    private function renderCreate(): void
    {
        $this->render('pages/community-new', [
            'title'        => 'Crear comunidad · TREVIX',
            'activeNav'    => 'communities',
            'categories'   => Community::CATEGORIES,
            'visibilities' => Community::VISIBILITIES,
            'errors'       => Session::pull('_errors', []),
            'old'          => Session::pull('_old', []),
            'aside'        => $this->asideData(),
        ]);
    }

    // -------------------------------------------------------------------------
    // Vista previa (sin sesión, solo lectura)
    // -------------------------------------------------------------------------

    private function demoCommunities(string $tab, string $term, ?string $category): array
    {
        $out = [];
        foreach (DemoData::communities() as $c) {
            $c += ['avatar_path' => null, 'cover_path' => null, 'owner_id' => 0, 'created_at' => date('Y-m-d H:i:s')];
            $c['membership'] = $c['is_member'] ? ['role' => 'member', 'status' => 'active'] : null;
            if ($tab === 'mine' && !$c['is_member']) {
                continue;
            }
            if ($category !== null && $c['category'] !== $category) {
                continue;
            }
            if ($term !== '' && mb_stripos($c['name'] . ' ' . $c['description'], $term) === false) {
                continue;
            }
            $out[] = $c;
        }
        return $out;
    }

    private function showDemo(string $slug): void
    {
        $community = null;
        foreach ($this->demoCommunities('discover', '', null) as $c) {
            if ($c['slug'] === $slug) {
                $community = $c;
            }
        }
        if ($community === null) {
            Response::abort(404, 'Esta comunidad no existe o ya no está disponible.');
        }
        $community['owner'] = null;
        $access = $this->access($community);
        $posts = array_values(array_filter(DemoData::posts(), static fn (array $p) => ($p['community']['slug'] ?? '') === $slug));

        $this->render('pages/community', [
            'title'        => $community['name'] . ' · Comunidades · TREVIX',
            'activeNav'    => 'communities',
            'community'    => $community,
            'access'       => $access,
            'tab'          => 'posts',
            'tabs'         => ['posts' => self::TABS['posts']],
            'list'         => $access['canView'] ? ['posts' => $posts, 'nextUrl' => null] : null,
            'members'      => null,
            'status'       => 'active',
            'nextUrl'      => null,
            'pendingCount' => 0,
            'categories'   => Community::CATEGORIES,
            'errors'       => [],
            'old'          => [],
            'aside'        => $this->asideData(),
        ]);
    }
}
