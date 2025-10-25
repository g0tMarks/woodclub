-- name: ListSubscriptionsByCustomer :many
SELECT * FROM app.subscriptions
WHERE customer_id = @customer_id::uuid
ORDER BY created_at DESC;

-- name: GetSubscription :one
SELECT * FROM app.subscriptions
WHERE subscription_id = @subscription_id::uuid;

-- name: CreateSubscription :one
INSERT INTO app.subscriptions
(customer_id, plan_name, quantity_tonnes, flat_rate_cents, delivery_month, status, next_delivery_date, start_date, stripe_subscription_id, config)
VALUES
(@customer_id::uuid, @plan_name, @quantity_tonnes, @flat_rate_cents, @delivery_month, @status::app.subscription_status,
 @next_delivery_date, @start_date, @stripe_subscription_id, COALESCE(@config::jsonb, '{}'::jsonb))
RETURNING *;

-- name: UpdateSubscription :one
UPDATE app.subscriptions
SET plan_name = @plan_name,
    quantity_tonnes = @quantity_tonnes,
    flat_rate_cents = @flat_rate_cents,
    delivery_month = @delivery_month,
    status = @status::app.subscription_status,
    next_delivery_date = @next_delivery_date,
    end_date = @end_date,
    stripe_subscription_id = @stripe_subscription_id,
    config = COALESCE(@config::jsonb, config)
WHERE subscription_id = @subscription_id::uuid
RETURNING *;

-- name: DeleteSubscription :exec
DELETE FROM app.subscriptions
WHERE subscription_id = @subscription_id::uuid;
