<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Models\Community;
use Trevix\Models\Follow;
use Trevix\Models\Hashtag;
use Trevix\Models\Post;
use Trevix\Models\User;

final class ExploreController extends Controller
{
    public const FILTERS = [
        'all'         => 'Todo',
        'featured'    => 'Destacados',
        'people'      => 'Personas',
        'posts'       => 'Publicaciones',
        'tags'        => 'Hashtags',
        'communities' => 'Comunidades',
    ];

    /** Personas que se muestran en la pestaña "Todo" (la pestaña "Personas" pagina). */
    private const PEOPLE_PREVIEW = 6;

    public function index(): void
    {
        Authenticate::handle();

        $query = trim(mb_substr(Request::query('q'), 0, 80));
        $tag = mb_substr(ltrim(Request::query('tag'), '#'), 0, 50);
        $filter = Request::queryIn('type', array_keys(self::FILTERS), 'all');
        $show = static fn (string $section) => $filter === 'all' || $filter === $section;

        // "#etiqueta" en el buscador lleva directo a las publicaciones de esa etiqueta.
        if ($tag === '' && preg_match('/^#([\p{L}\p{N}_]{1,50})$/u', $query, $m)) {
            Response::redirect(url('explore.php', ['tag' => $m[1]]));
        }

        $people = $trends = $communities = $media = [];
        $tagList = $postList = $featuredList = ['posts' => [], 'nextUrl' => null];
        $peopleNext = null;

        if ($this->isPreview()) {
            $needle = mb_strtolower($tag !== '' ? $tag : $query);
            $matches = static fn (string ...$fields) => $needle === ''
                || array_filter($fields, static fn (string $f) => str_contains(mb_strtolower($f), $needle));

            $people = array_values(array_filter(
                DemoData::users(),
                static fn (array $u) => $u['username'] !== 'valentina.rios' && $matches($u['username'], $u['display_name'], $u['bio'])
            ));
            $trends = array_values(array_filter(DemoData::trends(), static fn (array $t) => $matches($t['tag'], $t['category'])));
            $communities = array_values(array_filter(
                DemoData::communities(),
                static fn (array $c) => $matches($c['name'], $c['description'], $c['category'])
            ));
            foreach (DemoData::posts() as $post) {
                if ($needle !== '' && $show('posts') && $matches($post['body'])) {
                    $postList['posts'][] = $post;
                }
                if ($post['media'] && $matches($post['body'], $post['user']['display_name'])) {
                    $media[] = $post;
                }
            }
        } else {
            $uid = (int) $this->viewer()['id'];
            $page = max(1, (int) Request::query('page', '1'));
            $peopleLimit = $filter === 'people' ? (int) Config::get('app.limits.people_page', 30) : self::PEOPLE_PREVIEW;

            if ($filter === 'featured') {
                $limit = (int) Config::get('app.limits.feed_page', 15);
                $featuredList = $this->listData(Post::featured($uid, $page, $limit), 'explore.php', ['type' => 'featured']);
                if ($this->isPartial()) {
                    $this->renderList($featuredList, 'Ya viste todas las publicaciones destacadas.');
                }
            } elseif ($tag !== '') {
                $result = Post::feed($uid, [
                    'join'       => 'JOIN post_hashtags ph ON ph.post_id = p.id JOIN hashtags h ON h.id = ph.hashtag_id AND h.tag = ?',
                    'joinParams' => [$tag],
                ] + $this->paging());
                $tagList = $this->listData($result, 'explore.php', ['tag' => $tag]);
                if ($this->isPartial()) {
                    $this->renderList($tagList, t('No hay más publicaciones con #{tag}.', ['tag' => $tag]));
                }
            } elseif ($query !== '') {
                if ($show('posts')) {
                    $postList = $this->listData(Post::search($uid, $query, $this->paging()), 'explore.php', ['q' => $query, 'type' => 'posts']);
                    if ($this->isPartial()) {
                        $this->renderList($postList, 'No hay más publicaciones que coincidan.');
                    }
                }
                if ($show('people')) {
                    $found = User::search($uid, $query, $filter === 'people' ? $page : 1, $peopleLimit);
                    $people = $found['users'];
                    if ($found['hasMore']) {
                        $peopleNext = url('explore.php', $filter === 'people'
                            ? ['q' => $query, 'type' => 'people', 'page' => $page + 1]
                            : ['q' => $query, 'type' => 'people']);
                    }
                }
                if ($show('tags')) {
                    $trends = Hashtag::search(ltrim($query, '#'));
                }
                if ($show('communities')) {
                    $communities = Community::discover($uid, $query, null, 1, $filter === 'communities' ? 24 : 4)['communities'];
                }
            } else {
                if ($show('communities')) {
                    $communities = Community::discover($uid, '', null, 1, $filter === 'communities' ? 24 : 4)['communities'];
                }
                if ($show('people')) {
                    $people = Follow::suggestions($uid, $peopleLimit);
                }
                if ($show('tags')) {
                    $trends = Hashtag::trending(10);
                }
                if ($filter === 'all') {
                    $media = Post::recentMedia($uid, 12);
                    $featuredList = ['posts' => Post::featured($uid, 1, 3)['posts'], 'nextUrl' => null];
                }
            }
        }

        $this->render('pages/explore', [
            'title'       => ($tag !== '' ? '#' . $tag . ' · ' : '') . t('Explorar') . ' · TREVIX',
            'activeNav'   => 'explore',
            'query'       => $query,
            'tag'         => $tag,
            'filter'      => $filter,
            'filters'     => self::FILTERS,
            'people'      => $people,
            'peopleNext'  => $peopleNext,
            'trends'      => $trends,
            'communities' => $communities,
            'media'       => $media,
            'postList'    => $postList,
            'featuredList' => $featuredList,
            'tagList'     => $tagList,
            'tagInfo'     => !$this->isPreview() && $tag !== '' ? Hashtag::find($tag) : null,
            'isPreview'   => $this->isPreview(),
        ], 'layouts/app');
    }
}
