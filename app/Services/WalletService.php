<?php
declare(strict_types=1);

namespace Trevix\Services;

use DomainException;
use RuntimeException;
use Throwable;
use Trevix\Core\ActionError;
use Trevix\Core\Database;
use Trevix\Models\AppSetting;
use Trevix\Models\AuditLog;
use Trevix\Models\Notification;
use Trevix\Models\RateLimit;
use Trevix\Models\User;
use Trevix\Models\Wallet;

/**
 * Monedero en dólares (USD): recargas que se pagan por fuera (PayPal, Llave Bre-B…) y se acreditan cuando el equipo
 * revisa el comprobante, retiros de lo ganado como colaborador y el historial de movimientos.
 */
final class WalletService
{
    /** Pendientes a la vez por persona. */
    private const MAX_PENDING_TOPUPS = 3;

    /** Importe para mostrar: «US$ 12,50» (español) o «US$12.50» (inglés). */
    public static function money(int $cents): string
    {
        $value = abs($cents) / 100;
        $text = locale() === 'en' ? 'US$' . number_format($value, 2, '.', ',') : 'US$ ' . number_format($value, 2, ',', '.');
        return ($cents < 0 ? '−' : '') . $text;
    }

    /** Importe escrito por la persona («12», «12.5», «12,50») en centavos; null si no es un importe válido. */
    public static function parseAmount(string $text): ?int
    {
        $text = str_replace([' ', 'US$', '$', 'USD'], '', trim($text));
        if (!preg_match('/^(\d{1,7})(?:[.,](\d{1,2}))?$/', $text, $m)) {
            return null;
        }
        return (int) $m[1] * 100 + (int) str_pad($m[2] ?? '0', 2, '0');
    }

    /** Ajuste del panel en dólares, en centavos (con un mínimo para que no quede en cero). */
    public static function settingCents(string $key, int $min = 1): int
    {
        return max($min, self::parseAmount(AppSetting::get($key)) ?? (int) round((float) AppSetting::DEFAULTS[$key] * 100));
    }

    public static function amount(int $cents): array
    {
        return ['cents' => $cents, 'formatted' => self::money($cents)];
    }

    /** Resumen para la pantalla del monedero. */
    public static function summary(int $userId): array
    {
        $pending = Wallet::pendingWithdrawal($userId);
        return [
            'currency'           => 'USD',
            'balance'            => self::amount(Wallet::balance($userId)),
            'withdrawable'       => self::amount(Wallet::withdrawable($userId)),
            'min_withdrawal'     => self::amount(self::settingCents('wallet_min_withdrawal')),
            'max_topup'          => self::amount(self::settingCents('wallet_max_topup')),
            'pending_topups'     => Wallet::pendingTopups($userId),
            'pending_withdrawal' => $pending !== null ? self::presentWithdrawal($pending) : null,
            'methods'            => array_map([self::class, 'presentMethod'], Wallet::methods()),
        ];
    }

    // -------------------------------------------------------------------------
    // Recargas
    // -------------------------------------------------------------------------

    /**
     * Pide una recarga con el comprobante del campo «proof». $input: method_id, amount (texto en USD), reference, note.
     */
    public static function requestTopup(array $user, array $input): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        Guard::rateLimit('wallet_request', (string) $uid, 'Enviaste muchas solicitudes seguidas. Inténtalo en {min} min.');

        $method = Wallet::method((int) ($input['method_id'] ?? 0));
        $amount = self::parseAmount((string) ($input['amount'] ?? ''));
        $reference = Guard::singleLine((string) ($input['reference'] ?? ''), 120) ?? '';
        $note = Guard::singleLine((string) ($input['note'] ?? ''), 500);
        $max = self::settingCents('wallet_max_topup');

        $errors = [];
        if ($method === null || !(bool) $method['is_active']) {
            $errors['method_id'] = 'Elige un medio de pago.';
        }
        if ($amount === null || $amount < 1) {
            $errors['amount'] = 'Escribe el monto que pagaste, en dólares (por ejemplo 10 o 12.50).';
        } elseif ($method !== null && $amount < (int) $method['min_amount_cents']) {
            $errors['amount'] = t('El mínimo con {method} es {amount}.', ['method' => $method['name'], 'amount' => self::money((int) $method['min_amount_cents'])]);
        } elseif ($amount > $max) {
            $errors['amount'] = t('El máximo por recarga es {amount}.', ['amount' => self::money($max)]);
        }
        if (mb_strlen($reference) < 3) {
            $errors['reference'] = 'Escribe el número de transacción o la referencia del pago.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }
        if (Wallet::pendingTopups($uid) >= self::MAX_PENDING_TOPUPS) {
            throw new ActionError(t('Tienes {n} recargas en revisión. Espera a que el equipo las revise.', ['n' => self::MAX_PENDING_TOPUPS]), 422);
        }

        try {
            $proof = ImageUpload::storeProof('proof');
        } catch (RuntimeException $e) {
            throw ActionError::field('proof', $e->getMessage());
        }
        RateLimit::hit('wallet_request', (string) $uid);
        try {
            $id = Wallet::createTopup($uid, $method, (int) $amount, $reference, $note, $proof);
        } catch (Throwable $e) {
            @unlink(BASE_PATH . '/' . $proof);
            throw $e;
        }
        return self::presentTopup(Wallet::topup($id));
    }

    public static function cancelTopup(int $userId, int $topupId): void
    {
        $topup = Wallet::topup($topupId);
        if ($topup === null || (int) $topup['user_id'] !== $userId) {
            throw new ActionError('Esta recarga no existe.', 404);
        }
        if (!Wallet::decideTopup($topupId, 'cancelled', null, null)) {
            throw new ActionError('Esta recarga ya fue revisada.', 422);
        }
    }

    /** Aprueba la recarga y acredita $credited (por defecto, lo que dijo haber pagado). Solo administradores. */
    public static function approveTopup(array $actor, int $topupId, ?int $credited, ?string $note): array
    {
        self::assertAdmin($actor);
        $topup = Database::transaction(static function () use ($actor, $topupId, $credited, $note): array {
            $topup = Wallet::topup($topupId, true);
            if ($topup === null) {
                throw new ActionError('Esta recarga no existe.', 404);
            }
            if ($topup['status'] !== 'pending') {
                throw new DomainException('Esta recarga ya no está en revisión.');
            }
            $amount = $credited ?? (int) $topup['amount_cents'];
            if ($amount < 1 || $amount > 100000000) {
                throw new DomainException('Escribe un monto válido para acreditar.');
            }
            Wallet::decideTopup($topupId, 'approved', (int) $actor['id'], $note, $amount);
            Wallet::apply((int) $topup['user_id'], $amount, 'topup', ['topup_id' => $topupId], $topup['method_name']);
            return $topup + ['credited_cents' => $amount];
        });
        Notification::notifySystem((int) $topup['user_id'], 'topup_approved', $topupId);
        AuditLog::record((int) $actor['id'], 'wallet.topup_approve', 'user', (int) $topup['user_id'], array_filter([
            'topup' => $topupId, 'amount' => self::money((int) $topup['credited_cents']), 'note' => $note,
        ]));
        return $topup;
    }

    public static function rejectTopup(array $actor, int $topupId, string $reason): array
    {
        self::assertAdmin($actor);
        if (mb_strlen(trim($reason)) < 5) {
            throw new DomainException('Escribe el motivo (al menos 5 caracteres).');
        }
        $topup = Wallet::topup($topupId);
        if ($topup === null) {
            throw new ActionError('Esta recarga no existe.', 404);
        }
        if (!Wallet::decideTopup($topupId, 'rejected', (int) $actor['id'], $reason)) {
            throw new DomainException('Esta recarga ya no está en revisión.');
        }
        Notification::notifySystem((int) $topup['user_id'], 'topup_rejected', $topupId);
        AuditLog::record((int) $actor['id'], 'wallet.topup_reject', 'user', (int) $topup['user_id'], [
            'topup' => $topupId, 'amount' => self::money((int) $topup['amount_cents']), 'note' => $reason,
        ]);
        return $topup;
    }

    // -------------------------------------------------------------------------
    // Retiros
    // -------------------------------------------------------------------------

    /** Pide un retiro de lo ganado: se descuenta del saldo ya y se devuelve si se rechaza o se cancela. */
    public static function requestWithdrawal(array $user, array $input): array
    {
        $uid = (int) $user['id'];
        Guard::verifiedEmail($user);
        Guard::rateLimit('wallet_request', (string) $uid, 'Enviaste muchas solicitudes seguidas. Inténtalo en {min} min.');

        $amount = self::parseAmount((string) ($input['amount'] ?? ''));
        $method = Guard::singleLine((string) ($input['method'] ?? ''), 60) ?? '';
        $account = Guard::singleLine((string) ($input['account'] ?? ''), 255) ?? '';
        $min = self::settingCents('wallet_min_withdrawal');

        $errors = [];
        if ($amount === null || $amount < 1) {
            $errors['amount'] = 'Escribe el monto en dólares (por ejemplo 25 o 25.50).';
        } elseif ($amount < $min) {
            $errors['amount'] = t('El retiro mínimo es {amount}.', ['amount' => self::money($min)]);
        }
        if (mb_strlen($method) < 2) {
            $errors['method'] = 'Escribe por dónde quieres recibirlo (por ejemplo PayPal o Llave Bre-B).';
        }
        if (mb_strlen($account) < 3) {
            $errors['account'] = 'Escribe la cuenta, el correo o la llave donde quieres recibirlo.';
        }
        if ($errors !== []) {
            throw ActionError::fields($errors);
        }
        if (Wallet::pendingWithdrawal($uid) !== null) {
            throw new ActionError('Ya tienes un retiro en revisión.', 422);
        }

        RateLimit::hit('wallet_request', (string) $uid);
        $id = Database::transaction(static function () use ($uid, $amount, $method, $account): int {
            Wallet::lock($uid);
            if ($amount > Wallet::withdrawable($uid)) {
                throw ActionError::field('amount', t('Puedes retirar hasta {amount}: solo lo ganado como colaborador.', ['amount' => self::money(Wallet::withdrawable($uid))]));
            }
            $id = Wallet::createWithdrawal($uid, (int) $amount, $method, $account);
            if (Wallet::apply($uid, -(int) $amount, 'withdrawal', ['withdrawal_id' => $id], $method) === null) {
                throw ActionError::field('amount', 'No tienes saldo suficiente.');
            }
            return $id;
        });
        return self::presentWithdrawal(Wallet::withdrawal($id));
    }

    public static function cancelWithdrawal(int $userId, int $withdrawalId): void
    {
        Database::transaction(static function () use ($userId, $withdrawalId): void {
            $w = Wallet::withdrawal($withdrawalId, true);
            if ($w === null || (int) $w['user_id'] !== $userId) {
                throw new ActionError('Este retiro no existe.', 404);
            }
            if (!Wallet::decideWithdrawal($withdrawalId, 'cancelled', null, null)) {
                throw new ActionError('Este retiro ya fue revisado.', 422);
            }
            Wallet::apply($userId, (int) $w['amount_cents'], 'withdrawal_refund', ['withdrawal_id' => $withdrawalId], t('Retiro cancelado'));
        });
    }

    /** Marca el retiro como pagado (el equipo ya envió el dinero por fuera). Solo administradores. */
    public static function markWithdrawalPaid(array $actor, int $withdrawalId, ?string $payoutReference, ?string $note): array
    {
        self::assertAdmin($actor);
        $w = Wallet::withdrawal($withdrawalId);
        if ($w === null) {
            throw new ActionError('Este retiro no existe.', 404);
        }
        if (!Wallet::decideWithdrawal($withdrawalId, 'paid', (int) $actor['id'], $note, $payoutReference)) {
            throw new DomainException('Este retiro ya no está en revisión.');
        }
        Notification::notifySystem((int) $w['user_id'], 'withdrawal_paid', $withdrawalId);
        AuditLog::record((int) $actor['id'], 'wallet.withdrawal_paid', 'user', (int) $w['user_id'], array_filter([
            'withdrawal' => $withdrawalId, 'amount' => self::money((int) $w['amount_cents']), 'reference' => $payoutReference, 'note' => $note,
        ]));
        return $w;
    }

    /** Rechaza el retiro y devuelve el dinero al monedero. Solo administradores. */
    public static function rejectWithdrawal(array $actor, int $withdrawalId, string $reason): array
    {
        self::assertAdmin($actor);
        if (mb_strlen(trim($reason)) < 5) {
            throw new DomainException('Escribe el motivo (al menos 5 caracteres).');
        }
        $w = Database::transaction(static function () use ($actor, $withdrawalId, $reason): array {
            $w = Wallet::withdrawal($withdrawalId, true);
            if ($w === null) {
                throw new ActionError('Este retiro no existe.', 404);
            }
            if (!Wallet::decideWithdrawal($withdrawalId, 'rejected', (int) $actor['id'], $reason)) {
                throw new DomainException('Este retiro ya no está en revisión.');
            }
            Wallet::apply((int) $w['user_id'], (int) $w['amount_cents'], 'withdrawal_refund', ['withdrawal_id' => $withdrawalId], t('Retiro rechazado'));
            return $w;
        });
        Notification::notifySystem((int) $w['user_id'], 'withdrawal_rejected', $withdrawalId);
        AuditLog::record((int) $actor['id'], 'wallet.withdrawal_reject', 'user', (int) $w['user_id'], [
            'withdrawal' => $withdrawalId, 'amount' => self::money((int) $w['amount_cents']), 'note' => $reason,
        ]);
        return $w;
    }

    // -------------------------------------------------------------------------
    // Medios de pago (panel)
    // -------------------------------------------------------------------------

    /** Crea o edita un medio de pago. $input: name, instructions, min_amount (USD), position, active. */
    public static function saveMethod(array $actor, ?int $id, array $input): int
    {
        self::assertAdmin($actor);
        $name = Guard::singleLine((string) ($input['name'] ?? ''), 60) ?? '';
        $instructions = Guard::cleanText((string) ($input['instructions'] ?? ''));
        $min = self::parseAmount((string) ($input['min_amount'] ?? '1')) ?? -1;
        if (mb_strlen($name) < 2) {
            throw new DomainException('Escribe el nombre del medio de pago (por ejemplo PayPal).');
        }
        if (mb_strlen($instructions) < 5 || mb_strlen($instructions) > 1000) {
            throw new DomainException('Escribe los datos para pagar (cuenta, correo o llave y los pasos), de 5 a 1000 caracteres.');
        }
        if ($min < 1) {
            throw new DomainException('Escribe un monto mínimo válido, en dólares.');
        }
        if ($id !== null && Wallet::method($id) === null) {
            throw new ActionError('Este medio de pago no existe.', 404);
        }
        $saved = Wallet::saveMethod($id, $name, $instructions, $min, !empty($input['active']), max(0, min(999, (int) ($input['position'] ?? 0))));
        AuditLog::record((int) $actor['id'], $id === null ? 'wallet.method_create' : 'wallet.method_update', 'settings', null, ['method' => $name]);
        return $saved;
    }

    public static function deleteMethod(array $actor, int $id): void
    {
        self::assertAdmin($actor);
        $method = Wallet::method($id);
        if ($method === null || !Wallet::deleteMethod($id)) {
            throw new ActionError('Este medio de pago no existe.', 404);
        }
        AuditLog::record((int) $actor['id'], 'wallet.method_delete', 'settings', null, ['method' => $method['name']]);
    }

    // -------------------------------------------------------------------------
    // Ajustes y reembolsos (panel)
    // -------------------------------------------------------------------------

    /**
     * Acredita ($direction 'credit') o descuenta ('debit') un monto del monedero de una cuenta, con un motivo que
     * la persona ve en su historial y en el aviso. Sirve para los reembolsos de la política (cobros duplicados o
     * errores técnicos) y para registrar la devolución de saldo no usado que se paga por fuera.
     */
    public static function adjust(array $actor, string $username, string $direction, string $amountText, string $reason): array
    {
        self::assertAdmin($actor);
        $user = User::findByUsername(ltrim(trim($username), '@'));
        if ($user === null) {
            throw new DomainException('No hay ninguna cuenta con ese usuario.');
        }
        if (!in_array($direction, ['credit', 'debit'], true)) {
            throw new DomainException('Elige si vas a acreditar o descontar.');
        }
        $amount = self::parseAmount($amountText);
        if ($amount === null || $amount < 1 || $amount > 100000000) {
            throw new DomainException('Escribe un monto válido, en dólares.');
        }
        $reason = Guard::singleLine($reason, 255) ?? '';
        if (mb_strlen($reason) < 5) {
            throw new DomainException('Escribe el motivo (al menos 5 caracteres).');
        }
        $uid = (int) $user['id'];
        $signed = $direction === 'debit' ? -$amount : $amount;
        $result = Database::transaction(static function () use ($uid, $signed, $reason): array {
            Wallet::lock($uid);
            $balance = Wallet::apply($uid, $signed, 'adjustment', [], $reason);
            if ($balance === null) {
                throw new DomainException('El monedero no tiene saldo suficiente para descontar ese monto.');
            }
            return ['balance' => $balance, 'transaction_id' => (int) Database::connection()->lastInsertId()];
        });
        Notification::notifySystem($uid, 'wallet_adjusted', $result['transaction_id']);
        AuditLog::record((int) $actor['id'], 'wallet.adjust', 'user', $uid, [
            'username' => $user['username'], 'amount' => self::money($signed), 'balance' => self::money($result['balance']), 'note' => $reason,
        ]);
        return $user + $result + ['amount_cents' => $signed];
    }

    // -------------------------------------------------------------------------
    // Formato para la API y las vistas
    // -------------------------------------------------------------------------

    public static function presentMethod(array $m): array
    {
        return [
            'id'           => (int) $m['id'],
            'name'         => (string) $m['name'],
            'instructions' => (string) $m['instructions'],
            'min_amount'   => self::amount((int) $m['min_amount_cents']),
        ];
    }

    public static function presentTopup(array $t): array
    {
        return [
            'id'            => (int) $t['id'],
            'method'        => (string) $t['method_name'],
            'amount'        => self::amount((int) $t['amount_cents']),
            'credited'      => $t['credited_cents'] !== null ? self::amount((int) $t['credited_cents']) : null,
            'reference'     => (string) $t['reference'],
            'note'          => $t['note'],
            'status'        => $t['status'],
            'status_label'  => t(Wallet::TOPUP_STATUSES[$t['status']] ?? $t['status']),
            'decision_note' => $t['decision_note'],
            'created_at'    => $t['created_at'],
            'reviewed_at'   => $t['reviewed_at'],
        ];
    }

    public static function presentWithdrawal(array $w): array
    {
        return [
            'id'               => (int) $w['id'],
            'amount'           => self::amount((int) $w['amount_cents']),
            'method'           => (string) $w['method'],
            'account'          => (string) $w['account'],
            'status'           => $w['status'],
            'status_label'     => t(Wallet::WITHDRAWAL_STATUSES[$w['status']] ?? $w['status']),
            'payout_reference' => $w['payout_reference'],
            'decision_note'    => $w['decision_note'],
            'created_at'       => $w['created_at'],
            'reviewed_at'      => $w['reviewed_at'],
        ];
    }

    public static function presentTransaction(array $t): array
    {
        $counterpart = $t['counterpart_id'] !== null ? [
            'id'           => (int) $t['counterpart_id'],
            'username'     => (string) $t['counterpart_username'],
            'display_name' => (string) $t['counterpart_name'],
            'avatar_path'  => $t['counterpart_avatar'],
            'is_verified'  => !empty($t['counterpart_verified']),
        ] : null;
        $label = match ($t['type']) {
            'subscription' => $counterpart !== null ? t('Suscripción a {name}', ['name' => $counterpart['display_name']]) : t('Suscripción'),
            'earning'      => $counterpart !== null ? t('Suscripción de {name}', ['name' => $counterpart['display_name']]) : t('Ingreso por suscripción'),
            'topup'        => $t['note'] !== null ? t('Recarga con {method}', ['method' => $t['note']]) : t('Recarga'),
            'withdrawal'   => $t['note'] !== null ? t('Retiro a {method}', ['method' => $t['note']]) : t('Retiro'),
            'adjustment'   => $t['note'] !== null ? t('Ajuste de TREVIX: {reason}', ['reason' => $t['note']]) : t('Ajuste de TREVIX'),
            default        => t(Wallet::TYPES[$t['type']] ?? $t['type']),
        };
        return [
            'id'            => (int) $t['id'],
            'type'          => $t['type'],
            'label'         => $label,
            'amount'        => self::amount((int) $t['amount_cents']),
            'balance_after' => self::amount((int) $t['balance_after_cents']),
            'counterpart'   => $counterpart,
            'created_at'    => $t['created_at'],
        ];
    }

    public static function assertAdmin(array $actor): void
    {
        if (!Moderation::isAdmin($actor)) {
            throw new DomainException('Esta acción es exclusiva de los administradores.');
        }
    }
}
