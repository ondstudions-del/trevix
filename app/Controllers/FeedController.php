<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Core\Request;
use Trevix\Core\Response;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Models\Post;
use Trevix\Models\Story;
use Trevix\Services\AdService;

final class FeedController extends Controller
{
    public const FEEDS = [
        'foryou'    => 'Para ti',
        'following' => 'Siguiendo',
        'friends'   => 'Amigos',
        'trending'  => 'Tendencias',
    ];

    private const END_TEXT = 'Ya viste todas las publicaciones de esta pestaña.';

    public function index(): void
    {
        Authenticate::handle();

        $feed = Request::queryIn('feed', array_keys(self::FEEDS), 'foryou');
        $preview = $this->isPreview();

        // ?newer=ID: cuántas publicaciones nuevas hay arriba (aviso «nuevas publicaciones» de feed-refresh.js).
        $newer = (int) Request::query('newer');
        if ($newer > 0) {
            $uid = (int) Auth::id();
            Response::json(['ok' => true, 'count' => $uid > 0 && $feed !== 'trending' ? Post::countNewer($uid, self::query($feed, $uid), $newer) : 0]);
        }

        if ($preview) {
            $list = [
                'posts'   => array_values(array_filter(DemoData::posts(), static fn (array $p) => in_array($feed, $p['feeds'], true))),
                'nextUrl' => null,
            ];
        } else {
            $uid = (int) $this->viewer()['id'];
            $result = self::page($feed, $uid, $this->paging(), Request::query('more') === '1');
            $list = $this->listData($result, 'feed.php', ['feed' => $feed === 'foryou' ? null : $feed]) + [
                'suggested' => $result['suggested'],
                'ad'        => $result['posts'] !== [] ? AdService::deliver($uid) : null,
            ];
        }

        if ($this->isPartial()) {
            $this->renderList($list, self::END_TEXT);
        }

        $this->render('pages/feed', [
            'title'     => t('Inicio') . ' · TREVIX',
            'activeNav' => 'home',
            'feed'      => $feed,
            'feeds'     => self::FEEDS,
            'list'      => $list,
            'endText'   => t(self::END_TEXT),
            'stories'   => $preview ? DemoData::stories() : Story::tray((int) $this->viewer()['id']),
            'aside'     => $this->asideData(),
        ]);
    }

    /** Filtro de Post::feed de cada pestaña del inicio (también lo usa la API). */
    public static function query(string $feed, int $uid): array
    {
        return match ($feed) {
            // Siguiendo: cuentas que sigues y comunidades de las que eres miembro.
            'following' => [
                'where'  => "p.user_id = ? OR EXISTS (SELECT 1 FROM follows fw WHERE fw.follower_id = ? AND fw.following_id = p.user_id)
                             OR EXISTS (SELECT 1 FROM community_members fcm
                                 WHERE fcm.community_id = p.community_id AND fcm.user_id = ? AND fcm.status = 'active')",
                'params' => [$uid, $uid, $uid],
            ],
            // Amigos: seguimiento mutuo.
            'friends'   => [
                'where'  => 'EXISTS (SELECT 1 FROM follows fa WHERE fa.follower_id = ? AND fa.following_id = p.user_id)
                             AND EXISTS (SELECT 1 FROM follows fb WHERE fb.follower_id = p.user_id AND fb.following_id = ?)',
                'params' => [$uid, $uid],
            ],
            'trending'  => [
                'where' => "p.visibility = 'public' AND (p.community_id IS NULL OR c.visibility = 'public')
                            AND p.created_at > (NOW() - INTERVAL 7 DAY)
                            AND (p.likes_count + p.comments_count + p.shares_count + p.saves_count) > 0",
                'order' => 'score',
            ],
            // Para ti: todo lo visible (publicaciones e hilos), del más reciente al más antiguo.
            default     => [],
        };
    }

    /**
     * Una página del inicio (web y API). Cuando se terminan las publicaciones de la pestaña, el feed sigue con
     * «Sugerencias para ti» (more=1): todo lo demás que la persona puede ver, del más reciente al más antiguo.
     * «Para ti» ya incluye todo, así que al terminarse no continúa.
     *
     * @return array{posts: list<array>, next: ?array, suggested: bool} suggested = primera página de sugerencias
     */
    public static function page(string $feed, int $uid, array $paging, bool $more): array
    {
        if ($more && $feed !== 'foryou') {
            $base = self::query($feed, $uid);
            $result = Post::feed($uid, ['where' => 'NOT (' . $base['where'] . ')', 'params' => $base['params'] ?? []] + $paging);
            return [
                'posts'     => $result['posts'],
                'next'      => $result['next'] !== null ? $result['next'] + ['more' => 1] : null,
                'suggested' => (int) ($paging['before'] ?? 0) === 0,
            ];
        }
        $result = self::withFeatured(Post::feed($uid, self::query($feed, $uid) + $paging), $feed, $uid, $paging);
        return [
            'posts'     => $result['posts'],
            'next'      => $result['next'] ?? ($feed !== 'foryou' ? ['more' => 1] : null),
            'suggested' => false,
        ];
    }

    /** Primera página de «Para ti»: las destacadas por la administración van arriba, sin repetirse en esa página. */
    public static function withFeatured(array $result, string $feed, int $uid, array $paging): array
    {
        if ($feed !== 'foryou' || (int) ($paging['before'] ?? 0) > 0 || (int) ($paging['page'] ?? 1) > 1) {
            return $result;
        }
        $featured = Post::featured($uid, 1, (int) Config::get('app.limits.featured_on_feed', 3))['posts'];
        if ($featured === []) {
            return $result;
        }
        $ids = array_column($featured, 'id');
        $rest = array_filter($result['posts'], static fn (array $p): bool => !in_array($p['id'], $ids, true));
        $result['posts'] = array_merge($featured, array_values($rest));
        return $result;
    }
}
