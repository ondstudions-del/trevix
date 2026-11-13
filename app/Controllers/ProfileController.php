<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\ActionError;
use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Response;
use Trevix\Core\Request;
use Trevix\Core\Session;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Block;
use Trevix\Models\Conversation;
use Trevix\Models\Follow;
use Trevix\Models\Playlist;
use Trevix\Models\Post;
use Trevix\Models\Song;
use Trevix\Models\Story;
use Trevix\Models\User;
use Trevix\Services\AccountRules;
use Trevix\Services\CollaboratorService;
use Trevix\Services\ProfileService;

final class ProfileController extends Controller
{
    public const TABS = ['posts' => 'Publicaciones', 'threads' => 'Hilos', 'media' => 'Multimedia', 'followers' => 'Seguidores', 'following' => 'Seguidos'];

    public function show(): void
    {
        Authenticate::handle();

        $viewer = $this->viewer();
        $username = mb_strtolower(Request::query('u', (string) ($viewer['username'] ?? '')));
        if (!preg_match('/^[a-z0-9_.]{3,30}$/', $username)) {
            Response::abort(404, 'Ese perfil no existe.');
        }

        $preview = $this->isPreview();
        $profile = $preview ? DemoData::user($username) : User::findByUsername($username);
        $isOwn = $profile !== null && $viewer !== null && $viewer['username'] === $profile['username'];
        $isBlocked = false;
        if ($profile !== null && !$preview && !$isOwn) {
            $uid = (int) $viewer['id'];
            $pid = (int) $profile['id'];
            // Si esa cuenta te bloqueó, para ti no existe. Si la bloqueaste tú, ves el perfil para poder desbloquearla.
            if ($profile['status'] !== 'active' || Block::exists($pid, $uid)) {
                $profile = null;
            } else {
                $isBlocked = Block::exists($uid, $pid);
                $profile['relation'] = Follow::relation($uid, $pid);
            }
        }
        if ($profile === null) {
            Response::abort(404, t('No encontramos a @{username}.', ['username' => $username]));
        }

        $tabs = self::TABS;
        // Creadores de contenido: listas de reproducción de reels en lugar de hilos.
        if (!$preview && User::isCreator($profile)) {
            $tabs = ['posts' => $tabs['posts'], 'lists' => 'Listas'] + $tabs;
            unset($tabs['threads']);
        }
        // Música: artistas musicales y cuentas con canciones en la biblioteca (pública aunque el perfil sea privado).
        $hasMusic = !$preview && (User::isMusicArtist($profile) || Song::publishedCountForArtist((int) $profile['id']) > 0);
        $extra = ($hasMusic ? ['music' => t('Música')] : []) + ($isOwn ? ['saved' => t('Guardados')] : []);
        $tabs = array_slice($tabs, 0, 3, true) + $extra + array_slice($tabs, 3, null, true);
        $tab = Request::queryIn('tab', array_keys($tabs), 'posts');
        // Guardado: lo guardado, lo propio en «Solo yo» (publicaciones, reels e historias) y lo que le gustó.
        $savedCat = Request::queryIn('cat', ['saved', 'private', 'liked'], 'saved');
        $savedKind = Request::queryIn('kind', $savedCat === 'private' ? ['all', 'posts', 'reels', 'stories'] : ['all', 'posts', 'reels'], 'all');
        if ($tab !== 'saved' || $preview) {
            $savedKind = 'all';
        }
        $privateStories = [];
        $privateStoriesNext = null;

        $list = ['posts' => [], 'nextUrl' => null];
        $playlists = [];
        $songs = [];
        $songsNext = null;
        if ($preview) {
            $canView = $isOwn || !$profile['is_private'] || in_array($profile['relationship'] ?? 'none', ['following', 'friend'], true);
            $posts = $canView ? DemoData::postsByUser($profile['username']) : [];
            $list['posts'] = match ($tab) {
                'threads' => array_values(array_filter($posts, static fn (array $p) => $p['format'] === 'thread')),
                'media'   => array_values(array_filter($posts, static fn (array $p) => $p['media'] !== [])),
                'saved'   => array_values(array_filter(DemoData::posts(), static fn (array $p) => $p['viewer_saved'])),
                default   => $posts,
            };
        } else {
            $uid = (int) $viewer['id'];
            $canView = !$isBlocked && ($isOwn || !$profile['is_private'] || $profile['relation']['following']);
            $collaborator = $isBlocked ? null : CollaboratorService::profileOffer((int) $profile['id'], $uid);
            // En una cuenta privada, quien tiene una suscripción vigente ve las publicaciones para suscriptores.
            if (!$canView && !$isBlocked && ($collaborator['access_until'] ?? null) !== null && in_array($tab, ['posts', 'threads', 'media'], true)) {
                $canView = true;
            }
            if ($tab === 'lists') {
                $playlists = $canView ? Playlist::forUser((int) $profile['id']) : [];
            } elseif ($tab === 'music') {
                $canView = !$isBlocked;
                $page = max(1, (int) Request::query('page', '1'));
                $result = Song::library($uid, ['artist_id' => (int) $profile['id']], $page, (int) Config::get('app.limits.songs_page', 24));
                $songs = $result['songs'];
                $songsNext = $result['hasMore'] ? url('profile.php', ['u' => $profile['username'], 'tab' => 'music', 'page' => $page + 1]) : null;
            } elseif ($tab === 'saved' && $savedKind === 'stories') {
                $page = max(1, (int) Request::query('page', '1'));
                $result = Story::privateArchive($uid, $page, (int) Config::get('app.limits.people_page', 30));
                $privateStories = $result['group']['items'] ?? [];
                $privateStoriesNext = $result['hasMore'] ? url('profile.php', ['u' => $profile['username'], 'tab' => 'saved', 'cat' => 'private', 'kind' => 'stories', 'page' => $page + 1]) : null;
            } elseif ($canView && !in_array($tab, ['followers', 'following'], true)) {
                $paging = $this->paging();
                $kindFilter = Post::kindFilter($savedKind);
                $result = $tab === 'saved'
                    ? match ($savedCat) {
                        'liked'   => Post::liked($uid, $paging['page'], $paging['limit'], $kindFilter),
                        'private' => Post::privateOwn($uid, $paging, $kindFilter),
                        default   => Post::saved($uid, $paging['page'], $paging['limit'], $kindFilter),
                    }
                    : Post::feed($uid, [
                        'where'  => 'p.user_id = ?' . match ($tab) {
                            'threads' => " AND p.format = 'thread'",
                            'media'   => ' AND EXISTS (SELECT 1 FROM post_media pm WHERE pm.post_id = p.id)',
                            default   => '',
                        },
                        'params' => [(int) $profile['id']],
                    ] + $paging);
                $list = $this->listData($result, 'profile.php', ['u' => $profile['username'], 'tab' => $tab === 'posts' ? null : $tab]
                    + ($tab === 'saved' ? ['cat' => $savedCat, 'kind' => $savedKind === 'all' ? null : $savedKind] : []));
            }
        }

        if ($this->isPartial() && !in_array($tab, ['media', 'music', 'lists'], true)) {
            $this->renderList($list, 'No hay más publicaciones.');
        }

        $people = [];
        $peopleNext = null;
        if ($canView && in_array($tab, ['followers', 'following'], true)) {
            if ($preview) {
                $people = array_values(array_filter(DemoData::users(), static fn (array $u) => $u['username'] !== $profile['username']));
                $people = $tab === 'followers' ? array_slice($people, 0, 6) : array_slice(array_reverse($people), 0, 5);
            } else {
                $page = max(1, (int) Request::query('page', '1'));
                $result = Follow::connections($tab, (int) $profile['id'], (int) $viewer['id'], $page, (int) Config::get('app.limits.people_page', 30));
                $people = $result['users'];
                $peopleNext = $result['hasMore'] ? url('profile.php', ['u' => $profile['username'], 'tab' => $tab, 'page' => $page + 1]) : null;
            }
        }

        // Botón de mensaje: abre la conversación existente o una nueva, salvo que su privacidad lo impida.
        $message = ['url' => url('messages.php'), 'blocked' => null];
        if (!$preview && !$isOwn && !$isBlocked) {
            $conversationId = Conversation::findDirectId((int) $viewer['id'], (int) $profile['id']);
            $message = [
                'url'     => $conversationId !== null
                    ? url('messages.php', ['c' => $conversationId])
                    : url('messages.php', ['to' => $profile['username']]),
                'blocked' => Conversation::cannotMessage((int) $viewer['id'], $profile, $conversationId),
            ];
        }

        $this->render('pages/profile', [
            'title'     => $profile['display_name'] . ' (@' . $profile['username'] . ') · TREVIX',
            'activeNav' => $isOwn ? 'profile' : '',
            'profile'   => $profile,
            'isOwn'     => $isOwn,
            'isBlocked' => $isBlocked,
            'message'   => $message,
            'storyRing' => !$preview && !$isBlocked ? Story::ringFor((int) $profile['id'], (int) $viewer['id']) : null,
            'alertsOn'  => !$preview && !$isOwn && !$isBlocked && \Trevix\Models\ProfileAlert::isOn((int) $viewer['id'], (int) $profile['id']),
            'canView'   => $canView,
            'collaborator' => $collaborator ?? null,
            'peopleNext' => $peopleNext,
            'tab'       => $tab,
            'tabs'      => $tabs,
            'list'      => $list,
            'people'    => $people,
            'playlists' => $playlists,
            'songs'     => $songs,
            'songsNext' => $songsNext,
            'savedCat'  => $savedCat,
            'savedKind' => $savedKind,
            'privateStories' => $privateStories,
            'privateStoriesNext' => $privateStoriesNext,
            'aside'     => $this->asideData(),
        ]);
    }

    public function edit(): void
    {
        Authenticate::handle();
        $countries = ProfileService::countries();

        if (Request::isPost()) {
            VerifyCsrf::handle();
            $this->saveProfile($this->requireUser());
        }

        $this->render('pages/edit-profile', [
            'title'     => t('Editar perfil') . ' · TREVIX',
            'activeNav' => 'profile',
            'countries' => $countries,
            'errors'    => Session::pull('_errors', []),
            'old'       => Session::pull('_old', []),
            'canEdit'   => Auth::check(),
        ], 'layouts/app');
    }

    private function saveProfile(array $user): never
    {
        $data = [
            'display_name' => AccountRules::normalizeName(Request::text('display_name')),
            'username'     => mb_strtolower(Request::text('username')),
            'bio'          => str_replace("\r\n", "\n", Request::text('bio')),
            'website'      => AccountRules::normalizeWebsite(Request::text('website')),
            'country'      => strtoupper(Request::text('country')),
            'birth_date'   => Request::text('birth_date'),
            'is_private'   => Request::text('is_private') === '1' ? 1 : 0,
            'account_type' => Request::text('account_type'),
            'creator_category' => Request::text('creator_category'),
        ];

        try {
            $result = ProfileService::update($user, $data, Request::text('remove_avatar') === '1', Request::text('remove_cover') === '1');
        } catch (ActionError $e) {
            $this->backWithErrors(url('edit-profile.php'), $e->fields ?: ['display_name' => $e->getMessage()], $data);
        }

        $accepted = $result['accepted'];
        Session::flash('success', t('Tu perfil se actualizó.')
            . ($accepted > 0 ? ' ' . tn($accepted, 'Como ahora es pública, aprobamos la solicitud pendiente.', 'Como ahora es pública, aprobamos las {n} solicitudes pendientes.') : ''));
        Response::redirect(url('profile.php', ['u' => $result['data']['username']]));
    }
}