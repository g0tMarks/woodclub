-- name: ListPaymentsBySubscription :many
SELECT * FROM app.payments
WHERE subscription_id = @subscription_id::uuid
ORDER BY created_at DESC;

-- name: CreatePaymentFromInvoice :one
INSERT INTO app.payments
(subscription_id, amount_cents, currency, status, stripe_invoice_id, stripe_payment_intent_id, invoice_date, paid_at)
VALUES
(@subscription_id::uuid, @amount_cents, @currency,
 @status::app.payment_status, @stripe_invoice_id, @stripe_payment_intent_id, @invoice_date, @paid_at)
RETURNING *;

-- name: MarkPaymentPaid :one
UPDATE app.payments
SET status = 'paid',
    paid_at = COALESCE(@paid_at, now())
WHERE payment_id = @payment_id::uuid
RETURNING *;
