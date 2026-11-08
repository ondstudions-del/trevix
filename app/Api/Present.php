<?php
declare(strict_types=1);

namespace Trevix\Api;

use Trevix\Core\Auth;
use Trevix\Core\Config;
use Trevix\Models\Song;
use Trevix\Models\User;
use Trevix\Services\MusicService;

/**
 * Formas JSON estables de la API v1. Fechas en ISO 8601 con zona horaria, archivos como URL absoluta,
 * banderas como booleanos e ids como enteros. Nunca incluye hashes, IPs ni datos de otras cuentas que
 * la web no muestre.
 */
final class Present
{
    public static function date(?string $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        $time = strtotime($value);
        return $time !== false ? date(DATE_ATOM, $time) : null;
    }

    /** URL absoluta de un archivo subido (uploads/…); null si no hay. */
    public static function file(?string $path): ?string
    {
        return $path !== null && $path !== '' ? absolute_url($path) : null;
    }

    /** Cuenta en listas, autores y tarjetas. Incluye la relación con quien mira si se calculó. */
    public static function user(array $u): array
    {
        $out = [
            'id'           => (int) $u['id'],
            'username'     => (string) $u['username'],
            'display_name' => (string) $u['display_name'],
            'avatar_url'   => self::file($u['avatar_path'] ?? null),
            'is_verified'  => !empty($u['is_verified']),
        ];
        if (array_key_exists('is_private', $u)) {
            $out['is_private'] = !empty($u['is_private']);
        }
        if (array_key_exists('bio', $u)) {
            $out['bio'] = (string) ($u['bio'] ?? '');
        }
        if (array_key_exists('followers_count', $u)) {
            $out['followers_count'] = (int) $u['followers_count'];
        }
        if (isset($u['relation'])) {
            $out['relation'] = self::relation($u['relation']);
        } elseif (array_key_exists('viewer_follows', $u)) {
            $out['relation'] = ['following' => !empty($u['viewer_follows'])];
        }
        return $out;
    }

    public static function relation(array $r): array
    {
        return [
            'following'   => !empty($r['following']),
            'requested'   => !empty($r['requested']),
            'follows_you' => !empty($r['follows_you']),
        ];
    }

    /** Perfil público de una cuenta (sin correo, fecha de nacimiento ni ajustes). */
    public static function profile(array $u): array
    {
        $creator = ($u['account_type'] ?? 'personal') === 'creator';
        return self::user($u) + [
            'bio'             => (string) ($u['bio'] ?? ''),
            'website'         => $u['website'] ?? null,
            'country'         => $u['country'] ?? null,
            'cover_url'       => self::file($u['cover_path'] ?? null),
            'is_private'      => !empty($u['is_private']),
            'account_type'    => $creator ? 'creator' : 'personal',
            'creator_category' => $creator ? ($u['creator_category'] ?? null) : null,
            'creator_label'   => User::creatorLabel($u),
            'is_music_artist' => User::isMusicArtist($u),
            'role'            => in_array($u['role'] ?? 'user', ['moderator', 'admin'], true) ? $u['role'] : 'user',
            'online'          => User::isOnline($u),
            'followers_count' => (int) ($u['followers_count'] ?? 0),
            'following_count' => (int) ($u['following_count'] ?? 0),
            'posts_count'     => (int) ($u['posts_count'] ?? 0),
            'created_at'      => self::date($u['created_at'] ?? null),
        ];
    }

    /** La propia cuenta: perfil, correo, ajustes y contadores de avisos. */
    public static function me(array $u): array
    {
        return self::profile($u) + [
            'email'          => (string) $u['email'],
            'email_verified' => !empty($u['email_verified_at']),
            'birth_date'     => $u['birth_date'] ?? null,
            'role'           => (string) ($u['role'] ?? 'user'),
            'is_staff'       => Auth::hasRole('moderator', $u),
            'settings'       => [
                'is_private'      => !empty($u['is_private']),
                'show_activity'   => !empty($u['show_activity']),
                'message_privacy' => (string) $u['message_privacy'],
                'notify_follows'  => !empty($u['notify_follows']),
                'notify_likes'    => !empty($u['notify_likes']),
                'notify_comments' => !empty($u['notify_comments']),
                'notify_mentions' => !empty($u['notify_mentions']),
            ],
            'counts'         => self::counts($u),
        ];
    }

    public static function counts(array $u): array
    {
        return [
            'notifications'    => (int) ($u['unread_notifications'] ?? 0),
            'follow_requests'  => (int) ($u['pending_requests'] ?? 0),
            'messages'         => (int) ($u['unread_messages'] ?? 0),
        ];
    }

    public static function post(array $p): array
    {
        $viewerId = (int) Auth::id();
        $out = [
            'id'         => (int) $p['id'],
            'format'     => $p['format'],
            'body'       => (string) $p['body'],
            'visibility' => $p['visibility'],
            'created_at' => self::date($p['created_at']),
            'is_edited'  => !empty($p['is_edited']),
            'user'       => self::user($p['user']),
            'community'  => $p['community'] !== null ? [
                'id'         => (int) $p['community']['id'],
                'slug'       => $p['community']['slug'],
                'name'       => $p['community']['name'],
                'visibility' => $p['community']['visibility'],
            ] : null,
            'media'      => array_map(static fn (array $m): array => [
                'type'   => $m['type'],
                'url'    => self::file($m['src']),
                'alt'    => (string) ($m['alt'] ?? ''),
                'width'  => $m['width'] ?? null,
                'height' => $m['height'] ?? null,
            ], $p['media']),
            'background' => $p['background'] ?? null,
            'life_event' => $p['life_event'] ?? null,
            'location'   => $p['location'] ?? null,
            'gif'        => $p['gif'] ?? null,
            'event'      => isset($p['event']) ? self::event($p['event']) : null,
            'featured'   => !empty($p['featured']),
            'song'               => isset($p['song']) ? self::song($p['song'], true) : null,
            'shared'             => $p['shared'] !== null ? self::post($p['shared']) : null,
            'shared_unavailable' => !empty($p['shared_missing']),
            'counts'     => [
                'likes'    => (int) ($p['likes_count'] ?? 0),
                'comments' => (int) ($p['comments_count'] ?? 0),
                'shares'   => (int) ($p['shares_count'] ?? 0),
                'saves'    => (int) ($p['saves_count'] ?? 0),
            ],
            'viewer'     => [
                'liked'     => !empty($p['viewer_liked']),
                'saved'     => !empty($p['viewer_saved']),
                'is_author' => (int) $p['user']['id'] === $viewerId,
            ],
            'web_url'    => absolute_url('post.php?id=' . (int) $p['id']),
        ];
        if (isset($p['community']['can_moderate'])) {
            $out['community']['can_moderate'] = (bool) $p['community']['can_moderate'];
        }
        return $out;
    }

    public static function event(array $e): array
    {
        return [
            'id'               => (int) $e['id'],
            'title'            => $e['title'],
            'description'      => (string) $e['description'],
            'place'            => $e['place'],
            'starts_at'        => self::date($e['starts_at']),
            'ends_at'          => $e['ends_at'] !== null ? self::date($e['ends_at']) : null,
            'cover_url'        => $e['cover_path'] !== null ? self::file($e['cover_path']) : null,
            'going_count'      => (int) $e['going_count'],
            'interested_count' => (int) $e['interested_count'],
            'viewer_response'  => $e['viewer_response'],
            'is_past'          => (bool) $e['is_past'],
            'is_owner'         => (int) $e['user_id'] === (int) Auth::id(),
        ];
    }

    public static function posts(array $posts): array
    {
        return array_map([self::class, 'post'], $posts);
    }

    public static function comment(array $c, ?int $postOwnerId = null): array
    {
        $viewerId = (int) Auth::id();
        return [
            'id'            => (int) $c['id'],
            'post_id'       => (int) $c['post_id'],
            'parent_id'     => $c['parent_id'] !== null ? (int) $c['parent_id'] : null,
            'body'          => (string) $c['body'],
            'gif'           => $c['gif'] ?? null,
            'created_at'    => self::date($c['created_at']),
            'user'          => self::user($c['user']),
            'replies_count' => (int) ($c['replies_count'] ?? 0),
            'replies'       => array_map(static fn (array $r) => self::comment($r, $postOwnerId), $c['replies'] ?? []),
            'can_delete'    => (int) $c['user_id'] === $viewerId || ($postOwnerId !== null && $postOwnerId === $viewerId),
        ];
    }

    public static function notification(array $n): array
    {
        return [
            'id'           => (int) $n['id'],
            'type'         => $n['type'],
            'actor'        => $n['actor'] !== null ? self::user($n['actor']) : null,
            'text'         => $n['text'],
            'excerpt'      => $n['excerpt'],
            'thumb_url'    => self::file($n['thumb'] ?? null),
            'post_id'      => $n['post_id'],
            'song_id'      => $n['song_id'] ?? null,
            'comment_id'   => $n['comment_id'] ?? null,
            'community_id' => $n['community_id'] ?? null,
            'read'         => (bool) $n['read'],
            'created_at'   => self::date($n['created_at']),
        ];
    }

    public static function conversation(array $c): array
    {
        $out = [
            'id'              => (int) $c['id'],
            'user'            => self::user($c['user']),
            'available'       => (bool) $c['available'],
            'blocked'         => (bool) $c['blocked'],
            'online'          => (bool) $c['online'],
            'unread'          => (int) $c['unread'],
            'muted'           => (bool) $c['muted'],
            'preview'         => $c['preview'],
            'last_message_at' => self::date($c['last_message_at'] ?? null),
        ];
        if (array_key_exists('partner_last_read', $c)) {
            $out['partner_last_read_id'] = (int) $c['partner_last_read'];
        }
        return $out;
    }

    public static function message(array $m): array
    {
        $deleted = $m['deleted_at'] !== null;
        $voice = !empty($m['media_path']) && str_starts_with((string) ($m['media_mime'] ?? ''), 'audio/');
        $story = $m['story'] ?? null;
        return [
            'id'              => (int) $m['id'],
            'conversation_id' => (int) $m['conversation_id'],
            'sender_id'       => $m['sender_id'] !== null ? (int) $m['sender_id'] : null,
            'is_mine'         => $m['sender_id'] !== null && (int) $m['sender_id'] === (int) Auth::id(),
            'body'            => $deleted ? null : $m['body'],
            'image_url'       => $deleted || $voice ? null : self::file($m['media_path'] ?? null),
            'voice'           => !$deleted && $voice ? [
                'url'      => self::file($m['media_path']),
                'mime'     => $m['media_mime'],
                'duration' => (int) ($m['media_duration'] ?? 0),
            ] : null,
            'gif'             => $deleted ? null : ($m['gif'] ?? null),
            'song'            => !$deleted && isset($m['song']) ? self::song($m['song']) : null,
            'deleted'         => $deleted,
            'story'           => $m['story_id'] !== null ? ($story !== null ? [
                'id'         => (int) $story['id'],
                'type'       => $story['media_type'],
                'media_url'  => self::file($story['media_path'] ?? null),
                'body'       => (string) ($story['body'] ?? ''),
                'background' => $story['background'],
            ] : ['id' => (int) $m['story_id'], 'expired' => true]) : null,
            'created_at'      => self::date($m['created_at']),
        ];
    }

    public static function messages(array $messages): array
    {
        return array_map([self::class, 'message'], $messages);
    }

    public static function storyGroup(array $g): array
    {
        $own = (int) $g['user']['id'] === (int) Auth::id();
        return [
            'user'          => self::user($g['user']),
            'own'           => $own,
            'reply_blocked' => $g['replyBlocked'] ?? null,
            'items'         => array_map(static fn (array $s): array => [
                'id'         => (int) $s['id'],
                'type'       => $s['type'],
                'media_url'  => self::file($s['src'] ?? null),
                'mime'       => $s['mime'],
                'body'       => (string) $s['body'],
                'background' => $s['background'],
                'song'       => isset($s['song']) ? self::song($s['song'], true) : null,
                'seconds'    => (int) $s['seconds'],
                'views'      => $own ? (int) $s['views'] : null,
                'seen'       => (bool) $s['seen'],
                'created_at' => self::date($s['created_at']),
            ], $g['items']),
        ];
    }

    /**
     * Canción de la biblioteca (Song::cardsFor). Si ya no está disponible solo trae id y available=false:
     * la app muestra «Canción no disponible». Con $clip, añade el fragmento elegido (publicaciones e historias).
     */
    public static function song(array $s, bool $clip = false): array
    {
        if (empty($s['available'])) {
            return ['id' => (int) $s['id'], 'available' => false];
        }
        $out = [
            'id'           => (int) $s['id'],
            'available'    => true,
            'title'        => $s['title'],
            'featuring'    => $s['featuring'],
            'genre'        => $s['genre'],
            'genre_label'  => Song::GENRES[$s['genre']] ?? 'Otro',
            'is_explicit'  => (bool) $s['is_explicit'],
            'duration'     => (int) $s['duration'],
            'audio_url'    => self::file($s['src']),
            'mime'         => $s['mime'],
            'cover_url'    => self::file($s['cover'] ?? null),
            'uses_count'   => (int) $s['uses_count'],
            'published_at' => self::date($s['published_at'] ?? null),
            'artist'       => self::user($s['artist']),
            'source'       => $s['source'] ?? 'trevix',
            'source_label' => $s['source_label'] ?? 'TREVIX',
            'external_url' => $s['external_url'] ?? null,
            'web_url'      => absolute_url('music.php?id=' . (int) $s['id']),
        ];
        if ($clip) {
            $start = (int) ($s['start'] ?? 0);
            $out['clip'] = [
                'start' => $start,
                'end'   => min((int) $s['duration'], $start + (int) Config::get('app.limits.song_clip_seconds', 30)),
            ];
        }
        return $out;
    }

    public static function songs(array $songs): array
    {
        return array_map(static fn (array $s): array => self::song($s), $songs);
    }

    /** Canción propia en el panel del artista (Song::forArtist): cualquier estado, con revisión y usos. */
    public static function ownSong(array $s): array
    {
        return [
            'id'           => (int) $s['id'],
            'title'        => $s['title'],
            'featuring'    => $s['featuring'],
            'genre'        => $s['genre'],
            'genre_label'  => Song::GENRES[$s['genre']] ?? 'Otro',
            'is_explicit'  => (bool) $s['is_explicit'],
            'status'       => $s['status'],
            'status_label' => Song::STATUSES[$s['status']] ?? $s['status'],
            'duration'     => (int) $s['duration_seconds'],
            'size_bytes'   => (int) $s['size_bytes'],
            'audio_url'    => self::file($s['audio_path']),
            'mime'         => $s['audio_mime'],
            'cover_url'    => self::file($s['cover_path'] ?? null),
            'review_note'  => in_array($s['status'], ['rejected', 'removed', 'published'], true) ? $s['review_note'] : null,
            'reviewed_at'  => self::date($s['reviewed_at'] ?? null),
            'published_at' => self::date($s['published_at'] ?? null),
            'created_at'   => self::date($s['created_at']),
            'uses'         => [
                'total'    => (int) $s['uses_count'],
                'posts'    => (int) ($s['post_uses'] ?? 0),
                'stories'  => (int) ($s['story_uses'] ?? 0),
                'messages' => (int) ($s['message_uses'] ?? 0),
            ],
            'actions'      => array_values(array_filter([
                $s['status'] === 'pending' ? 'cancel' : null,
                $s['status'] === 'published' ? 'withdraw' : null,
                $s['status'] === 'withdrawn' ? 'republish' : null,
                in_array($s['status'], MusicService::DELETABLE, true) ? 'delete' : null,
            ])),
        ];
    }

    public static function community(array $c, ?array $access = null): array
    {
        $out = [
            'id'            => (int) $c['id'],
            'slug'          => $c['slug'],
            'name'          => $c['name'],
            'description'   => (string) $c['description'],
            'category'      => (string) $c['category'],
            'avatar_url'    => self::file($c['avatar_path'] ?? null),
            'cover_url'     => self::file($c['cover_path'] ?? null),
            'visibility'    => $c['visibility'],
            'members_count' => (int) $c['members_count'],
            'posts_count'   => (int) $c['posts_count'],
            'created_at'    => self::date($c['created_at']),
            'membership'    => $c['membership'],
            'web_url'       => absolute_url('community.php?c=' . rawurlencode((string) $c['slug'])),
        ];
        if (isset($c['owner'])) {
            $out['owner'] = $c['owner'] + ['id' => (int) $c['owner_id']];
        }
        if ($access !== null) {
            $out['access'] = [
                'member'      => $access['member'],
                'owner'       => $access['owner'],
                'manager'     => $access['manager'],
                'banned'      => $access['banned'],
                'pending'     => $access['pending'],
                'can_view'    => $access['canView'],
                'can_post'    => $access['canPost'],
            ];
        }
        return $out;
    }

    /**
     * Datos del panel de administración: se conservan las claves del modelo, las fechas pasan a ISO 8601
     * y las rutas de archivos (uploads/…) a URL absoluta. Se quitan las claves internas («row»).
     */
    public static function admin(mixed $value): mixed
    {
        if (!is_array($value)) {
            return $value;
        }
        $out = [];
        foreach ($value as $key => $item) {
            if ($key === 'row' || $key === 'password_hash' || $key === 'ip_address') {
                continue;
            }
            if (is_string($item) && str_starts_with($item, 'uploads/')) {
                $out[$key] = self::file($item);
            } elseif (is_string($key) && is_string($item) && (str_ends_with($key, '_at') || str_ends_with($key, '_until'))) {
                $out[$key] = self::date($item);
            } else {
                $out[$key] = self::admin($item);
            }
        }
        return $out;
    }
}
