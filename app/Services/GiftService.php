<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use RuntimeException;
use Trevix\Core\ActionError;
use Trevix\Core\Config;
use Trevix\Core\Database;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\Block;
use Trevix\Models\Conversation;
use Trevix\Models\Gift;
use Trevix\Models\Notification;
use Trevix\Models\Post;
use Trevix\Models\RateLimit;
use Trevix\Models\Story;
use Trevix\Models\User;
use Trevix\Models\Wallet;

/**
 * Regalos (web y API): el catálogo lo arma la administración; se pagan con el saldo del monedero, se envían al
 * momento o se guardan en «Mis regalos» para enviarlos después. Quien recibe gana el valor del regalo menos la
 * comisión de TREVIX (panel › Regalos), y ese dinero se puede retirar como lo ganado por suscripciones.
 * Los regalos recibidos solo los ve quien los recibe.
 */
final class GiftService
{
    public static function commissionPct(): int
    {
        return max(0, min(90, (int) AppSetting::get('gift_commission')));
    }

    public static function maxQuantity(): int
    {
        return max(1, (int) Config::get('app.limits.gift_buy_max', 20));
    }

    /** URL absoluta de la imagen de un regalo (archivo subido o GIPHY). */
    public static function mediaUrl(string $media): string
    {
        return preg_match('#^https://#', $media) ? $media : absolute_url($media);
    }

    public static function present(array $g): array
    {
        return [
            'id'          => (int) $g['id'],
            'name'        => (string) $g['name'],
            'kind'        => $g['kind'] === 'gif' ? 'gif' : 'sticker',
            'media_url'   => self::mediaUrl(Gift::media($g)),
            'width'       => (int) $g['width'],
            'height'      => (int) $g['height'],
            'price'       => WalletService::amount((int) $g['price_cents']),
            'category_id' => $g['category_id'] !== null ? (int) $g['category_id'] : null,
            'is_active'   => (bool) $g['is_active'],
        ];
    }

    /** Catálogo agrupado por categoría (los regalos sin categoría van al final, en «Otros»). */
    public static function catalog(): array
    {
        $groups = [];
        foreach (Gift::catalog() as $g) {
            $key = $g['category_id'] !== null ? (int) $g['category_id'] : 0;
            $groups[$key] ??= ['id' => $key, 'name' => $key > 0 ? (string) $g['category_name'] : t('Otros'), 'gifts' => []];
            $groups[$key]['gifts'][] = self::present($g);
        }
        return array_values($groups);
    }

    /** Lo guardado en «Mis regalos»: cada regalo con cuántas unidades quedan. */
    public static function inventory(int $userId): array
    {
        return array_map(static fn (array $g): array => self::present($g) + [
            'quantity' => (int) $g['quantity'],
            // Al enviarlo, quien lo recibe gana lo que se pagó por esa unidad menos la comisión.
            'paid'     => WalletService::amount((int) $g['paid_min']),
        ], Gift::inventory($userId));
    }

    /** Resumen para la pantalla de regalos: saldo, comisión, catálogo e inventario. */
    public static function summary(int $userId): array
    {
        return [
            'balance'    => WalletService::amount(Wallet::balance($userId)),
            'commission' => self::commissionPct(),
            'max_quantity' => self::maxQuantity(),
            'categories' => self::catalog(),
            'inventory'  => self::inventory($userId),
        ];
    }

    /**
     * Compra $quantity unidades para guardarlas en «Mis regalos».
     *
     * @return array{message:string, balance:array, inventory:list<array>}
     */
    public static function buy(array $user, int $giftId, int $quantity): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        if ($quantity < 1 || $quantity > self::maxQuantity()) {
            throw ActionError::field('quantity', t('Puedes comprar de 1 a {n} unidades a la vez.', ['n' => self::maxQuantity()]));
        }
        Guard::rateLimit('gift_buy', (string) $uid, 'Hiciste muchas compras seguidas. Inténtalo en {min} min.');
        RateLimit::hit('gift_buy', (string) $uid);

        $result = Database::transaction(static function () use ($uid, $giftId, $quantity): array {
            $gift = Gift::find($giftId);
            if ($gift === null || !(bool) $gift['is_active']) {
                throw new ActionError('Este regalo ya no está a la venta.', 404);
            }
            $price = (int) $gift['price_cents'];
            $total = $price * $quantity;
            Wallet::lock($uid);
            $note = $quantity > 1 ? $gift['name'] . ' ×' . $quantity : (string) $gift['name'];
            $balance = Wallet::apply($uid, -$total, 'gift_purchase', [], mb_substr($note, 0, 255));
            if ($balance === null) {
                throw new ActionError(t('Tu saldo no alcanza: cuesta {price}. Recarga tu monedero.', ['price' => WalletService::money($total)]), 402);
            }
            Gift::addToInventory($uid, $giftId, $price, $quantity);
            return ['gift' => $gift, 'balance' => $balance];
        });
        return [
            'message'   => $quantity > 1
                ? t('Guardaste {n} × {gift} en Mis regalos.', ['n' => $quantity, 'gift' => $result['gift']['name']])
                : t('Guardaste {gift} en Mis regalos.', ['gift' => $result['gift']['name']]),
            'balance'   => WalletService::amount($result['balance']),
            'inventory' => self::inventory($uid),
        ];
    }

    /**
     * Envía un regalo: comprándolo en el momento ($fromInventory = false) o usando una unidad guardada.
     * $context dice desde dónde: el perfil, el chat privado (queda como mensaje), una publicación o reel ($refId =
     * la publicación) o una historia ($refId = la historia). Quien recibe se deduce de la publicación o la historia.
     *
     * @return array{message:string, send:array, balance:array, conversation_id:?int}
     */
    public static function send(array $user, string $to, int $giftId, bool $fromInventory, string $context, int $refId = 0): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        if (!in_array($context, Gift::CONTEXTS, true)) {
            $context = 'profile';
        }
        [$recipient, $postId, $storyId] = self::recipient($uid, $to, $context, $refId);
        $rid = (int) $recipient['id'];
        $conversationId = null;
        if ($context === 'message') {
            $conversationId = Conversation::findDirectId($uid, $rid);
            $reason = Conversation::cannotMessage($uid, $recipient, $conversationId);
            if ($reason !== null) {
                throw new ActionError($reason, 403);
            }
        }
        Guard::rateLimit('gift_send', (string) $uid, 'Enviaste muchos regalos seguidos. Inténtalo en {min} min.');
        RateLimit::hit('gift_send', (string) $uid);
        $pct = self::commissionPct();

        $result = Database::transaction(static function () use ($uid, $rid, $giftId, $fromInventory, $context, $postId, $storyId, $pct, $conversationId): array {
            $gift = Gift::find($giftId);
            if ($gift === null) {
                throw new ActionError('Este regalo ya no está disponible.', 404);
            }
            Wallet::lock($uid, $rid);
            if ($fromInventory) {
                $unit = Gift::takeFromInventory($uid, $giftId);
                if ($unit === null) {
                    throw new ActionError('Ya no te quedan unidades de este regalo. Cómpralo para enviarlo.', 409);
                }
                $price = (int) $unit['price_cents'];
            } else {
                if (!(bool) $gift['is_active']) {
                    throw new ActionError('Este regalo ya no está a la venta.', 404);
                }
                $price = (int) $gift['price_cents'];
            }
            $commission = intdiv($price * $pct + 50, 100);
            $sendId = Gift::createSend([
                'sender_id' => $uid, 'recipient_id' => $rid, 'gift' => $gift, 'price_cents' => $price, 'commission_cents' => $commission,
                'context' => $context, 'post_id' => $postId, 'story_id' => $storyId, 'from_inventory' => $fromInventory,
            ]);
            $balance = $fromInventory
                ? Wallet::balance($uid)
                : Wallet::apply($uid, -$price, 'gift_purchase', ['counterpart_id' => $rid], mb_substr((string) $gift['name'], 0, 255));
            if ($balance === null) {
                throw new ActionError(t('Tu saldo no alcanza: el regalo cuesta {price}. Recarga tu monedero.', ['price' => WalletService::money($price)]), 402);
            }
            if ($price - $commission > 0) {
                Wallet::apply($rid, $price - $commission, 'gift_received', ['counterpart_id' => $uid], mb_substr((string) $gift['name'], 0, 255));
            }
            $sent = null;
            if ($context === 'message') {
                $sent = Conversation::send($uid, $rid, $conversationId, '🎁 ' . $gift['name'], null, null, null, null, [
                    'context'      => 'gift',
                    'gift_send_id' => $sendId,
                ]);
                Gift::setSendMessage($sendId, $sent[1]);
            }
            return ['send_id' => $sendId, 'balance' => $balance, 'conversation_id' => $sent[0] ?? null];
        });
        if ($context !== 'message') {
            Notification::notifyGift($rid, $uid, $result['send_id']);
        }
        $send = Gift::send($result['send_id']);
        return [
            'message'         => t('Enviaste {gift} a {name}.', ['gift' => $send['gift_name'], 'name' => $recipient['display_name']]),
            'send'            => self::presentSend($send + [
                'user_id' => $rid, 'username' => $recipient['username'], 'display_name' => $recipient['display_name'],
                'avatar_path' => $recipient['avatar_path'], 'is_verified' => $recipient['is_verified'], 'user_status' => 'active',
            ], 'sent'),
            'balance'         => WalletService::amount((int) $result['balance']),
            'conversation_id' => $result['conversation_id'],
        ];
    }

    /**
     * Cuenta que recibe el regalo y la publicación o historia desde la que se envía (ya comprobadas).
     *
     * @return array{0: array, 1: ?int, 2: ?int}
     */
    private static function recipient(int $uid, string $to, string $context, int $refId): array
    {
        $postId = null;
        $storyId = null;
        if ($context === 'post') {
            $post = $refId > 0 ? Post::findVisible($refId, $uid) : null;
            if ($post === null) {
                throw new ActionError('Esta publicación ya no está disponible.', 404);
            }
            $recipientId = (int) $post['user_id'];
            $postId = $refId;
        } elseif ($context === 'story') {
            $story = $refId > 0 ? Story::findVisible($refId, $uid) : null;
            if ($story === null) {
                throw new ActionError('Esta historia ya no está disponible.', 404);
            }
            $recipientId = (int) $story['user_id'];
            $storyId = $refId;
        } else {
            $found = User::findByUsername(mb_strtolower(trim(ltrim(trim($to), '@'))));
            $recipientId = $found !== null ? (int) $found['id'] : 0;
        }
        if ($recipientId === $uid) {
            throw new ActionError('No puedes enviarte regalos a ti mismo.', 422);
        }
        $recipient = $recipientId > 0 ? User::findActiveById($recipientId) : null;
        if ($recipient === null || Block::exists($uid, $recipientId) || Block::exists($recipientId, $uid)) {
            throw new ActionError('Esta cuenta no está disponible.', 404);
        }
        return [$recipient, $postId, $storyId];
    }

    /** @param 'received'|'sent' $direction */
    public static function history(int $userId, string $direction, int $before): array
    {
        $page = Gift::history($userId, $direction, $before, 30);
        $items = array_map(static fn (array $r): array => self::presentSend($r, $direction), $page['items']);
        return ['items' => $items, 'next' => $page['hasMore'] && $items !== [] ? ['before' => (int) end($items)['id']] : null];
    }

    /** Envío para «Recibidos» (con lo que se ganó) o «Enviados» (con lo que se pagó). */
    public static function presentSend(array $s, string $direction): array
    {
        $available = $s['user_id'] !== null && ($s['user_status'] ?? 'active') === 'active';
        return [
            'id'         => (int) $s['id'],
            'gift'       => [
                'id'        => $s['gift_id'] !== null ? (int) $s['gift_id'] : null,
                'name'      => (string) $s['gift_name'],
                'kind'      => $s['gift_kind'] === 'gif' ? 'gif' : 'sticker',
                'media_url' => self::mediaUrl((string) $s['media']),
                'width'     => (int) $s['width'],
                'height'    => (int) $s['height'],
            ],
            'user'       => $available ? [
                'id'           => (int) $s['user_id'],
                'username'     => (string) $s['username'],
                'display_name' => (string) $s['display_name'],
                'avatar_path'  => $s['avatar_path'],
                'is_verified'  => !empty($s['is_verified']),
            ] : null,
            'amount'     => WalletService::amount($direction === 'sent' ? (int) $s['price_cents'] : (int) $s['earning_cents']),
            'context'    => (string) $s['context'],
            'post_id'    => $s['post_id'] !== null ? (int) $s['post_id'] : null,
            'from_inventory' => (bool) $s['from_inventory'],
            'created_at' => $s['created_at'],
        ];
    }

    /** Regalo de un mensaje del chat (Message::withAttachments). */
    public static function presentMessageGift(array $s): array
    {
        return [
            'name'      => (string) $s['gift_name'],
            'kind'      => $s['gift_kind'] === 'gif' ? 'gif' : 'sticker',
            'media_url' => self::mediaUrl((string) $s['media']),
            'width'     => (int) $s['width'],
            'height'    => (int) $s['height'],
        ];
    }

    // -------------------------------------------------------------------------
    // Panel › Regalos
    // -------------------------------------------------------------------------

    public static function saveCategory(array $staff, ?int $id, string $name, int $position, bool $active): void
    {
        WalletService::assertAdmin($staff);
        $name = trim((string) preg_replace('/\s+/u', ' ', $name));
        if (mb_strlen($name) < 2 || mb_strlen($name) > 60) {
            throw new DomainException('El nombre de la categoría debe tener entre 2 y 60 caracteres.');
        }
        if ($id !== null && Gift::category($id) === null) {
            throw new DomainException('Esa categoría ya no existe.');
        }
        $savedId = Gift::saveCategory($id, $name, max(0, min(999, $position)), $active);
        AuditLog::record((int) $staff['id'], $id === null ? 'gifts.category_create' : 'gifts.category_update', 'gift_category', $savedId, ['name' => $name]);
    }

    public static function deleteCategory(array $staff, int $id): void
    {
        WalletService::assertAdmin($staff);
        $category = Gift::category($id) ?? throw new DomainException('Esa categoría ya no existe.');
        Gift::deleteCategory($id);
        AuditLog::record((int) $staff['id'], 'gifts.category_delete', 'gift_category', $id, ['name' => $category['name']]);
    }

    /**
     * Agrega o edita un regalo. La imagen es un archivo subido (campo «media») o un GIF/sticker de GIPHY (su id o
     * enlace en «giphy»); al editar sin enviar ninguno se conserva la actual.
     *
     * @param array{name:string, category_id:int, kind:string, price:string, position:int, active:bool, giphy:string} $in
     */
    public static function saveGift(array $staff, ?int $id, array $in): array
    {
        WalletService::assertAdmin($staff);
        $current = $id !== null ? (Gift::find($id) ?? throw new DomainException('Ese regalo ya no existe.')) : null;
        $name = trim((string) preg_replace('/\s+/u', ' ', $in['name']));
        if (mb_strlen($name) < 2 || mb_strlen($name) > 60) {
            throw new DomainException('El nombre del regalo debe tener entre 2 y 60 caracteres.');
        }
        $categoryId = $in['category_id'] > 0 ? $in['category_id'] : null;
        if ($categoryId !== null && Gift::category($categoryId) === null) {
            throw new DomainException('Elige una categoría válida.');
        }
        $kind = isset(Gift::KINDS[$in['kind']]) ? $in['kind'] : 'sticker';
        $price = WalletService::parseAmount($in['price']);
        if ($price === null || $price < 1 || $price > 100000) {
            throw new DomainException('Escribe el costo en dólares, entre 0.01 y 1000 (por ejemplo 1 o 2.50).');
        }

        $media = $current !== null ? [
            'source' => $current['source'], 'media_path' => $current['media_path'], 'giphy_id' => $current['giphy_id'],
            'media_url' => $current['media_url'], 'width' => (int) $current['width'], 'height' => (int) $current['height'],
        ] : null;
        try {
            $upload = ImageUpload::storeGift('media');
        } catch (RuntimeException $e) {
            throw new DomainException($e->getMessage());
        }
        $giphyId = self::giphyId($in['giphy']);
        if ($upload !== null && $giphyId !== '') {
            ImageUpload::deleteGift($upload['path']);
            throw new DomainException('Sube un archivo o elige uno de GIPHY, no los dos.');
        }
        if ($upload !== null) {
            $media = ['source' => 'upload', 'media_path' => $upload['path'], 'giphy_id' => null, 'media_url' => null,
                'width' => $upload['width'], 'height' => $upload['height']];
        } elseif ($giphyId !== '') {
            try {
                $gif = Giphy::resolve($giphyId, $kind);
            } catch (ActionError $e) {
                throw new DomainException($e->getMessage());
            }
            if ($gif === null) {
                throw new DomainException('Ese GIF de GIPHY no está disponible.');
            }
            $media = ['source' => 'giphy', 'media_path' => null, 'giphy_id' => (string) $gif['gif_id'], 'media_url' => (string) $gif['gif_url'],
                'width' => (int) $gif['gif_width'], 'height' => (int) $gif['gif_height']];
        }
        if ($media === null) {
            throw new DomainException('Sube el GIF o sticker del regalo (GIF, PNG o WEBP) o elige uno de GIPHY.');
        }

        try {
            $savedId = Gift::save($id, [
                'category_id' => $categoryId, 'name' => $name, 'kind' => $kind, 'price_cents' => $price,
                'position' => max(0, min(999, $in['position'])), 'active' => $in['active'],
            ] + $media);
        } catch (\Throwable $e) {
            if ($upload !== null) {
                ImageUpload::deleteGift($upload['path']);
            }
            throw $e;
        }
        // La imagen anterior se borra solo si nadie compró el regalo (los envíos guardan la misma ruta).
        if ($current !== null && $current['media_path'] !== null && $current['media_path'] !== $media['media_path'] && !Gift::wasSold($savedId)) {
            ImageUpload::deleteGift((string) $current['media_path']);
        }
        AuditLog::record((int) $staff['id'], $id === null ? 'gifts.create' : 'gifts.update', 'gift', $savedId, [
            'name' => $name, 'price' => WalletService::money($price), 'active' => $in['active'],
        ]);
        return Gift::find($savedId) ?? [];
    }

    /** Un regalo que nunca se vendió se borra; si ya se vendió, se oculta del catálogo (los envíos lo conservan). */
    public static function deleteGift(array $staff, int $id): bool
    {
        WalletService::assertAdmin($staff);
        $gift = Gift::find($id) ?? throw new DomainException('Ese regalo ya no existe.');
        if (Gift::wasSold($id)) {
            Gift::save($id, [
                'category_id' => $gift['category_id'] !== null ? (int) $gift['category_id'] : null, 'name' => $gift['name'], 'kind' => $gift['kind'],
                'source' => $gift['source'], 'media_path' => $gift['media_path'], 'giphy_id' => $gift['giphy_id'], 'media_url' => $gift['media_url'],
                'width' => (int) $gift['width'], 'height' => (int) $gift['height'], 'price_cents' => (int) $gift['price_cents'],
                'position' => (int) $gift['position'], 'active' => false,
            ]);
            AuditLog::record((int) $staff['id'], 'gifts.update', 'gift', $id, ['name' => $gift['name'], 'active' => false]);
            return false;
        }
        Gift::delete($id);
        ImageUpload::deleteGift($gift['media_path']);
        AuditLog::record((int) $staff['id'], 'gifts.delete', 'gift', $id, ['name' => $gift['name']]);
        return true;
    }

    /** Id de GIPHY a partir del id o de un enlace (giphy.com/gifs/nombre-ID, media.giphy.com/media/ID/…). */
    public static function giphyId(string $text): string
    {
        $text = trim($text);
        if ($text === '') {
            return '';
        }
        if (preg_match('#giphy\.com/(?:media|stickers|gifs|embed)/(?:v1\.[^/]+/)?(?:[^/]*-)?([A-Za-z0-9]{6,64})(?:[/?\#]|$)#', $text, $m)) {
            return $m[1];
        }
        return preg_match('/^[A-Za-z0-9]{1,64}$/', $text) ? $text : '!';
    }
}
