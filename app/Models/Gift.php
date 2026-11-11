<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Regalos: categorías y catálogo (los edita la administración), unidades compradas que la persona guarda para
 * enviar después y regalos enviados. Cada envío guarda una copia del nombre y la imagen del regalo.
 */
final class Gift extends Model
{
    public const KINDS = ['sticker' => 'Sticker', 'gif' => 'GIF'];

    public const CONTEXTS = ['profile', 'message', 'post', 'story'];

    private const COLUMNS = 'g.id, g.category_id, g.name, g.kind, g.source, g.media_path, g.giphy_id, g.media_url, g.width, g.height,
        g.price_cents, g.position, g.is_active, g.created_at';

    // -------------------------------------------------------------------------
    // Categorías
    // -------------------------------------------------------------------------

    public static function categories(bool $onlyActive = true): array
    {
        return self::fetchAll(
            'SELECT c.id, c.name, c.position, c.is_active,
                    (SELECT COUNT(*) FROM gifts g WHERE g.category_id = c.id' . ($onlyActive ? ' AND g.is_active = 1' : '') . ') AS gifts_count
             FROM gift_categories c' . ($onlyActive ? ' WHERE c.is_active = 1' : '') . ' ORDER BY c.position, c.id'
        );
    }

    public static function category(int $id): ?array
    {
        return self::fetchOne('SELECT id, name, position, is_active FROM gift_categories WHERE id = ?', [$id]);
    }

    public static function saveCategory(?int $id, string $name, int $position, bool $active): int
    {
        if ($id !== null) {
            self::execute('UPDATE gift_categories SET name = ?, position = ?, is_active = ? WHERE id = ?', [$name, $position, $active ? 1 : 0, $id]);
            return $id;
        }
        self::execute('INSERT INTO gift_categories (name, position, is_active) VALUES (?, ?, ?)', [$name, $position, $active ? 1 : 0]);
        return (int) self::db()->lastInsertId();
    }

    /** Los regalos de la categoría quedan sin categoría («Otros»). */
    public static function deleteCategory(int $id): bool
    {
        return self::execute('DELETE FROM gift_categories WHERE id = ?', [$id]) > 0;
    }

    // -------------------------------------------------------------------------
    // Catálogo
    // -------------------------------------------------------------------------

    /** Regalos a la venta (activos y de una categoría activa o sin categoría), en el orden del panel. */
    public static function catalog(): array
    {
        return self::fetchAll(
            'SELECT ' . self::COLUMNS . ', c.name AS category_name
             FROM gifts g LEFT JOIN gift_categories c ON c.id = g.category_id
             WHERE g.is_active = 1 AND (g.category_id IS NULL OR c.is_active = 1)
             ORDER BY c.position IS NULL, c.position, c.id, g.position, g.price_cents, g.id'
        );
    }

    /** Todos los regalos para el panel, con cuántas veces se vendieron. */
    public static function adminList(): array
    {
        return self::fetchAll(
            'SELECT ' . self::COLUMNS . ', c.name AS category_name,
                    (SELECT COUNT(*) FROM gift_sends s WHERE s.gift_id = g.id) AS sends_count,
                    (SELECT COUNT(*) FROM gift_inventory i WHERE i.gift_id = g.id) AS stored_count
             FROM gifts g LEFT JOIN gift_categories c ON c.id = g.category_id
             ORDER BY c.position IS NULL, c.position, c.id, g.position, g.id'
        );
    }

    public static function find(int $id, bool $forUpdate = false): ?array
    {
        return self::fetchOne('SELECT ' . self::COLUMNS . ' FROM gifts g WHERE g.id = ?' . ($forUpdate ? ' FOR UPDATE' : ''), [$id]);
    }

    /** @param array{category_id:?int, name:string, kind:string, source:string, media_path:?string, giphy_id:?string, media_url:?string, width:int, height:int, price_cents:int, position:int, active:bool} $f */
    public static function save(?int $id, array $f): int
    {
        $values = [
            $f['category_id'], $f['name'], $f['kind'], $f['source'], $f['media_path'], $f['giphy_id'], $f['media_url'],
            $f['width'], $f['height'], $f['price_cents'], $f['position'], $f['active'] ? 1 : 0,
        ];
        if ($id !== null) {
            self::execute(
                'UPDATE gifts SET category_id = ?, name = ?, kind = ?, source = ?, media_path = ?, giphy_id = ?, media_url = ?, width = ?,
                        height = ?, price_cents = ?, position = ?, is_active = ? WHERE id = ?',
                [...$values, $id]
            );
            return $id;
        }
        self::execute(
            'INSERT INTO gifts (category_id, name, kind, source, media_path, giphy_id, media_url, width, height, price_cents, position, is_active)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            $values
        );
        return (int) self::db()->lastInsertId();
    }

    /** Un regalo que ya se compró no se borra (los envíos y el inventario lo usan): solo se puede ocultar. */
    public static function wasSold(int $id): bool
    {
        return (bool) self::fetchValue(
            'SELECT EXISTS (SELECT 1 FROM gift_sends WHERE gift_id = ?) OR EXISTS (SELECT 1 FROM gift_inventory WHERE gift_id = ?)',
            [$id, $id]
        );
    }

    public static function delete(int $id): bool
    {
        return self::execute('DELETE FROM gifts WHERE id = ?', [$id]) > 0;
    }

    /** Ruta subida o URL de GIPHY del regalo (lo que se copia en cada envío). */
    public static function media(array $gift): string
    {
        return $gift['source'] === 'giphy' ? (string) $gift['media_url'] : (string) $gift['media_path'];
    }

    // -------------------------------------------------------------------------
    // Inventario («Mis regalos»)
    // -------------------------------------------------------------------------

    public static function addToInventory(int $userId, int $giftId, int $priceCents, int $quantity): void
    {
        $rows = implode(',', array_fill(0, $quantity, '(?, ?, ?)'));
        $params = [];
        for ($i = 0; $i < $quantity; $i++) {
            array_push($params, $userId, $giftId, $priceCents);
        }
        self::execute("INSERT INTO gift_inventory (user_id, gift_id, price_cents) VALUES $rows", $params);
    }

    /** Unidad más antigua guardada de ese regalo, bloqueada para enviarla. */
    public static function takeFromInventory(int $userId, int $giftId): ?array
    {
        $unit = self::fetchOne(
            'SELECT id, price_cents FROM gift_inventory WHERE user_id = ? AND gift_id = ? ORDER BY id LIMIT 1 FOR UPDATE',
            [$userId, $giftId]
        );
        if ($unit === null) {
            return null;
        }
        self::execute('DELETE FROM gift_inventory WHERE id = ?', [(int) $unit['id']]);
        return $unit;
    }

    /** Regalos guardados, agrupados, con cuántas unidades hay de cada uno. */
    public static function inventory(int $userId): array
    {
        return self::fetchAll(
            'SELECT ' . self::COLUMNS . ', COUNT(i.id) AS quantity, MIN(i.price_cents) AS paid_min, MAX(i.price_cents) AS paid_max
             FROM gift_inventory i JOIN gifts g ON g.id = i.gift_id
             WHERE i.user_id = ?
             GROUP BY g.id
             ORDER BY MAX(i.id) DESC',
            [$userId]
        );
    }

    public static function inventoryCount(int $userId): int
    {
        return (int) self::fetchValue('SELECT COUNT(*) FROM gift_inventory WHERE user_id = ?', [$userId]);
    }

    // -------------------------------------------------------------------------
    // Envíos
    // -------------------------------------------------------------------------

    /** @param array{sender_id:int, recipient_id:int, gift:array, price_cents:int, commission_cents:int, context:string, post_id:?int, story_id:?int, from_inventory:bool} $s */
    public static function createSend(array $s): int
    {
        $gift = $s['gift'];
        self::execute(
            'INSERT INTO gift_sends (sender_id, recipient_id, gift_id, gift_name, gift_kind, media, width, height, price_cents, commission_cents,
                                     earning_cents, context, post_id, story_id, from_inventory)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $s['sender_id'], $s['recipient_id'], (int) $gift['id'], (string) $gift['name'], (string) $gift['kind'], self::media($gift),
                (int) $gift['width'], (int) $gift['height'], $s['price_cents'], $s['commission_cents'],
                $s['price_cents'] - $s['commission_cents'], $s['context'], $s['post_id'], $s['story_id'], $s['from_inventory'] ? 1 : 0,
            ]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function setSendMessage(int $sendId, int $messageId): void
    {
        self::execute('UPDATE gift_sends SET message_id = ? WHERE id = ?', [$messageId, $sendId]);
    }

    public static function send(int $id): ?array
    {
        return self::fetchOne('SELECT * FROM gift_sends WHERE id = ?', [$id]);
    }

    /** Copias de los regalos de los mensajes del chat, por id de envío. */
    public static function sendsFor(array $ids): array
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids))));
        if ($ids === []) {
            return [];
        }
        $out = [];
        foreach (self::fetchAll(
            'SELECT id, gift_name, gift_kind, media, width, height, price_cents, earning_cents FROM gift_sends WHERE id IN ('
            . implode(',', array_fill(0, count($ids), '?')) . ')',
            $ids
        ) as $row) {
            $out[(int) $row['id']] = $row;
        }
        return $out;
    }

    /**
     * Regalos recibidos (solo los ve quien los recibió) o enviados, del más reciente al más antiguo, paginados por id.
     *
     * @param 'received'|'sent' $direction
     */
    public static function history(int $userId, string $direction, int $before, int $limit): array
    {
        $limit = max(1, min(50, $limit));
        [$mine, $other] = $direction === 'sent' ? ['sender_id', 'recipient_id'] : ['recipient_id', 'sender_id'];
        $rows = self::fetchAll(
            "SELECT s.id, s.gift_id, s.gift_name, s.gift_kind, s.media, s.width, s.height, s.price_cents, s.commission_cents, s.earning_cents,
                    s.context, s.post_id, s.story_id, s.from_inventory, s.created_at,
                    u.id AS user_id, u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS user_status
             FROM gift_sends s LEFT JOIN users u ON u.id = s.$other
             WHERE s.$mine = ?" . ($before > 0 ? ' AND s.id < ?' : '') . '
             ORDER BY s.id DESC LIMIT ' . ($limit + 1),
            $before > 0 ? [$userId, $before] : [$userId]
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Totales del panel: ventas, comisiones y lo acreditado a quienes recibieron. */
    public static function totals(): array
    {
        $row = self::fetchOne(
            "SELECT (SELECT COALESCE(SUM(-amount_cents), 0) FROM wallet_transactions WHERE type = 'gift_purchase') AS sales,
                    (SELECT COALESCE(SUM(commission_cents), 0) FROM gift_sends) AS commissions,
                    (SELECT COALESCE(SUM(earning_cents), 0) FROM gift_sends) AS earnings,
                    (SELECT COUNT(*) FROM gift_sends) AS sends,
                    (SELECT COUNT(*) FROM gift_inventory) AS stored"
        );
        return array_map('intval', $row ?? []);
    }
}
