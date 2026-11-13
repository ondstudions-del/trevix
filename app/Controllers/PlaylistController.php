<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Core\Session;
use Trevix\Middleware\VerifyCsrf;
use Trevix\Models\Block;
use Trevix\Models\Playlist;
use Trevix\Models\Post;
use Trevix\Models\User;
use Trevix\Services\PlaylistService;

/** playlist.php (ver una lista o elegir listas para un video) y api/playlists.php (crear, editar, agregar y quitar). */
final class PlaylistController extends Controller
{
    /** playlist.php?id= — la lista con sus videos en orden · playlist.php?add=POST — elegir listas para un video propio. */
    public function index(): void
    {
        $user = $this->requireUser();
        if (Request::isPost()) {
            header('Allow: GET');
            Response::abort(405, 'Las listas se modifican en api/playlists.php.');
        }
        $uid = (int) $user['id'];

        $addId = (int) Request::query('add');
        if ($addId > 0) {
            $post = Post::findVisible($addId, $uid);
            if ($post === null || (int) $post['user']['id'] !== $uid) {
                Response::abort(404, 'Esta publicación no existe o ya no está disponible.');
            }
            $this->render('pages/playlist-add', [
                'title'     => t('Agregar a una lista') . ' · TREVIX',
                'activeNav' => 'profile',
                'post'      => $post,
                'playlists' => Playlist::forUser($uid, $addId),
                'isCreator' => User::isCreator($user),
                'aside'     => $this->asideData(),
            ]);
            return;
        }

        $id = (int) Request::query('id');
        $playlist = $id > 0 ? Playlist::find($id) : null;
        if ($playlist === null || ($playlist['user_id'] !== $uid
            && (Block::exists($playlist['user_id'], $uid) || Block::exists($uid, $playlist['user_id'])))) {
            Response::abort(404, 'Esta lista de reproducción no existe.');
        }
        $page = max(1, (int) Request::query('page', '1'));
        $result = Playlist::posts($id, $uid, $page, (int) Config::get('app.limits.feed_page', 15));
        $list = $this->listData($result, 'playlist.php', ['id' => $id]);
        if ($this->isPartial()) {
            $this->renderList($list, 'Ya viste todos los videos de la lista.');
        }
        $this->render('pages/playlist', [
            'title'     => $playlist['title'] . ' · @' . $playlist['user']['username'] . ' · TREVIX',
            'activeNav' => $playlist['user_id'] === $uid ? 'profile' : '',
            'playlist'  => $playlist,
            'list'      => $list,
            'isOwn'     => $playlist['user_id'] === $uid,
            'aside'     => $this->asideData(),
        ]);
    }

    /** api/playlists.php POST action = create | update | delete | add | remove. */
    public function api(): void
    {
        $this->onlyPost();
        VerifyCsrf::handle();
        $user = $this->requireUser();
        $action = Request::text('action');
        $id = (int) Request::text('playlist_id');
        $postId = (int) Request::text('post_id');
        $profile = url('profile.php', ['u' => $user['username'], 'tab' => 'lists']);
        $back = $id > 0 ? url('playlist.php', ['id' => $id]) : $profile;
        $returnTo = Request::text('return') === 'add' && $postId > 0 ? url('playlist.php', ['add' => $postId]) : null;

        $message = $this->attempt(static function () use ($action, $user, $id, $postId, &$back): string {
            switch ($action) {
                case 'create':
                    $newId = PlaylistService::create($user, Request::text('title'), Request::text('description', false));
                    $back = url('playlist.php', ['id' => $newId]);
                    if ($postId > 0) {
                        PlaylistService::addPost($user, $newId, $postId);
                        return 'Creamos la lista y agregamos el video.';
                    }
                    return 'Creamos la lista de reproducción.';
                case 'update':
                    PlaylistService::update($user, $id, Request::text('title'), Request::text('description', false));
                    return 'Guardamos los cambios de la lista.';
                case 'delete':
                    PlaylistService::delete($user, $id);
                    return 'Eliminamos la lista. Los videos siguen publicados.';
                case 'add':
                    return PlaylistService::addPost($user, $id, $postId) ? 'Agregamos el video a la lista.' : 'El video ya estaba en la lista.';
                case 'remove':
                    PlaylistService::removePost($user, $id, $postId);
                    return 'Quitamos el video de la lista.';
                default:
                    throw new \Trevix\Core\ActionError('Acción no válida.', 400);
            }
        }, $returnTo ?? $back);

        if (Request::wantsJson()) {
            Response::json(['ok' => true, 'message' => t($message)]);
        }
        Session::flash('success', $message);
        Response::redirect($returnTo ?? ($action === 'delete' ? $profile : $back));
    }
}
