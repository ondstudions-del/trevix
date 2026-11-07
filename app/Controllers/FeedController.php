<?php
declare(strict_types=1);

namespace Trevix\Controllers;

use Trevix\Core\Request;
use Trevix\Data\DemoData;
use Trevix\Middleware\Authenticate;
use Trevix\Models\Post;
use Trevix\Models\Story;

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

        if ($preview) {
            $list = [
                'posts'   => array_values(array_filter(DemoData::posts(), static fn (array $p) => in_array($feed, $p['feeds'], true))),
                'nextUrl' => null,
            ];
        } else {
            $uid = (int) $this->viewer()['id'];
            $result = Post::feed($uid, self::query($feed, $uid) + $this->paging());
            $list = $this->listData($result, 'feed.php', ['feed' => $feed === 'foryou' ? null : $feed]);
        }

        if ($this->isPartial()) {
            $this->renderList($list, self::END_TEXT);
        }

        $this->render('pages/feed', [
            'title'     => 'Inicio · TREVIX',
            'activeNav' => 'home',
            'feed'      => $feed,
            'feeds'     => self::FEEDS,
            'list'      => $list,
            'endText'   => self::END_TEXT,
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
}
