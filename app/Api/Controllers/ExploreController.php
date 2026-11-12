<?php
declare(strict_types=1);

namespace Trevix\Api\Controllers;

use Trevix\Api\Present;
use Trevix\Api\Reply;
use Trevix\Core\Request;
use Trevix\Models\Community;
use Trevix\Models\Follow;
use Trevix\Models\Group;
use Trevix\Models\Hashtag;
use Trevix\Models\People;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Services\Guard;
use Trevix\Services\Mentions;

/** Búsqueda, Explorar, hashtags y sugerencias de personas. */
final class ExploreController extends ApiController
{
    private const TYPES = ['people', 'posts', 'tags', 'communities', 'groups'];

    /**
     * GET /search?q=&type=people|posts|tags|communities|groups&page=|before=
     * Cada tipo pagina por separado; las publicaciones usan ?before= como el feed. Los grupos (públicos) no paginan.
     */
    public function search(): never
    {
        $uid = $this->uid();
        $query = trim(mb_substr(Request::query('q'), 0, 80));
        $type = Request::queryIn('type', self::TYPES, 'people');
        if ($query === '') {
            Reply::ok([], ['next' => null]);
        }
        switch ($type) {
            case 'posts':
                $result = Post::search($uid, $query, $this->paging());
                Reply::ok(Present::posts($result['posts']), ['next' => $result['next']]);
            case 'tags':
                Reply::ok(array_map([self::class, 'tag'], Hashtag::search(ltrim($query, '#'))), ['next' => null]);
            case 'groups':
                Reply::ok(array_map([Present::class, 'publicGroup'], Group::searchPublic($query, $uid, 30)), ['next' => null]);
            case 'communities':
                $result = Community::discover($uid, $query, null, $this->pageNumber(), $this->limit('communities_page', 24));
                Reply::ok(array_map([Present::class, 'community'], $result['communities']), $this->nextPage($result['hasMore']));
            default:
                $result = User::search($uid, $query, $this->pageNumber(), $this->limit('people_page', 30));
                Reply::ok(array_map([self::class, 'suggestion'], $result['users']), $this->nextPage($result['hasMore']));
        }
    }

    /** GET /explore — portada de Explorar: sugerencias, tendencias, comunidades y publicaciones con imágenes. */
    public function index(): never
    {
        $uid = $this->uid();
        Reply::ok([
            'people'      => array_map([self::class, 'suggestion'], Follow::suggestions($uid, 6)),
            'hashtags'    => array_map([self::class, 'tag'], Hashtag::trending(10)),
            'communities' => array_map([Present::class, 'community'], Community::discover($uid, '', null, 1, 4)['communities']),
            'media'       => Present::posts(Post::recentMedia($uid, 12)),
            'featured'    => Present::posts(Post::featured($uid, 1, 3)['posts']),
        ]);
    }

    /** GET /hashtags/trending */
    public function trending(): never
    {
        Reply::ok(array_map([self::class, 'tag'], Hashtag::trending(min(30, max(1, (int) Request::query('limit', '10'))))));
    }

    /** GET /hashtags/{tag}?before= — publicaciones con la etiqueta. */
    public function hashtag(string $tag): never
    {
        $tag = mb_substr(ltrim($tag, '#'), 0, 50);
        $info = $tag !== '' ? Hashtag::find($tag) : null;
        $result = $info !== null
            ? Post::feed($this->uid(), [
                'join'       => 'JOIN post_hashtags ph ON ph.post_id = p.id JOIN hashtags h ON h.id = ph.hashtag_id AND h.tag = ?',
                'joinParams' => [$tag],
            ] + $this->paging())
            : ['posts' => [], 'next' => null];
        Reply::ok(Present::posts($result['posts']), [
            'next'    => $result['next'],
            'hashtag' => ['tag' => $info['tag'] ?? $tag, 'posts_count' => (int) ($info['posts_count'] ?? 0)],
        ]);
    }

    /**
     * GET /suggestions/users?limit=&page= — personas cercanas que aún no sigues (te siguen, amigos en común,
     * misma ciudad, interacciones e intereses), con el motivo de cada una.
     */
    public function suggestions(): never
    {
        $limit = min(30, max(1, (int) Request::query('limit', '10')));
        $result = People::suggestions($this->uid(), $limit, $this->pageNumber());
        Reply::ok(array_map([self::class, 'suggestion'], $result['users']), $this->nextPage($result['hasMore']));
    }

    /**
     * GET /mentions?q= — personas para completar una @mención. Sin q: amistades, cuentas que sigues y seguidores;
     * con q, esas primero y luego el resto de TREVIX. relation: friend | following | follower | null.
     */
    public function mentions(): never
    {
        $uid = $this->uid();
        Guard::rateLimit('mention_search', 'user:' . $uid, 'Vas demasiado rápido. Espera {min} min.');
        RateLimit::hit('mention_search', 'user:' . $uid);
        Reply::ok(array_map(static fn (array $u): array => [
            'id'             => $u['id'],
            'username'       => $u['username'],
            'display_name'   => $u['display_name'],
            'avatar_url'     => Present::file($u['avatar_path']),
            'is_verified'    => $u['is_verified'],
            'relation'       => $u['relation'],
            'relation_label' => Mentions::relationLabel($u['relation']),
        ], Mentions::suggest($uid, Request::query('q'), 10)));
    }

    /** POST /suggestions/users/{id}/dismiss — «No me interesa»: no vuelve a sugerirse en 90 días. */
    public function dismiss(string $id): never
    {
        $target = User::findForRelation((int) $id);
        if ($target === null || (int) $target['id'] === $this->uid()) {
            $this->notFound('No encontramos esa cuenta.');
        }
        People::dismiss($this->uid(), (int) $target['id']);
        Reply::ok(['message' => t('No volveremos a sugerirte a {name}.', ['name' => $target['display_name']])]);
    }

    private static function tag(array $t): array
    {
        return ['tag' => (string) $t['tag'], 'category' => $t['category'] ?? null, 'posts_count' => (int) ($t['posts_count'] ?? 0)];
    }

    private static function suggestion(array $u): array
    {
        return Present::user($u) + ['reason' => $u['reason'] ?? null];
    }
}
