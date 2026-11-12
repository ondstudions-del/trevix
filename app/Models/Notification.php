<?php
declare(strict_types=1);

namespace Trevix\Models;

use Trevix\Services\Mentions;

/**
 * Notificaciones de actividad. Nunca se avisa a uno mismo, ni a cuentas inactivas, ni entre cuentas
 * bloqueadas, ni de tipos que la persona desactivó en Configuración. Repetir una acción (seguir, dar
 * me gusta) reemplaza el aviso anterior en lugar de duplicarlo, y deshacerla lo retira.
 * Las solicitudes de seguimiento no se guardan aquí: se leen en vivo de follow_requests.
 */
final class Notification extends Model
{
    /** Tipos que muestra la pestaña "Menciones". */
    public const MENTION_TYPES = ['mention', 'reply', 'comment'];

    /** Crea el aviso si corresponde. Devuelve true si se creó. */
    public static function notify(
        int $userId,
        int $actorId,
        string $type,
        ?int $postId = null,
        ?int $commentId = null,
        ?int $communityId = null
    ): bool {
        $column = User::NOTIFY_COLUMNS[$type] ?? null;
        if ($column === null || $userId === $actorId || $userId < 1 || $actorId < 1) {
            return false;
        }
        $allowed = (bool) self::fetchValue(
            "SELECT 1 FROM users u WHERE u.id = ? AND u.status = 'active' AND u.$column = 1
               AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = u.id AND b.blocked_id = ?) OR (b.blocker_id = ? AND b.blocked_id = u.id))
             LIMIT 1",
            [$userId, $actorId, $actorId]
        );
        if (!$allowed) {
            return false;
        }
        self::remove($userId, $actorId, $type, $postId, $commentId, $communityId);
        self::execute(
            'INSERT INTO notifications (user_id, actor_id, type, post_id, comment_id, community_id) VALUES (?, ?, ?, ?, ?, ?)',
            [$userId, $actorId, $type, $postId, $commentId, $communityId]
        );
        return true;
    }

    /** Tipos que envía TREVIX (sin persona que actúe) sobre la revisión de una canción. */
    public const SONG_TYPES = ['song_approved', 'song_rejected', 'song_removed'];

    /** Aviso del equipo sobre una canción del artista. No depende de preferencias: es parte de la revisión. */
    public static function notifySong(int $userId, string $type, int $songId): void
    {
        if (!in_array($type, self::SONG_TYPES, true)) {
            return;
        }
        self::execute(
            "INSERT INTO notifications (user_id, actor_id, type, song_id)
             SELECT id, NULL, ?, ? FROM users WHERE id = ? AND status = 'active'",
            [$type, $songId, $userId]
        );
    }

    /** Avisos del equipo de TREVIX, sin persona que actúe: advertencias y decisiones sobre el verificado. */
    public const SYSTEM_TYPES = ['warning', 'verification_approved', 'verification_rejected', 'appeal_accepted', 'appeal_rejected',
        'topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected', 'wallet_adjusted', 'collaborator_enabled',
        'ad_approved', 'ad_rejected', 'ad_finished'];

    /** Avisos de OND-ADS (ref_id = la campaña). */
    public const AD_TYPES = ['ad_approved', 'ad_rejected', 'ad_finished'];

    /** Avisos del monedero (recargas, retiros y ajustes del equipo). */
    public const WALLET_TYPES = ['topup_approved', 'topup_rejected', 'withdrawal_paid', 'withdrawal_rejected', 'wallet_adjusted'];

    /** Alguien compró una suscripción al colaborador. Siempre llega: es un ingreso, no depende de los ajustes de avisos. */
    public static function notifySubscription(int $collaboratorId, int $subscriberId, int $subscriptionId): void
    {
        self::execute(
            "INSERT INTO notifications (user_id, actor_id, type, ref_id)
             SELECT id, ?, 'subscription', ? FROM users WHERE id = ? AND status = 'active'",
            [$subscriberId, $subscriptionId, $collaboratorId]
        );
    }

    /** Alguien envió un regalo ($sendId). Siempre llega: es un ingreso, no depende de los ajustes de avisos. */
    public static function notifyGift(int $recipientId, int $senderId, int $sendId): void
    {
        self::execute(
            "INSERT INTO notifications (user_id, actor_id, type, ref_id)
             SELECT id, ?, 'gift', ? FROM users WHERE id = ? AND status = 'active'",
            [$senderId, $sendId, $recipientId]
        );
    }

    /** $refId: la advertencia o la solicitud de verificado. Siempre llega (no depende de los ajustes de avisos). */
    public static function notifySystem(int $userId, string $type, int $refId): void
    {
        if (!in_array($type, self::SYSTEM_TYPES, true)) {
            return;
        }
        self::execute(
            "INSERT INTO notifications (user_id, actor_id, type, ref_id)
             SELECT id, NULL, ?, ? FROM users WHERE id = ? AND status = 'active'",
            [$type, $refId, $userId]
        );
    }

    /**
     * Avisa a las personas mencionadas con @ que pueden ver la publicación.
     *
     * @param list<int>    $skipIds   cuentas que ya recibieron otro aviso por la misma acción
     * @param list<string> $skipNames menciones que ya estaban (al editar)
     */
    public static function notifyMentions(int $actorId, ?string $text, int $postId, ?int $commentId = null, array $skipIds = [], array $skipNames = []): void
    {
        $names = array_values(array_diff(Mentions::extract($text), $skipNames));
        if ($names === []) {
            return;
        }
        $ids = self::fetchAll(
            'SELECT id FROM users WHERE status = \'active\' AND username IN (' . implode(',', array_fill(0, count($names), '?')) . ')',
            $names
        );
        foreach (array_map('intval', array_column($ids, 'id')) as $id) {
            if ($id === $actorId || in_array($id, $skipIds, true) || Post::findVisible($postId, $id) === null) {
                continue;
            }
            self::notify($id, $actorId, 'mention', $postId, $commentId);
        }
    }

    /** Retira el aviso de una acción que se deshizo (quitar el me gusta, dejar de seguir). */
    public static function remove(
        int $userId,
        int $actorId,
        string $type,
        ?int $postId = null,
        ?int $commentId = null,
        ?int $communityId = null
    ): void {
        self::execute(
            'DELETE FROM notifications WHERE user_id = ? AND actor_id = ? AND type = ? AND post_id <=> ? AND comment_id <=> ? AND community_id <=> ?',
            [$userId, $actorId, $type, $postId, $commentId, $communityId]
        );
    }

    /** Retira los avisos de un tipo sobre una comunidad que generó una persona (p. ej. al resolver su solicitud). */
    public static function removeForCommunity(int $communityId, int $actorId, string $type): void
    {
        self::execute(
            'DELETE FROM notifications WHERE community_id = ? AND actor_id = ? AND type = ?',
            [$communityId, $actorId, $type]
        );
    }

    /** Al bloquear: se borran los avisos entre ambas cuentas, en los dos sentidos. */
    public static function removeBetween(int $a, int $b): void
    {
        self::execute(
            'DELETE FROM notifications WHERE (user_id = ? AND actor_id = ?) OR (user_id = ? AND actor_id = ?)',
            [$a, $b, $b, $a]
        );
    }

    public static function unreadCount(int $userId): int
    {
        return (int) self::fetchValue(
            "SELECT COUNT(*) FROM notifications n LEFT JOIN users a ON a.id = n.actor_id
             WHERE n.user_id = ? AND n.read_at IS NULL AND (n.actor_id IS NULL OR a.status = 'active')",
            [$userId]
        );
    }

    private const LIST_SQL = "SELECT n.id, n.type, n.post_id, n.comment_id, n.community_id, n.song_id, n.ref_id, n.read_at, n.created_at,
                    ap.type AS appeal_type, ap.resolution_note AS appeal_note,
                    a.id AS actor_id, a.username, a.display_name, a.avatar_path, a.is_verified, a.is_private,
                    COALESCE(NULLIF(p.body, ''), sp.body) AS post_body,
                    COALESCE(NULLIF(c.body, ''), CASE c.gif_kind WHEN 'sticker' THEN 'Sticker' WHEN 'gif' THEN 'GIF' END) AS comment_body,
                    cm.name AS community_name, cm.slug AS community_slug, sg.title AS song_title, sg.review_note AS song_note,
                    uw.reason AS warning_reason, vr.decision_note AS verification_note,
                    COALESCE(wt.credited_cents, wt.amount_cents, ww.amount_cents, ABS(wx.amount_cents)) AS wallet_amount,
                    COALESCE(wt.decision_note, ww.decision_note, wx.note) AS wallet_note, wx.amount_cents AS adjust_cents,
                    gs.gift_name, gs.earning_cents AS gift_earning, nt.body AS note_body,
                    adc.status AS ad_status, adc.review_note AS ad_note, adc.refunded_cents AS ad_refunded, adc.impressions AS ad_impressions,
                    COALESCE((SELECT pm.path FROM post_media pm WHERE pm.post_id = COALESCE(sp.id, p.id) AND pm.type = 'image'
                      ORDER BY pm.position LIMIT 1), sg.cover_path) AS thumb
             FROM notifications n
             LEFT JOIN users a ON a.id = n.actor_id
             LEFT JOIN posts p ON p.id = n.post_id
             LEFT JOIN posts sp ON sp.id = p.shared_post_id
             LEFT JOIN comments c ON c.id = n.comment_id
             LEFT JOIN communities cm ON cm.id = n.community_id
             LEFT JOIN songs sg ON sg.id = n.song_id
             LEFT JOIN user_warnings uw ON n.type = 'warning' AND uw.id = n.ref_id
             LEFT JOIN verification_requests vr ON n.type = 'verification_rejected' AND vr.id = n.ref_id
             LEFT JOIN appeals ap ON n.type IN ('appeal_accepted', 'appeal_rejected') AND ap.id = n.ref_id
             LEFT JOIN wallet_topups wt ON n.type IN ('topup_approved', 'topup_rejected') AND wt.id = n.ref_id
             LEFT JOIN wallet_withdrawals ww ON n.type IN ('withdrawal_paid', 'withdrawal_rejected') AND ww.id = n.ref_id
             LEFT JOIN wallet_transactions wx ON n.type = 'wallet_adjusted' AND wx.id = n.ref_id
             LEFT JOIN gift_sends gs ON n.type = 'gift' AND gs.id = n.ref_id
             LEFT JOIN user_notes nt ON n.type = 'new_note' AND nt.id = n.ref_id
             LEFT JOIN ad_campaigns adc ON n.type IN ('ad_approved', 'ad_rejected', 'ad_finished') AND adc.id = n.ref_id";

    /**
     * Avisos sin leer posteriores a $afterId, del más antiguo al más reciente (avisos del teléfono), cada uno con
     * la pantalla de la app que abre ("link", relativa: post.php?id=5).
     *
     * @return list<array>
     */
    public static function unreadSince(int $userId, int $afterId, int $limit): array
    {
        $rows = self::fetchAll(
            self::LIST_SQL . " WHERE n.user_id = ? AND n.id > ? AND n.read_at IS NULL AND (n.actor_id IS NULL OR a.status = 'active')
             ORDER BY n.id ASC LIMIT " . max(1, min(50, $limit)),
            [$userId, $afterId]
        );
        return array_map(static fn (array $r) => self::present($r) + ['link' => self::appLink($r)], $rows);
    }

    /** Pantalla de la app para un aviso (las rutas que entiende el enlace trevix://open/...). */
    private static function appLink(array $r): string
    {
        $type = (string) $r['type'];
        return match (true) {
            in_array($type, self::WALLET_TYPES, true)             => 'wallet.php',
            $type === 'collaborator_enabled'                      => 'wallet.php?tab=collaborator',
            $type === 'gift'                                      => 'gifts.php?tab=received',
            in_array($type, self::AD_TYPES, true)                 => 'ads.php',
            $type === 'new_story' && !empty($r['username'])       => 'stories.php?u=' . rawurlencode((string) $r['username']),
            in_array($type, self::SONG_TYPES, true), in_array($type, self::SYSTEM_TYPES, true) => 'notifications.php',
            $r['post_id'] !== null                                => 'post.php?id=' . (int) $r['post_id'],
            !empty($r['community_slug'])                          => 'community.php?c=' . rawurlencode((string) $r['community_slug']),
            !empty($r['username'])                                => 'profile.php?u=' . rawurlencode((string) $r['username']),
            default                                               => 'notifications.php',
        };
    }

    /**
     * Avisos del usuario, del más reciente al más antiguo, paginados por id ("ver más" usa el último id).
     *
     * @param list<string>|null $types
     * @return array{items: list<array>, hasMore: bool, nextBefore: ?int}
     */
    public static function listFor(int $userId, ?array $types, ?int $beforeId, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $where = '';
        $params = [$userId];
        if ($types !== null && $types !== []) {
            $where .= ' AND n.type IN (' . implode(',', array_fill(0, count($types), '?')) . ')';
            array_push($params, ...$types);
        }
        if ($beforeId !== null && $beforeId > 0) {
            $where .= ' AND n.id < ?';
            $params[] = $beforeId;
        }

        $rows = self::fetchAll(
            self::LIST_SQL . " WHERE n.user_id = ? AND (n.actor_id IS NULL OR a.status = 'active')$where
             ORDER BY n.id DESC
             LIMIT " . ($limit + 1),
            $params
        );

        $hasMore = count($rows) > $limit;
        $items = array_map([self::class, 'present'], array_slice($rows, 0, $limit));
        return [
            'items'      => $items,
            'hasMore'    => $hasMore,
            'nextBefore' => $hasMore && $items !== [] ? (int) end($items)['id'] : null,
        ];
    }

    /** Aviso propio por id, para abrirlo. */
    public static function findFor(int $userId, int $id): ?array
    {
        return self::fetchOne(
            'SELECT n.id, n.type, n.post_id, n.comment_id, n.song_id, n.ref_id, a.username, cm.slug AS community_slug
             FROM notifications n
             LEFT JOIN users a ON a.id = n.actor_id
             LEFT JOIN communities cm ON cm.id = n.community_id
             WHERE n.id = ? AND n.user_id = ? LIMIT 1',
            [$id, $userId]
        );
    }

    public static function markRead(int $userId, int $id): void
    {
        self::execute('UPDATE notifications SET read_at = NOW() WHERE id = ? AND user_id = ? AND read_at IS NULL', [$id, $userId]);
    }

    /** Devuelve cuántos avisos se marcaron. */
    public static function markAllRead(int $userId): int
    {
        return self::execute('UPDATE notifications SET read_at = NOW() WHERE user_id = ? AND read_at IS NULL', [$userId]);
    }

    /** Página a la que lleva un aviso. */
    public static function targetUrl(array $n): string
    {
        if (in_array($n['type'] ?? '', self::SONG_TYPES, true)) {
            return url('artist.php', ['status' => match ($n['type']) {
                'song_approved' => 'published',
                'song_rejected' => 'rejected',
                default         => 'removed',
            }]);
        }
        if (in_array($n['type'] ?? '', self::WALLET_TYPES, true)) {
            return url('wallet.php');
        }
        if (($n['type'] ?? '') === 'collaborator_enabled') {
            return url('wallet.php', ['tab' => 'collaborator']);
        }
        if (($n['type'] ?? '') === 'gift') {
            return url('gifts.php', ['tab' => 'received']);
        }
        if (in_array($n['type'] ?? '', self::AD_TYPES, true)) {
            return url('ads.php') . (!empty($n['ref_id']) ? '#anuncio-' . (int) $n['ref_id'] : '');
        }
        if (in_array($n['type'] ?? '', ['warning', 'appeal_accepted', 'appeal_rejected'], true)) {
            return url('appeals.php') . (($n['type'] ?? '') === 'warning' && !empty($n['ref_id']) ? '#advertencia-' . (int) $n['ref_id'] : '');
        }
        if (!empty($n['post_id'])) {
            return url('post.php', ['id' => (int) $n['post_id']]) . (!empty($n['comment_id']) ? '#comentario-' . (int) $n['comment_id'] : '');
        }
        if (in_array($n['type'] ?? '', ['story_mention', 'new_story'], true) && !empty($n['username'])) {
            return url('stories.php', ['u' => $n['username']]);
        }
        if (!empty($n['community_slug'])) {
            return url('community.php', [
                'c'   => $n['community_slug'],
                'tab' => ($n['type'] ?? '') === 'community_request' ? 'requests' : null,
            ]);
        }
        if (!empty($n['username'])) {
            return url('profile.php', ['u' => $n['username']]);
        }
        return url('notifications.php');
    }

    private static function present(array $r): array
    {
        $isComment = in_array($r['type'], ['comment', 'reply'], true) || ($r['type'] === 'mention' && $r['comment_id'] !== null);
        $community = ['community' => (string) ($r['community_name'] ?? t('una comunidad'))];
        $song = ['song' => (string) ($r['song_title'] ?? t('tu canción'))];
        $money = ['amount' => \Trevix\Services\WalletService::money((int) ($r['wallet_amount'] ?? 0))];
        $adRefund = ['amount' => \Trevix\Services\WalletService::money((int) ($r['ad_refunded'] ?? 0))];
        $text = match ($r['type']) {
            'song_approved'      => t('aprobó tu canción «{song}»: ya está en la biblioteca de música.', $song),
            'song_rejected'      => t('no aprobó tu canción «{song}».', $song),
            'song_removed'       => t('retiró tu canción «{song}» de la biblioteca.', $song),
            'like'               => t('le gustó tu publicación.'),
            'comment'            => t('comentó tu publicación:'),
            'reply'              => t('respondió a tu comentario:'),
            'mention'            => $r['comment_id'] !== null ? t('te mencionó en un comentario:') : t('te mencionó en una publicación:'),
            'share'              => t('compartió tu publicación.'),
            'follow'             => t('comenzó a seguirte.'),
            'follow_accepted'    => t('aceptó tu solicitud de seguimiento.'),
            'community_request'  => t('solicitó unirse a {community}.', $community),
            'community_accepted' => t('te aceptó en {community}.', $community),
            'story_mention'      => t('te mencionó en su historia.'),
            'event_going'        => t('asistirá a tu evento.'),
            'featured'           => t('destacó tu publicación: aparece arriba en el inicio y en Destacados.'),
            'warning'            => t('te dio una advertencia. Revisa las normas de la comunidad o apélala si crees que es un error.'),
            'appeal_accepted'    => $r['appeal_type'] === 'suspension'
                ? t('aceptó tu apelación: levantamos la suspensión de tu cuenta.')
                : t('aceptó tu apelación: retiramos la advertencia.'),
            'appeal_rejected'    => t('revisó tu apelación y la sanción se mantiene.'),
            'verification_approved' => t('verificó tu cuenta: la insignia ya aparece junto a tu nombre.'),
            'verification_rejected' => t('no aprobó tu solicitud de verificado.'),
            'subscription'       => t('se suscribió a tu contenido de colaborador.'),
            'topup_approved'     => t('aprobó tu recarga de {amount}: ya está en tu monedero.', $money),
            'topup_rejected'     => t('no aprobó tu recarga de {amount}.', $money),
            'withdrawal_paid'    => t('pagó tu retiro de {amount}.', $money),
            'withdrawal_rejected' => t('no aprobó tu retiro de {amount}: el dinero volvió a tu monedero.', $money),
            'wallet_adjusted'    => (int) ($r['adjust_cents'] ?? 0) >= 0
                ? t('acreditó {amount} en tu monedero.', $money)
                : t('descontó {amount} de tu monedero.', $money),
            'collaborator_enabled' => t('habilitó tu cuenta como colaboradora: ya puedes activar tu plan de suscripción.'),
            'gift'               => (int) ($r['gift_earning'] ?? 0) > 0
                ? t('te envió un regalo: {gift}. Recibiste {amount} en tu monedero.', [
                    'gift' => (string) ($r['gift_name'] ?? ''), 'amount' => \Trevix\Services\WalletService::money((int) $r['gift_earning']),
                ])
                : t('te envió un regalo: {gift}.', ['gift' => (string) ($r['gift_name'] ?? '')]),
            'ad_approved'        => t('aprobó tu anuncio de OND-ADS: ya se está mostrando en el feed.'),
            'ad_rejected'        => ($r['ad_status'] ?? '') === 'removed'
                ? t('retiró tu anuncio de OND-ADS. Devolvimos {amount} a tu monedero.', $adRefund)
                : t('no aprobó tu anuncio de OND-ADS. Devolvimos {amount} a tu monedero.', $adRefund),
            'ad_finished'        => (int) ($r['ad_refunded'] ?? 0) > 0
                ? t('terminó de mostrar tu anuncio de OND-ADS: llegó a {n} personas. Devolvimos {amount} por los días con menos alcance.', $adRefund + ['n' => (int) ($r['ad_impressions'] ?? 0)])
                : t('terminó de mostrar tu anuncio de OND-ADS: llegó a {n} personas.', ['n' => (int) ($r['ad_impressions'] ?? 0)]),
            'new_post'           => t('publicó algo nuevo.'),
            'new_note'           => t('compartió una nota.'),
            'new_story'          => t('subió una historia.'),
            default              => t('tiene actividad nueva para ti.'),
        };
        $excerpt = $isComment ? $r['comment_body'] : (in_array($r['type'], ['mention', 'new_post'], true) ? $r['post_body'] : null);
        if ($r['type'] === 'new_note') {
            $excerpt = $r['note_body'] ?? null;
        }
        if (in_array($r['type'], ['song_rejected', 'song_removed'], true)) {
            $excerpt = $r['song_note'] !== null ? t('Motivo: {reason}', ['reason' => $r['song_note']]) : null;
        } elseif ($r['type'] === 'warning') {
            $excerpt = $r['warning_reason'] !== null ? t('Motivo: {reason}', ['reason' => $r['warning_reason']]) : null;
        } elseif ($r['type'] === 'verification_rejected') {
            $excerpt = $r['verification_note'] !== null ? t('Motivo: {reason}', ['reason' => $r['verification_note']]) : null;
        } elseif (in_array($r['type'], ['appeal_accepted', 'appeal_rejected'], true)) {
            $excerpt = !empty($r['appeal_note']) ? t('Nota del equipo: {note}', ['note' => $r['appeal_note']]) : null;
        } elseif (in_array($r['type'], ['topup_rejected', 'withdrawal_rejected', 'wallet_adjusted'], true)) {
            $excerpt = !empty($r['wallet_note']) ? t('Motivo: {reason}', ['reason' => $r['wallet_note']]) : null;
        } elseif ($r['type'] === 'ad_rejected') {
            $excerpt = !empty($r['ad_note']) ? t('Motivo: {reason}', ['reason' => $r['ad_note']]) : null;
        }

        return [
            'id'         => (int) $r['id'],
            'type'       => $r['type'],
            'actor'      => $r['actor_id'] !== null ? [
                'id'           => (int) $r['actor_id'],
                'username'     => $r['username'],
                'display_name' => $r['display_name'],
                'avatar_path'  => $r['avatar_path'],
                'is_verified'  => (int) $r['is_verified'],
                'is_private'   => (int) $r['is_private'],
            ] : null,
            'text'       => $text,
            'excerpt'    => $excerpt !== null && $excerpt !== '' ? mb_strimwidth(preg_replace('/\s+/u', ' ', plain_body($excerpt)), 0, 140, '…') : null,
            'thumb'      => $r['thumb'],
            'post_id'    => $r['post_id'] !== null ? (int) $r['post_id'] : null,
            'comment_id' => $r['comment_id'] !== null ? (int) $r['comment_id'] : null,
            'community_id' => $r['community_id'] !== null ? (int) $r['community_id'] : null,
            'song_id'    => $r['song_id'] !== null ? (int) $r['song_id'] : null,
            'read'       => $r['read_at'] !== null,
            'created_at' => $r['created_at'],
            'url'        => url('notifications.php', ['open' => (int) $r['id']]),
        ];
    }
}
