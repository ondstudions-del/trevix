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
use Trevix\Services\InterestService;
use Trevix\Services\TasteService;

final class FeedController extends Controller
{
    public const FEEDS = [
        'foryou'    => 'Para ti',
        'following' => 'Siguiendo',
        'friends'   => 'Amigos',
        'trending'  => 'Tendencias',
    ];

    private const END_TEXT = 'Ya viste todas las publicaciones de esta pestaña.';

    /** Días que abarca el orden por intereses de «Para ti»; lo anterior sigue después, del más reciente al más antiguo. */
    private const FOR_YOU_DAYS = 120;

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
            $result = self::page(
                $feed,
                $uid,
                $this->paging(),
                Request::query('more') === '1',
                max(0, (int) Request::query('seed')),
                Request::query('refresh') === '1',
            );
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
            // Para ti: lo visible de los últimos FOR_YOU_DAYS días, ordenado por intereses (forYouOrder).
            default     => [
                'where'  => 'p.created_at > (NOW() - INTERVAL ' . self::FOR_YOU_DAYS . ' DAY)',
            ],
        };
    }

    /** Horas en las que lo que publica la persona va primero en su «Para ti». */
    private const OWN_FIRST_HOURS = 6;
    /** Horas en las que una publicación de sus intereses cuenta como nueva y va antes que el resto. */
    private const FRESH_HOURS = 48;

    /**
     * Orden de «Para ti»: lo propio reciente, lo fresco de intereses (# / temas / IA) y el resto.
     * Dentro de cada tramo: afinidad, engagement, frescura, cuentas que sigue, amigos de amigos (FoF),
     * cercanía por ciudad pública y una variación estable por semilla ($seed).
     */
    private static function forYouOrder(int $uid, int $seed): string
    {
        $affinity = InterestService::affinitySql($uid);
        $follows = "EXISTS (SELECT 1 FROM follows ff WHERE ff.follower_id = $uid AND ff.following_id = p.user_id)";
        // Amigos de amigos: alguien que sigues también sigue al autor (y tú aún no lo sigues).
        $fof = "EXISTS (
                    SELECT 1 FROM follows f1
                    JOIN follows f2 ON f2.follower_id = f1.following_id AND f2.following_id = p.user_id
                    WHERE f1.follower_id = $uid
                      AND NOT EXISTS (SELECT 1 FROM follows fx WHERE fx.follower_id = $uid AND fx.following_id = p.user_id)
                )";
        // Misma ciudad pública (no revela ciudades privadas).
        $near = "EXISTS (
                    SELECT 1 FROM user_profiles me
                    JOIN user_profiles them ON them.user_id = p.user_id
                        AND them.city_key = me.city_key
                        AND them.details_audience = 'everyone'
                    WHERE me.user_id = $uid AND me.city_key IS NOT NULL AND me.city_key <> ''
                )";
        $views = '(SELECT COUNT(*) FROM post_views pv WHERE pv.post_id = p.id)';
        $engage = "(p.likes_count + p.comments_count + p.shares_count + $views)";
        // Impulso a lo poco visto (pocos likes / pocas visualizaciones).
        $discovery = "(1 + 16 / POW(GREATEST($engage, 0) + 5, 0.62))";
        // Variación fuerte por semilla (cada refresco reordena distinto).
        $random = '(0.25 + CRC32(CONCAT(p.id, \':\', ' . $seed . ')) / 4294967295 * 2.35)';
        return "(p.user_id <> $uid AND p.created_at > NOW() - INTERVAL " . self::FRESH_HOURS . " HOUR AND $affinity > 0) DESC,
                (" . InterestService::factorSql($uid) . "
                * $discovery
                * (1 + LEAST(LN(p.likes_count * 2 + p.comments_count * 3 + p.shares_count * 4 + p.saves_count + 1), 3.2) / 4)
                * (1 + 1.2 * $follows)
                * (1 + 0.9 * $fof)
                * (1 + 0.45 * $near)
                / POW(TIMESTAMPDIFF(HOUR, p.created_at, NOW()) + 4, 0.72)
                * $random) DESC, p.id DESC";
    }

    /**
     * Una página del inicio (web y API). Cuando se terminan las publicaciones de la pestaña, el feed sigue con
     * «Sugerencias para ti» (more=1): todo lo demás que la persona puede ver, del más reciente al más antiguo.
     * En «Para ti» lo que sigue son las publicaciones más antiguas, sin el título de sugerencias.
     * «Para ti» pagina por página con una semilla ($seed; 0 = nueva) que viaja en next.
     *
     * @return array{posts: list<array>, next: ?array, suggested: bool} suggested = primera página de sugerencias
     */
    public static function page(string $feed, int $uid, array $paging, bool $more, int $seed = 0, bool $refresh = false): array
    {
        if ($more) {
            $base = self::query($feed, $uid);
            $rest = self::withoutNotInterested(['where' => 'NOT (' . $base['where'] . ')', 'params' => $base['params'] ?? []], $uid);
            $result = Post::feed($uid, $rest + $paging);
            return [
                'posts'     => $result['posts'],
                'next'      => $result['next'] !== null ? $result['next'] + ['more' => 1] : null,
                'suggested' => $feed !== 'foryou' && (int) ($paging['before'] ?? 0) === 0,
            ];
        }
        $query = self::withoutNotInterested(self::query($feed, $uid), $uid);
        if ($feed === 'foryou') {
            if ($refresh) {
                $seed = random_int(1, 999999);
            } else {
                $seed = $seed > 0 ? $seed % 1000000 : random_int(1, 999999);
            }
            $query += ['order' => 'custom', 'orderBy' => self::forYouOrder($uid, $seed)];
            if ((int) ($paging['page'] ?? 1) <= 1 && !$refresh) {
                TasteService::refreshLater($uid);
            }
        }
        $result = self::withFeatured(Post::feed($uid, $query + $paging), $feed, $uid, $paging, $refresh);
        $next = $result['next'];
        if ($next !== null && $feed === 'foryou') {
            $next += ['seed' => $seed];
        }
        return [
            'posts'     => $result['posts'],
            'next'      => $next ?? ['more' => 1],
            'suggested' => false,
        ];
    }

    /** Quita las publicaciones que la persona marcó con «No me importa». */
    private static function withoutNotInterested(array $query, int $uid): array
    {
        $query['where'] = '(' . ($query['where'] ?? '1 = 1') . ')
            AND NOT EXISTS (SELECT 1 FROM post_not_interested ni WHERE ni.user_id = ? AND ni.post_id = p.id)';
        $query['params'] = array_merge($query['params'] ?? [], [$uid]);
        return $query;
    }

    /**
     * Primera página de «Para ti»: lo que la persona acaba de publicar va primero; después, las destacadas por la
     * administración (sin repetirse en esa página) y el resto.
     */
    public static function withFeatured(array $result, string $feed, int $uid, array $paging, bool $refresh = false): array
    {
        if ($feed !== 'foryou' || (int) ($paging['before'] ?? 0) > 0 || (int) ($paging['page'] ?? 1) > 1) {
            return $result;
        }
        $featured = Post::featured($uid, 1, (int) Config::get('app.limits.featured_on_feed', 3))['posts'];
        $featuredIds = $featured !== [] ? array_column($featured, 'id') : [];
        if ($refresh) {
            if ($featured === []) {
                return $result;
            }
            $rest = [];
            foreach ($result['posts'] as $p) {
                if (!in_array($p['id'], $featuredIds, true)) {
                    $rest[] = $p;
                }
            }
            $result['posts'] = array_merge($featured, $rest);
            return $result;
        }
        if ($featured === []) {
            return $result;
        }
        $since = time() - self::OWN_FIRST_HOURS * 3600;
        $own = [];
        $rest = [];
        foreach ($result['posts'] as $p) {
            if (in_array($p['id'], $featuredIds, true)) {
                continue;
            }
            if ($p['user_id'] === $uid && strtotime((string) $p['created_at']) > $since) {
                $own[] = $p;
            } else {
                $rest[] = $p;
            }
        }
        $result['posts'] = array_merge($own, $featured, $rest);
        return $result;
    }
}
