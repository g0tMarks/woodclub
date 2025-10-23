-- name: ListDeliveriesBySubscription :many
SELECT * FROM app.deliveries
WHERE subscription_id = @subscription_id::uuid
ORDER BY scheduled_date DESC;

-- name: CreateDelivery :one
INSERT INTO app.deliveries
(subscription_id, scheduled_date, status, quantity_m3, notes)
VALUES (@subscription_id::uuid, @scheduled_date, @status::app.delivery_status, @quantity_m3, @notes)
RETURNING *;

-- name: CompleteDelivery :one
UPDATE app.deliveries
SET status = 'completed',
    delivered_at = now(),
    quantity_m3 = COALESCE(@quantity_m3, quantity_m3),
    notes = COALESCE(@notes, notes)
WHERE delivery_id = @delivery_id::uuid
RETURNING *;
