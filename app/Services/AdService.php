<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Database;
use Trevix\Models\Ad;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\Community;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Models\Wallet;

/**
 * OND-ADS (web y API). Cualquiera puede promocionar una publicación pública, una comunidad pública o un grupo público
 * propios, o publicar un anuncio libre (imagen, texto y botón con enlace). Se paga con el monedero al crearlo
 * (precio por día × días, panel › OND-ADS) y la administración lo revisa: si lo rechaza, se devuelve todo.
 *
 * Aprobado, se muestra en el feed (una tarjeta «Patrocinado» por página) a entre reach_min y reach_max personas
 * distintas por día durante los días pagados. Al terminar se liquida: por cada día que no llegó a reach_min personas
 * se devuelve la parte proporcional. Si la persona lo cancela o la administración lo retira, los días que no
 * empezaron se devuelven completos y los ya empezados se liquidan igual.
 */
final class AdService
{
    /** Ajustes del panel: precio por día (centavos), personas por día y días máximos. */
    public static function settings(): array
    {
        $min = max(1, (int) AppSetting::get('ads_reach_min'));
        return [
            'enabled'     => AppSetting::flag('ads_enabled'),
            'daily_cents' => WalletService::settingCents('ads_daily_price'),
            'reach_min'   => $min,
            'reach_max'   => max($min, (int) AppSetting::get('ads_reach_max')),
            'max_days'    => max(1, min(365, (int) AppSetting::get('ads_max_days'))),
        ];
    }

    /** Pantalla de OND-ADS: precio, saldo, lo que se puede promocionar y las campañas propias. */
    public static function summary(int $userId): array
    {
        $s = self::settings();
        return [
            'enabled'     => $s['enabled'],
            'daily_price' => WalletService::amount($s['daily_cents']),
            'reach_min'   => $s['reach_min'],
            'reach_max'   => $s['reach_max'],
            'max_days'    => $s['max_days'],
            'balance'     => WalletService::amount(Wallet::balance($userId)),
            'ctas'        => array_map(static fn (string $id, string $label): array => ['id' => $id, 'label' => t($label)], array_keys(Ad::CTAS), Ad::CTAS),
            'targets'     => [
                'posts'       => array_map(static fn (array $p): array => [
                    'id'         => (int) $p['id'],
                    'excerpt'    => self::excerpt((string) $p['body']) ?: t('Publicación sin texto'),
                    'thumb'      => $p['thumb'],
                    'created_at' => $p['created_at'],
                ], Ad::promotablePosts($userId)),
                'communities' => array_map(static fn (array $c): array => [
                    'id' => (int) $c['id'], 'name' => (string) $c['name'], 'slug' => (string) $c['slug'],
                    'avatar_path' => $c['avatar_path'], 'members_count' => (int) $c['members_count'],
                ], Ad::promotableCommunities($userId)),
                'groups'      => array_map(static fn (array $g): array => [
                    'id' => (int) $g['id'], 'title' => (string) $g['title'], 'avatar_path' => $g['avatar_path'],
                    'members_count' => (int) $g['members_count'],
                ], Ad::promotableGroups($userId)),
            ],
        ];
    }

    private static function excerpt(string $text, int $width = 90): string
    {
        return mb_strimwidth(trim((string) preg_replace('/\s+/u', ' ', $text)), 0, $width, '…');
    }

    // -------------------------------------------------------------------------
    // Crear y cancelar
    // -------------------------------------------------------------------------

    /**
     * Crea la campaña y cobra el total del monedero. $input: kind, target_id (publicación, comunidad o grupo), days y,
     * en el anuncio libre, title, body, link_url y cta. $image: imagen opcional del anuncio libre (MediaUpload::collect).
     *
     * @return array{message:string, campaign:array, balance:array}
     */
    public static function create(array $user, array $input, array $image = []): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        $s = self::settings();
        if (!$s['enabled']) {
            throw new ActionError('OND-ADS no está disponible en este momento.', 503);
        }
        $kind = (string) ($input['kind'] ?? '');
        if (!isset(Ad::KINDS[$kind])) {
            throw ActionError::field('kind', 'Elige qué quieres anunciar.');
        }
        $days = (int) ($input['days'] ?? 0);
        if ($days < 1 || $days > $s['max_days']) {
            throw ActionError::field('days', t('Elige de 1 a {n} días.', ['n' => $s['max_days']]));
        }
        if (Ad::pendingCount($uid) >= 5) {
            throw new ActionError('Tienes 5 anuncios en revisión. Espera a que el equipo los revise.', 429);
        }
        if ($kind === 'post' && (int) ($user['is_private'] ?? 0) === 1) {
            throw ActionError::field('kind', 'Tu cuenta es privada: solo tus seguidores verían la publicación. Hazla pública para promocionarla.');
        }
        $data = ['user_id' => $uid, 'kind' => $kind] + self::target($uid, $kind, (int) ($input['target_id'] ?? 0), $input);
        if (count($image) > 1) {
            throw ActionError::field('image', 'Puedes subir una imagen por anuncio.');
        }

        Guard::rateLimit('ad_create', (string) $uid, 'Creaste muchos anuncios seguidos. Inténtalo en {min} min.');
        RateLimit::hit('ad_create', (string) $uid);

        $imagePath = null;
        if ($kind === 'custom' && $image !== []) {
            try {
                $imagePath = MediaUpload::storeAdImage($image[0])['path'];
            } catch (RuntimeException $e) {
                throw ActionError::field('image', $e->getMessage());
            }
        }
        $total = $s['daily_cents'] * $days;
        $data += [
            'image_path'  => $imagePath,
            'days'        => $days,
            'daily_cents' => $s['daily_cents'],
            'total_cents' => $total,
            'reach_min'   => $s['reach_min'],
            'reach_max'   => $s['reach_max'],
        ];
        try {
            $result = Database::transaction(static function () use ($uid, $data, $total): array {
                Wallet::lock($uid);
                $id = Ad::create($data);
                $balance = Wallet::apply($uid, -$total, 'ad_payment', [], 'OND-ADS #' . $id);
                if ($balance === null) {
                    throw new ActionError(t('Tu saldo no alcanza: la campaña cuesta {price}. Recarga tu monedero.', ['price' => WalletService::money($total)]), 402);
                }
                return ['id' => $id, 'balance' => $balance];
            });
        } catch (Throwable $e) {
            MediaUpload::delete($imagePath);
            throw $e;
        }
        return [
            'message'  => t('Pagaste {price}. El equipo revisará tu anuncio y empezará a mostrarse cuando lo apruebe.', ['price' => WalletService::money($total)]),
            'campaign' => self::presentOwn((array) Ad::find($result['id'])),
            'balance'  => WalletService::amount($result['balance']),
        ];
    }

    /** Valida lo que se anuncia y que sea de quien paga. @return array<string, mixed> columnas de la campaña */
    private static function target(int $uid, string $kind, int $targetId, array $input): array
    {
        switch ($kind) {
            case 'post':
                $post = $targetId > 0 ? Post::findRaw($targetId) : null;
                if ($post === null || (int) $post['user_id'] !== $uid || $post['status'] !== 'published') {
                    throw ActionError::field('target_id', 'Elige una de tus publicaciones.');
                }
                if ($post['visibility'] !== 'public' || $post['community_id'] !== null) {
                    throw ActionError::field('target_id', 'Solo puedes promocionar publicaciones públicas de tu perfil.');
                }
                return ['post_id' => $targetId];
            case 'community':
                $community = $targetId > 0 ? Community::find($targetId, $uid) : null;
                if ($community === null || (int) $community['owner_id'] !== $uid) {
                    throw ActionError::field('target_id', 'Elige una comunidad que administres.');
                }
                if ($community['visibility'] !== 'public') {
                    throw ActionError::field('target_id', 'Solo puedes promocionar comunidades públicas.');
                }
                return ['community_id' => $targetId];
            case 'group':
                $ids = array_map('intval', array_column(Ad::promotableGroups($uid), 'id'));
                if ($targetId < 1 || !in_array($targetId, $ids, true)) {
                    throw ActionError::field('target_id', 'Elige un grupo público que administres.');
                }
                return ['conversation_id' => $targetId];
            default:
                return self::customFields($input);
        }
    }

    /** Título, texto, enlace y botón del anuncio libre. */
    private static function customFields(array $input): array
    {
        $title = trim(Guard::cleanText((string) ($input['title'] ?? '')));
        $body = trim(Guard::cleanText((string) ($input['body'] ?? '')));
        $link = trim((string) ($input['link_url'] ?? ''));
        $cta = (string) ($input['cta'] ?? 'learn_more');
        $errors = [];
        if ($title === '' || mb_strlen($title) > 80) {
            $errors['title'] = t('Escribe un título de hasta {n} caracteres.', ['n' => 80]);
        }
        if (mb_strlen($body) > 300) {
            $errors['body'] = t('El texto puede tener hasta {n} caracteres.', ['n' => 300]);
        }
        $parts = parse_url($link);
        if ($link === '' || strlen($link) > 500 || !filter_var($link, FILTER_VALIDATE_URL)
            || !in_array(strtolower((string) ($parts['scheme'] ?? '')), ['http', 'https'], true) || empty($parts['host']) || isset($parts['user'])) {
            $errors['link_url'] = 'Escribe un enlace válido que empiece por https://';
        }
        if (!isset(Ad::CTAS[$cta])) {
            $errors['cta'] = 'Elige el texto del botón.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }
        return ['title' => $title, 'body' => $body !== '' ? $body : null, 'link_url' => $link, 'cta' => $cta];
    }

    /** La persona cancela su campaña: en revisión se devuelve todo; activa, se liquida hasta hoy. */
    public static function cancel(array $user, int $id): array
    {
        $uid = (int) $user['id'];
        $refund = Database::transaction(static function () use ($uid, $id): int {
            $ad = Ad::lock($id);
            if ($ad === null || (int) $ad['user_id'] !== $uid) {
                throw new ActionError('Este anuncio no existe.', 404);
            }
            if (!in_array($ad['status'], ['pending', 'active'], true)) {
                throw new ActionError('Este anuncio ya terminó.', 409);
            }
            return self::close($ad, 'cancelled', null, null);
        });
        return [
            'message'  => $refund > 0
                ? t('Cancelaste el anuncio. Devolvimos {amount} a tu monedero.', ['amount' => WalletService::money($refund)])
                : t('Cancelaste el anuncio.'),
            'campaign' => self::presentOwn((array) Ad::find($id)),
        ];
    }

    // -------------------------------------------------------------------------
    // Revisión del equipo
    // -------------------------------------------------------------------------

    /** Aprobar (empieza a mostrarse desde ahora) o rechazar con motivo (se devuelve todo). */
    public static function review(array $staff, int $id, bool $approve, string $note): void
    {
        $note = trim(Guard::cleanText($note));
        if (!$approve && ($note === '' || mb_strlen($note) > 255)) {
            throw new DomainException('Escribe el motivo del rechazo (hasta 255 caracteres).');
        }
        $staffId = (int) $staff['id'];
        $ad = Database::transaction(static function () use ($id, $approve, $note, $staffId): array {
            $ad = Ad::lock($id);
            if ($ad === null || $ad['status'] !== 'pending') {
                throw new DomainException('Este anuncio ya no está en revisión.');
            }
            if ($approve) {
                Ad::approve($id, $staffId);
            } else {
                self::close($ad, 'rejected', $staffId, $note);
            }
            return $ad;
        });
        AuditLog::record($staffId, $approve ? 'ads.approve' : 'ads.reject', 'ad', $id, $approve ? [] : ['reason' => $note]);
        Notification::notifySystem((int) $ad['user_id'], $approve ? 'ad_approved' : 'ad_rejected', $id);
    }

    /** Retirar una campaña activa (incumple las normas): se liquida hasta hoy y se devuelve el resto. */
    public static function remove(array $staff, int $id, string $note): void
    {
        $note = trim(Guard::cleanText($note));
        if ($note === '' || mb_strlen($note) > 255) {
            throw new DomainException('Escribe el motivo (hasta 255 caracteres).');
        }
        $staffId = (int) $staff['id'];
        $ad = Database::transaction(static function () use ($id, $note, $staffId): array {
            $ad = Ad::lock($id);
            if ($ad === null || $ad['status'] !== 'active') {
                throw new DomainException('Este anuncio no está activo.');
            }
            self::close($ad, 'removed', $staffId, $note);
            return $ad;
        });
        AuditLog::record($staffId, 'ads.remove', 'ad', $id, ['reason' => $note]);
        Notification::notifySystem((int) $ad['user_id'], 'ad_rejected', $id);
    }

    /**
     * Cierra una campaña bloqueada y devuelve el dinero que corresponda. Devuelve lo devuelto (centavos).
     * - En revisión: todo.
     * - Activa: los días que no empezaron completos; de los empezados, la parte de las personas que faltaron para
     *   llegar a reach_min.
     */
    private static function close(array $ad, string $status, ?int $staffId, ?string $note): int
    {
        $id = (int) $ad['id'];
        $total = (int) $ad['total_cents'];
        if ($ad['status'] === 'pending') {
            $refund = $total;
        } else {
            $days = (int) $ad['days'];
            $daily = (int) $ad['daily_cents'];
            $min = max(1, (int) $ad['reach_min']);
            $elapsed = max(1, min($days, (int) ceil((time() - strtotime((string) $ad['starts_at'])) / 86400)));
            $reach = Ad::reachByDay($id);
            $refund = ($days - $elapsed) * $daily;
            for ($day = 0; $day < $elapsed; $day++) {
                $people = $reach[$day] ?? 0;
                if ($people < $min) {
                    $refund += intdiv($daily * ($min - $people), $min);
                }
            }
        }
        $refund = max(0, min($refund, $total - (int) $ad['refunded_cents']));
        Ad::close($id, $status, $refund, $staffId, $note);
        if ($refund > 0) {
            Wallet::lock((int) $ad['user_id']);
            Wallet::apply((int) $ad['user_id'], $refund, 'ad_refund', [], 'OND-ADS #' . $id);
        }
        return $refund;
    }

    /** Liquida las campañas cuyo plazo terminó (se llama al repartir anuncios y al abrir las pantallas de OND-ADS). */
    public static function settleDue(): void
    {
        foreach (Ad::dueIds() as $id) {
            try {
                $closed = Database::transaction(static function () use ($id): ?array {
                    $ad = Ad::lock($id);
                    if ($ad === null || $ad['status'] !== 'active' || strtotime((string) $ad['ends_at']) > time()) {
                        return null;
                    }
                    self::close($ad, 'finished', null, null);
                    return $ad;
                });
                if ($closed !== null) {
                    Notification::notifySystem((int) $closed['user_id'], 'ad_finished', $id);
                }
            } catch (Throwable $e) {
                error_log('[OND-ADS] No se pudo liquidar la campaña ' . $id . ': ' . $e->getMessage());
            }
        }
    }

    // -------------------------------------------------------------------------
    // Reparto en el feed
    // -------------------------------------------------------------------------

    /**
     * Elige un anuncio para esta página del feed de $viewerId (o null) y anota que lo vio. Solo entran campañas cuyo
     * contenido esta persona puede ver; cada una se muestra una vez por persona y día hasta su tope diario.
     *
     * @return array{campaign:array, post:?array, community:?array, group:?array, sponsor:array}|null
     */
    public static function deliver(int $viewerId): ?array
    {
        if ($viewerId < 1 || !AppSetting::flag('ads_enabled')) {
            return null;
        }
        try {
            self::settleDue();
            foreach (Ad::candidates($viewerId) as $ad) {
                $item = self::resolve($ad, $viewerId);
                $sponsor = $item !== null ? User::findActiveById((int) $ad['user_id']) : null;
                if ($sponsor === null) {
                    continue;
                }
                Ad::recordImpression((int) $ad['id'], (int) $ad['day_index'], $viewerId);
                return $item + ['sponsor' => [
                    'id' => (int) $sponsor['id'], 'username' => (string) $sponsor['username'], 'display_name' => (string) $sponsor['display_name'],
                    'avatar_path' => $sponsor['avatar_path'], 'is_verified' => (int) $sponsor['is_verified'],
                ]];
            }
        } catch (Throwable $e) {
            error_log('[OND-ADS] ' . $e->getMessage());
        }
        return null;
    }

    /** Contenido anunciado tal como lo vería $viewerId; null si ya no está disponible para esa persona. */
    private static function resolve(array $ad, int $viewerId): ?array
    {
        $item = ['campaign' => $ad, 'post' => null, 'community' => null, 'group' => null];
        switch ($ad['kind']) {
            case 'post':
                $item['post'] = $ad['post_id'] !== null ? Post::findVisible((int) $ad['post_id'], $viewerId) : null;
                return $item['post'] !== null && $item['post']['visibility'] === 'public' ? $item : null;
            case 'community':
                $item['community'] = $ad['community_id'] !== null ? Community::find((int) $ad['community_id'], $viewerId) : null;
                return $item['community'] !== null && $item['community']['visibility'] === 'public' ? $item : null;
            case 'group':
                $item['group'] = $ad['conversation_id'] !== null ? Ad::publicGroup((int) $ad['conversation_id'], $viewerId) : null;
                return $item['group'] !== null ? $item : null;
            default:
                return $item;
        }
    }

    /** Página a la que lleva el anuncio (relativa para la web; los anuncios libres, su enlace). */
    public static function destination(array $item): string
    {
        $ad = $item['campaign'];
        return match ($ad['kind']) {
            'post'      => 'post.php?id=' . (int) $ad['post_id'],
            'community' => 'community.php?c=' . rawurlencode((string) ($item['community']['slug'] ?? $ad['community_slug'] ?? '')),
            'group'     => 'g.php?c=' . rawurlencode((string) ($item['group']['invite_code'] ?? '')),
            default     => (string) $ad['link_url'],
        };
    }

    /**
     * Toque en un anuncio: cuenta una vez por persona y día (si lo vio ese día) y devuelve adónde lleva.
     *
     * @return array{kind:string, url:string, post_id:?int, community_slug:?string, invite_code:?string}
     */
    public static function click(int $viewerId, int $id): array
    {
        $ad = $id > 0 ? Ad::find($id) : null;
        if ($ad === null || !in_array($ad['status'], ['active', 'finished'], true)) {
            throw new ActionError('Este anuncio ya no está disponible.', 404);
        }
        $item = self::resolve($ad, $viewerId);
        if ($item === null) {
            throw new ActionError('Este anuncio ya no está disponible.', 404);
        }
        if ($ad['status'] === 'active' && (int) $ad['user_id'] !== $viewerId) {
            Ad::recordClick($id, $viewerId);
        }
        $url = self::destination($item);
        return [
            'kind'           => (string) $ad['kind'],
            'url'            => $ad['kind'] === 'custom' ? $url : absolute_url($url),
            'post_id'        => $ad['kind'] === 'post' ? (int) $ad['post_id'] : null,
            'community_slug' => $ad['kind'] === 'community' ? (string) ($item['community']['slug'] ?? '') : null,
            'invite_code'    => $ad['kind'] === 'group' ? (string) ($item['group']['invite_code'] ?? '') : null,
        ];
    }

    // -------------------------------------------------------------------------
    // Presentación
    // -------------------------------------------------------------------------

    /** Campaña propia (o del panel) con su estado, dinero y alcance. */
    public static function presentOwn(array $a): array
    {
        $days = (int) ($a['days'] ?? 0);
        $now = time();
        $starts = $a['starts_at'] !== null ? strtotime((string) $a['starts_at']) : null;
        $ends = $a['ends_at'] !== null ? strtotime((string) $a['ends_at']) : null;
        return [
            'id'          => (int) $a['id'],
            'kind'        => (string) $a['kind'],
            'kind_label'  => t(Ad::KINDS[$a['kind']] ?? ''),
            'status'      => (string) $a['status'],
            'status_label' => t(Ad::STATUSES[$a['status']] ?? ''),
            'target'      => match ($a['kind']) {
                'post'      => $a['post_id'] !== null ? (self::excerpt((string) ($a['post_body'] ?? ''), 70) ?: t('Publicación sin texto')) : t('Publicación eliminada'),
                'community' => (string) ($a['community_name'] ?? t('Comunidad eliminada')),
                'group'     => (string) ($a['group_title'] ?? t('Grupo eliminado')),
                default     => (string) ($a['title'] ?? ''),
            },
            'post_id'     => $a['post_id'] !== null ? (int) $a['post_id'] : null,
            'community_slug' => $a['community_slug'] ?? null,
            'title'       => $a['title'],
            'body'        => $a['body'],
            'image_path'  => $a['image_path'],
            'link_url'    => $a['link_url'],
            'cta'         => $a['cta'],
            'cta_label'   => $a['cta'] !== null ? t(Ad::CTAS[$a['cta']] ?? 'Más información') : null,
            'days'        => $days,
            'days_left'   => $a['status'] === 'active' && $ends !== null ? max(0, (int) ceil(($ends - $now) / 86400)) : null,
            'total'       => WalletService::amount((int) $a['total_cents']),
            'refunded'    => WalletService::amount((int) $a['refunded_cents']),
            'reach_min'   => (int) $a['reach_min'],
            'reach_max'   => (int) $a['reach_max'],
            'impressions' => (int) $a['impressions'],
            'clicks'      => (int) $a['clicks'],
            'review_note' => $a['review_note'],
            'starts_at'   => $starts !== null ? (string) $a['starts_at'] : null,
            'ends_at'     => $ends !== null ? (string) $a['ends_at'] : null,
            'created_at'  => (string) $a['created_at'],
            'can_cancel'  => in_array($a['status'], ['pending', 'active'], true),
            'user'        => isset($a['username']) ? [
                'id' => (int) $a['user_id'], 'username' => $a['username'], 'display_name' => $a['display_name'],
                'avatar_path' => $a['avatar_path'], 'is_verified' => (int) $a['is_verified'],
            ] : null,
        ];
    }

    /** @return array{items: list<array>, next: ?array} */
    public static function mine(int $userId, int $before): array
    {
        self::settleDue();
        $page = Ad::forUser($userId, $before, 20);
        $items = array_map([self::class, 'presentOwn'], $page['items']);
        return ['items' => $items, 'next' => $page['hasMore'] && $items !== [] ? ['before' => (int) end($items)['id']] : null];
    }
}
