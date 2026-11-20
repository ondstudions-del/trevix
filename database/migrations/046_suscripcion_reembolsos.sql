-- TREVIX · Reembolsos / revocación de suscripciones a colaboradores

ALTER TABLE wallet_transactions
    MODIFY COLUMN type ENUM(
        'topup', 'subscription', 'earning', 'withdrawal', 'withdrawal_refund', 'adjustment',
        'gift_purchase', 'gift_received', 'ad_payment', 'ad_refund', 'subscription_refund'
    ) NOT NULL;

ALTER TABLE collaborator_subscriptions
    ADD COLUMN refunded_cents INT UNSIGNED NOT NULL DEFAULT 0 AFTER earning_cents,
    ADD COLUMN revoked_at DATETIME NULL DEFAULT NULL AFTER expires_at;
