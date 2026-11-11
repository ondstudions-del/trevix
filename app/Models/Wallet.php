<?php
declare(strict_types=1);

namespace Trevix\Models;

/**
 * Monedero en centavos de dólar: saldo por persona, movimientos, recargas con comprobante, retiros y medios de pago.
 * El saldo solo cambia con apply(), siempre dentro de una transacción y con la fila bloqueada (FOR UPDATE), y cada
 * cambio deja un movimiento con el saldo resultante.
 */
final class Wallet extends Model
{
    public const TOPUP_STATUSES = [
        'pending'   => 'En revisión',
        'approved'  => 'Aprobada',
        'rejected'  => 'Rechazada',
        'cancelled' => 'Cancelada',
    ];

    public const WITHDRAWAL_STATUSES = [
        'pending'   => 'En revisión',
        'paid'      => 'Pagado',
        'rejected'  => 'Rechazado',
        'cancelled' => 'Cancelado',
    ];

    public const TYPES = [
        'topup'             => 'Recarga',
        'subscription'      => 'Suscripción',
        'earning'           => 'Ingreso por suscripción',
        'withdrawal'        => 'Retiro',
        'withdrawal_refund' => 'Retiro devuelto',
        'adjustment'        => 'Ajuste',
        'gift_purchase'     => 'Compra de regalos',
        'gift_received'     => 'Regalo recibido',
    ];

    public static function balance(int $userId): int
    {
        return (int) (self::fetchValue('SELECT balance_cents FROM wallets WHERE user_id = ?', [$userId]) ?: 0);
    }

    /**
     * Bloquea los monederos de las cuentas (creándolos si faltan) en orden de id, para que dos operaciones
     * cruzadas no se bloqueen entre sí. Debe llamarse dentro de una transacción.
     */
    public static function lock(int ...$userIds): void
    {
        $ids = array_values(array_unique(array_filter($userIds, static fn (int $id) => $id > 0)));
        sort($ids);
        foreach ($ids as $id) {
            self::execute('INSERT INTO wallets (user_id, balance_cents) VALUES (?, 0) ON DUPLICATE KEY UPDATE user_id = user_id', [$id]);
        }
        if ($ids !== []) {
            self::fetchAll(
                'SELECT user_id FROM wallets WHERE user_id IN (' . implode(',', array_fill(0, count($ids), '?')) . ') ORDER BY user_id FOR UPDATE',
                $ids
            );
        }
    }

    /**
     * Suma $amount (negativo = resta) al saldo y registra el movimiento. Devuelve el saldo nuevo, o null si el
     * saldo no alcanza. Llamar dentro de una transacción después de lock().
     *
     * @param array{counterpart_id?:int, topup_id?:int, withdrawal_id?:int, subscription_id?:int} $refs
     */
    public static function apply(int $userId, int $amount, string $type, array $refs = [], ?string $note = null): ?int
    {
        self::lock($userId);
        $balance = (int) self::fetchValue('SELECT balance_cents FROM wallets WHERE user_id = ? FOR UPDATE', [$userId]);
        $new = $balance + $amount;
        if ($new < 0) {
            return null;
        }
        self::execute('UPDATE wallets SET balance_cents = ? WHERE user_id = ?', [$new, $userId]);
        self::execute(
            'INSERT INTO wallet_transactions (user_id, type, amount_cents, balance_after_cents, counterpart_id, topup_id, withdrawal_id, subscription_id, note)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $userId, $type, $amount, $new,
                $refs['counterpart_id'] ?? null, $refs['topup_id'] ?? null, $refs['withdrawal_id'] ?? null, $refs['subscription_id'] ?? null,
                $note,
            ]
        );
        return $new;
    }

    /**
     * Lo que se puede retirar: solo lo ganado (suscripciones como colaborador y regalos recibidos) que no se haya
     * retirado ya (las recargas se gastan dentro de TREVIX), y nunca más que el saldo.
     */
    public static function withdrawable(int $userId): int
    {
        $row = self::fetchOne(
            "SELECT COALESCE(SUM(CASE WHEN type IN ('earning', 'gift_received') THEN amount_cents ELSE 0 END), 0) AS earned,
                    COALESCE(SUM(CASE WHEN type IN ('withdrawal', 'withdrawal_refund') THEN amount_cents ELSE 0 END), 0) AS withdrawn
             FROM wallet_transactions WHERE user_id = ?",
            [$userId]
        );
        $available = (int) ($row['earned'] ?? 0) + (int) ($row['withdrawn'] ?? 0);
        return max(0, min(self::balance($userId), $available));
    }

    /** Movimientos, del más reciente al más antiguo, paginados por id. */
    public static function transactions(int $userId, int $before, int $limit): array
    {
        $limit = max(1, min(50, $limit));
        $rows = self::fetchAll(
            'SELECT t.id, t.type, t.amount_cents, t.balance_after_cents, t.note, t.created_at, t.topup_id, t.withdrawal_id,
                    t.subscription_id, cu.id AS counterpart_id, cu.username AS counterpart_username, cu.display_name AS counterpart_name,
                    cu.avatar_path AS counterpart_avatar, cu.is_verified AS counterpart_verified
             FROM wallet_transactions t
             LEFT JOIN users cu ON cu.id = t.counterpart_id
             WHERE t.user_id = ?' . ($before > 0 ? ' AND t.id < ?' : '') . '
             ORDER BY t.id DESC LIMIT ' . ($limit + 1),
            $before > 0 ? [$userId, $before] : [$userId]
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    // -------------------------------------------------------------------------
    // Medios de pago
    // -------------------------------------------------------------------------

    public static function methods(bool $onlyActive = true): array
    {
        return self::fetchAll(
            'SELECT id, name, instructions, min_amount_cents, is_active, position FROM payment_methods'
            . ($onlyActive ? ' WHERE is_active = 1' : '') . ' ORDER BY position, id'
        );
    }

    public static function method(int $id): ?array
    {
        return self::fetchOne('SELECT id, name, instructions, min_amount_cents, is_active, position FROM payment_methods WHERE id = ?', [$id]);
    }

    public static function saveMethod(?int $id, string $name, string $instructions, int $minCents, bool $active, int $position): int
    {
        if ($id !== null) {
            self::execute(
                'UPDATE payment_methods SET name = ?, instructions = ?, min_amount_cents = ?, is_active = ?, position = ? WHERE id = ?',
                [$name, $instructions, $minCents, $active ? 1 : 0, $position, $id]
            );
            return $id;
        }
        self::execute(
            'INSERT INTO payment_methods (name, instructions, min_amount_cents, is_active, position) VALUES (?, ?, ?, ?, ?)',
            [$name, $instructions, $minCents, $active ? 1 : 0, $position]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function deleteMethod(int $id): bool
    {
        return self::execute('DELETE FROM payment_methods WHERE id = ?', [$id]) > 0;
    }

    // -------------------------------------------------------------------------
    // Recargas
    // -------------------------------------------------------------------------

    private const TOPUP_COLUMNS = 't.id, t.user_id, t.payment_method_id, t.method_name, t.amount_cents, t.credited_cents, t.reference,
        t.note, t.proof_path, t.status, t.decision_note, t.reviewed_at, t.created_at';

    public static function createTopup(int $userId, array $method, int $amount, string $reference, ?string $note, string $proofPath): int
    {
        self::execute(
            'INSERT INTO wallet_topups (user_id, payment_method_id, method_name, amount_cents, reference, note, proof_path) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [$userId, (int) $method['id'], (string) $method['name'], $amount, $reference, $note, $proofPath]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function topup(int $id, bool $forUpdate = false): ?array
    {
        return self::fetchOne('SELECT ' . self::TOPUP_COLUMNS . ' FROM wallet_topups t WHERE t.id = ?' . ($forUpdate ? ' FOR UPDATE' : ''), [$id]);
    }

    public static function topupsFor(int $userId, int $limit = 20): array
    {
        return self::fetchAll(
            'SELECT ' . self::TOPUP_COLUMNS . ' FROM wallet_topups t WHERE t.user_id = ? ORDER BY t.id DESC LIMIT ' . max(1, min(50, $limit)),
            [$userId]
        );
    }

    /** Comprobantes de la persona, para borrarlos del disco al eliminar la cuenta. */
    public static function proofPathsByUser(int $userId): array
    {
        return array_map('strval', array_column(self::fetchAll('SELECT proof_path FROM wallet_topups WHERE user_id = ?', [$userId]), 'proof_path'));
    }

    public static function pendingTopups(int $userId): int
    {
        return (int) self::fetchValue("SELECT COUNT(*) FROM wallet_topups WHERE user_id = ? AND status = 'pending'", [$userId]);
    }

    /** Cierra una recarga pendiente. Devuelve false si ya no estaba pendiente. */
    public static function decideTopup(int $id, string $status, ?int $reviewerId, ?string $note, ?int $credited = null): bool
    {
        return self::execute(
            "UPDATE wallet_topups SET status = ?, reviewed_by = ?, reviewed_at = NOW(), decision_note = ?, credited_cents = ?
             WHERE id = ? AND status = 'pending'",
            [$status, $reviewerId, $note, $credited, $id]
        ) > 0;
    }

    // -------------------------------------------------------------------------
    // Retiros
    // -------------------------------------------------------------------------

    private const WITHDRAWAL_COLUMNS = 'w.id, w.user_id, w.amount_cents, w.method, w.account, w.status, w.payout_reference, w.decision_note,
        w.reviewed_at, w.created_at';

    public static function createWithdrawal(int $userId, int $amount, string $method, string $account): int
    {
        self::execute(
            'INSERT INTO wallet_withdrawals (user_id, amount_cents, method, account) VALUES (?, ?, ?, ?)',
            [$userId, $amount, $method, $account]
        );
        return (int) self::db()->lastInsertId();
    }

    public static function withdrawal(int $id, bool $forUpdate = false): ?array
    {
        return self::fetchOne('SELECT ' . self::WITHDRAWAL_COLUMNS . ' FROM wallet_withdrawals w WHERE w.id = ?' . ($forUpdate ? ' FOR UPDATE' : ''), [$id]);
    }

    public static function withdrawalsFor(int $userId, int $limit = 20): array
    {
        return self::fetchAll(
            'SELECT ' . self::WITHDRAWAL_COLUMNS . ' FROM wallet_withdrawals w WHERE w.user_id = ? ORDER BY w.id DESC LIMIT ' . max(1, min(50, $limit)),
            [$userId]
        );
    }

    public static function pendingWithdrawal(int $userId): ?array
    {
        return self::fetchOne(
            'SELECT ' . self::WITHDRAWAL_COLUMNS . " FROM wallet_withdrawals w WHERE w.user_id = ? AND w.status = 'pending' ORDER BY w.id DESC LIMIT 1",
            [$userId]
        );
    }

    public static function decideWithdrawal(int $id, string $status, ?int $reviewerId, ?string $note, ?string $payoutReference = null): bool
    {
        return self::execute(
            "UPDATE wallet_withdrawals SET status = ?, reviewed_by = ?, reviewed_at = NOW(), decision_note = ?, payout_reference = ?
             WHERE id = ? AND status = 'pending'",
            [$status, $reviewerId, $note, $payoutReference, $id]
        ) > 0;
    }

    // -------------------------------------------------------------------------
    // Panel
    // -------------------------------------------------------------------------

    /** Recargas o retiros para el panel, con la cuenta y quien lo revisó. */
    public static function adminList(string $kind, string $status, int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $page = max(1, $page);
        [$table, $columns] = $kind === 'withdrawals'
            ? ['wallet_withdrawals w', self::WITHDRAWAL_COLUMNS]
            : ['wallet_topups t', self::TOPUP_COLUMNS];
        $alias = $kind === 'withdrawals' ? 'w' : 't';
        $rows = self::fetchAll(
            "SELECT $columns, u.username, u.display_name, u.avatar_path, u.is_verified, u.status AS user_status,
                    COALESCE(wl.balance_cents, 0) AS balance_cents, r.username AS reviewer_username
             FROM $table
             JOIN users u ON u.id = $alias.user_id
             LEFT JOIN wallets wl ON wl.user_id = $alias.user_id
             LEFT JOIN users r ON r.id = $alias.reviewed_by
             WHERE $alias.status = ?
             ORDER BY " . ($status === 'pending' ? "$alias.created_at ASC" : "$alias.reviewed_at DESC") . ", $alias.id DESC
             LIMIT " . ($limit + 1) . ' OFFSET ' . (($page - 1) * $limit),
            [$status]
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Cuántas recargas o retiros hay en cada estado (pestañas del panel). */
    public static function counts(string $kind): array
    {
        $table = $kind === 'withdrawals' ? 'wallet_withdrawals' : 'wallet_topups';
        $statuses = $kind === 'withdrawals' ? self::WITHDRAWAL_STATUSES : self::TOPUP_STATUSES;
        $counts = array_fill_keys(array_keys($statuses), 0);
        foreach (self::fetchAll("SELECT status, COUNT(*) AS n FROM $table GROUP BY status") as $row) {
            $counts[$row['status']] = (int) $row['n'];
        }
        return $counts;
    }

    /** Recargas y retiros por revisar (aviso del menú del panel). */
    public static function pendingCount(): int
    {
        return (int) self::fetchValue(
            "SELECT (SELECT COUNT(*) FROM wallet_topups WHERE status = 'pending') + (SELECT COUNT(*) FROM wallet_withdrawals WHERE status = 'pending')"
        );
    }

    /** Últimos ajustes y reembolsos hechos desde el panel, con la cuenta y su saldo resultante. */
    public static function adjustments(int $page, int $limit): array
    {
        $limit = max(1, min(100, $limit));
        $rows = self::fetchAll(
            "SELECT t.id, t.user_id, t.amount_cents, t.balance_after_cents, t.note, t.created_at,
                    u.username, u.display_name, u.avatar_path, u.is_verified
             FROM wallet_transactions t JOIN users u ON u.id = t.user_id
             WHERE t.type = 'adjustment'
             ORDER BY t.id DESC
             LIMIT " . ($limit + 1) . ' OFFSET ' . ((max(1, $page) - 1) * $limit)
        );
        return ['items' => array_slice($rows, 0, $limit), 'hasMore' => count($rows) > $limit];
    }

    /** Cifras generales: saldo de todos los monederos, comisiones cobradas y pendiente de pagar. */
    public static function totals(): array
    {
        $row = self::fetchOne(
            "SELECT (SELECT COALESCE(SUM(balance_cents), 0) FROM wallets) AS balances,
                    (SELECT COALESCE(SUM(commission_cents), 0) FROM collaborator_subscriptions) AS commissions,
                    (SELECT COALESCE(SUM(price_cents), 0) FROM collaborator_subscriptions) AS sales,
                    (SELECT COALESCE(SUM(amount_cents), 0) FROM wallet_withdrawals WHERE status = 'pending') AS pending_withdrawals,
                    (SELECT COALESCE(SUM(credited_cents), 0) FROM wallet_topups WHERE status = 'approved') AS topped_up,
                    (SELECT COALESCE(SUM(amount_cents), 0) FROM wallet_withdrawals WHERE status = 'paid') AS paid_out"
        );
        return array_map('intval', $row ?? []);
    }
}
