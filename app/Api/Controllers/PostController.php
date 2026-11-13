<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Input;
use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Controllers\FeedController;
use Trevix\Core\ActionError;
use Trevix\Core\Lang;
use Trevix\Core\Request;
use Trevix\Models\Comment;
use Trevix\Models\Post;
use Trevix\Services\AdService;
use Trevix\Services\CommentService;
use Trevix\Services\MediaUpload;
use Trevix\Services\PostService;
use Trevix\Services\TasteService;
use Trevix\Services\Translator;

/** Feeds, publicaciones, me gusta, guardados y comentarios. */
final class PostController extends ApiController
{
    /**
     * GET /feed?tab=foryou|following|friends|trending&before=|page=&more=&seed=
     * «Para ti» se ordena por intereses (hashtags de lo que la persona mira, comenta, guarda o comparte) y pagina
     * con page + seed (los dos vienen en next).
     * Al terminarse la pestaña, next lleva more=1 y el feed sigue con sugerencias (meta.suggested en su primera
     * página). meta.sponsored = {position, ad}: anuncio de OND-ADS para mostrar tras esa cantidad de publicaciones.
     */
    public function feed(): never
    {
        $uid = $this->uid();
        $tab = Request::queryIn('tab', array_keys(FeedController::FEEDS), 'foryou');
        $result = FeedController::page($tab, $uid, $this->paging(), Request::query('more') === '1', max(0, (int) Request::query('seed')));
        $ad = $result['posts'] !== [] ? AdService::deliver($uid) : null;
        Reply::ok(Present::posts($result['posts']), [
            'next'      => $result['next'],
            'suggested' => $result['suggested'],
            'sponsored' => $ad !== null ? ['position' => min(3, count($result['posts'])), 'ad' => Present::ad($ad)] : null,
        ]);
    }

    /** GET /feed/newer?tab=&after=ID — cuántas publicaciones nuevas hay sobre la más reciente que se ve (hasta 99). */
    public function newer(): never
    {
        $uid = $this->uid();
        $tab = Request::queryIn('tab', array_keys(FeedController::FEEDS), 'foryou');
        $after = max(0, (int) Request::query('after'));
        Reply::ok(['count' => $after > 0 && $tab !== 'trending' ? Post::countNewer($uid, FeedController::query($tab, $uid), $after) : 0]);
    }

    /**
     * GET /reels?seed=&page=&start= — publicaciones con video a pantalla completa. «start» (opcional) es el video
     * que se tocó para abrir Reels: va primero en la página 1 y no se repite después.
     */
    public function reels(): never
    {
        $uid = $this->uid();
        $page = $this->pageNumber();
        $limit = $this->limit('reels_page', 8);
        $seed = max(0, (int) Request::query('seed', '0'));
        $startId = max(0, (int) Request::query('start', '0'));

        $result = Post::reels($uid, $seed, $page, $limit, $startId);
        $posts = $result['posts'];
        if ($page === 1) {
            TasteService::refreshLater($uid);
        }
        if ($page === 1 && $startId > 0) {
            $start = Post::findVisible($startId, $uid);
            $hasVideo = $start !== null && array_filter($start['media'], static fn (array $m) => $m['type'] === 'video') !== [];
            if ($hasVideo) {
                array_unshift($posts, $start);
            }
        }
        Reply::ok(Present::posts($posts), ['next' => $result['next'] !== null ? $result['next'] + ['seed' => $seed, 'start' => $startId] : null]);
    }

    /** GET /posts/featured?page= — destacadas por la administración (sección Destacados de Explorar). */
    public function featured(): never
    {
        $result = Post::featured($this->uid(), $this->pageNumber(), $this->limit('feed_page', 15));
        Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
    }

    /**
     * POST /posts — JSON o multipart con archivos en «media[]».
     * {body?, format?: post|thread, visibility?: public|followers|private, community_id?, shared_post_id?,
     *  song_id?, song_start?, filter?, song_sync?: 1 (un solo video grabado sobre la canción, sin sonido propio),
     *  is_adult?: 1 (contenido para adultos, oculto a menores), poll_options?: [2 a 4 respuestas], poll_days?: 1|3|7}
     */
    public function create(): never
    {
        $this->rejectOversized();
        $user = $this->user();
        $result = PostService::create($user, [
            'format'         => Input::str('format'),
            'visibility'     => Input::str('visibility'),
            'community_id'   => Input::int('community_id'),
            'shared_post_id' => Input::int('shared_post_id'),
            'body'           => Input::str('body', false),
            'song_id'        => Input::int('song_id'),
            'song_start'     => Input::int('song_start'),
            'background'     => Input::str('background'),
            'life_event'     => Input::str('life_event'),
            'location_name'  => Input::str('location_name'),
            'location_lat'   => Input::str('location_lat'),
            'location_lng'   => Input::str('location_lng'),
            'gif_id'         => Input::str('gif_id'),
            'gif_kind'       => Input::str('gif_kind'),
            'event'          => Input::map('event'),
            'filter'         => Input::str('filter'),
            'song_sync'      => Input::str('song_sync'),
            'is_adult'       => Input::bool('is_adult') ? '1' : '',
            'poll_options'   => Input::raw('poll_options'),
            'poll_days'      => Input::int('poll_days', 1),
        ], MediaUpload::collect('media'));
        $post = Post::findVisible($result['id'], (int) $user['id']);
        $this->created($post !== null ? Present::post($post) : ['id' => $result['id']]);
    }

    /** GET /posts/{id} */
    public function show(string $id): never
    {
        $post = $this->visible((int) $id);
        Post::recordViews([(int) $post['id']], $this->uid());
        Reply::ok(Present::post($post));
    }

    /** POST /posts/{id}/translation {lang?} — traducción con IA al idioma pedido (por defecto, el de Accept-Language). */
    public function translate(string $id): never
    {
        $lang = Input::has('lang') ? Input::str('lang') : Lang::locale();
        Reply::ok(Translator::post($this->uid(), (int) $id, $lang));
    }

    /** PATCH /posts/{id} {body?, visibility?, song_id?, song_start?} — solo la propia publicación; song_id 0 quita la canción. */
    public function update(string $id): never
    {
        $uid = $this->uid();
        $post = PostService::findOwnEditable((int) $id, $uid);
        $song = null;
        if (Input::has('song_id')) {
            $song = ['id' => Input::int('song_id'), 'start' => Input::has('song_start') ? Input::int('song_start') : (int) ($post['song']['start'] ?? 0)];
        } elseif (Input::has('song_start') && $post['song'] !== null) {
            $song = ['id' => (int) $post['song']['id'], 'start' => Input::int('song_start')];
        }
        PostService::update(
            $post,
            Input::has('body') ? Input::str('body', false) : $post['body'],
            Input::has('visibility') ? Input::str('visibility') : $post['visibility'],
            $song
        );
        Reply::ok(Present::post(Post::findVisible((int) $id, $uid) ?? $post));
    }

    /** DELETE /posts/{id} */
    public function destroy(string $id): never
    {
        PostService::delete($this->uid(), (int) $id);
        Reply::ok(['message' => 'Eliminaste la publicación.']);
    }

    /** POST|DELETE /posts/{id}/like · /posts/{id}/save */
    public function interact(string $id, string $kind): never
    {
        $result = PostService::interact($kind, $this->uid(), (int) $id, Request::method() !== 'DELETE');
        Reply::ok([$kind === 'like' ? 'liked' : 'saved' => $result['active'], 'count' => $result['count']]);
    }

    /**
     * POST /posts/{id}/view {seconds} — tiempo que la publicación estuvo en pantalla · POST /posts/{id}/share — se
     * compartió fuera de TREVIX. Alimentan los intereses de «Para ti».
     */
    public function signal(string $id, string $kind): never
    {
        PostService::signal($this->uid(), (int) $id, $kind, Input::int('seconds'));
        Reply::ok(['recorded' => true]);
    }

    /** GET /posts/{id}/comments?page= */
    public function comments(string $id): never
    {
        $post = $this->visible((int) $id);
        $page = $this->pageNumber();
        $result = Comment::forPost((int) $id, $this->uid(), $page, $this->limit('comments_page', 30));
        $ownerId = (int) $post['user']['id'];
        Reply::ok(
            array_map(static fn (array $c) => Present::comment($c, $ownerId), $result['comments']),
            $this->nextPage($result['hasMore'])
        );
    }

    /** POST /posts/{id}/comments {body?, parent_id?, gif_id?, gif_kind?: gif|sticker} — texto, GIF o ambos. */
    public function comment(string $id): never
    {
        $user = $this->user();
        $result = CommentService::create(
            $user,
            (int) $id,
            Input::str('body', false),
            Input::int('parent_id'),
            Input::str('gif_id'),
            Input::str('gif_kind')
        );
        $this->created(Present::comment([
            'id'         => $result['id'],
            'post_id'    => $result['post_id'],
            'user_id'    => (int) $user['id'],
            'parent_id'  => $result['parent_id'],
            'body'       => $result['body'],
            'gif'        => $result['gif'],
            'created_at' => date('Y-m-d H:i:s'),
            'user'       => $user,
        ], $result['post_owner_id']));
    }

    /**
     * POST|DELETE /posts/{id}/not-interested — «No me importa»: la publicación sale del feed y de los reels y se
     * muestra menos de ese tipo de contenido; DELETE lo deshace.
     */
    public function notInterested(string $id): never
    {
        $active = PostService::notInterested($this->uid(), (int) $id, Request::method() !== 'DELETE');
        Reply::ok(['not_interested' => $active]);
    }

    /** POST /posts/{id}/poll {option_id} — voto en la encuesta (uno por persona); devuelve la encuesta con resultados. */
    public function vote(string $id): never
    {
        Reply::ok(Present::poll(PostService::votePoll($this->uid(), (int) $id, Input::int('option_id'))));
    }

    /** POST /comments/{id}/reaction {value: like|dislike|none} — me gusta o no me gusta en un comentario. */
    public function react(string $id): never
    {
        $value = Input::in('value', ['like', 'dislike', 'none'], 'none', 'Elige like, dislike o none.');
        $result = CommentService::react($this->uid(), (int) $id, $value === 'none' ? null : $value);
        Reply::ok(['reaction' => $result['reaction'], 'likes_count' => $result['likes'], 'dislikes_count' => $result['dislikes']]);
    }

    /** DELETE /comments/{id} — el autor del comentario o el de la publicación. */
    public function deleteComment(string $id): never
    {
        $postId = CommentService::delete($this->uid(), (int) $id);
        Reply::ok(['message' => 'Comentario eliminado.', 'post_id' => $postId]);
    }

    private function visible(int $id): array
    {
        $post = $id > 0 ? Post::findVisible($id, $this->uid()) : null;
        if ($post === null) {
            $this->notFound('Esta publicación no existe o ya no está disponible.');
        }
        return $post;
    }

    /** Si el cuerpo supera post_max_size, PHP descarta los datos y los archivos. */
    private function rejectOversized(): void
    {
        $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($length > 0 && $_POST === [] && $_FILES === [] && !str_contains(strtolower((string) ($_SERVER['CONTENT_TYPE'] ?? '')), 'json')) {
            throw new ActionError('Los archivos superan el tamaño total que acepta el servidor.', 413);
        }
    }
}
