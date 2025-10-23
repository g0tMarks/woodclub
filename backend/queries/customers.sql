-- name: ListCustomers :many
SELECT * FROM app.customers
ORDER BY customer_name;

-- name: GetCustomer :one
SELECT * FROM app.customers
WHERE customer_id = @customer_id::uuid;

-- name: CreateCustomer :one
INSERT INTO app.customers (customer_name, email, phone, address_line1, suburb, state, postcode, stripe_customer_id)
VALUES (@customer_name, @email, @phone, @address_line1, @suburb, @state, @postcode, @stripe_customer_id)
RETURNING *;

-- name: UpdateCustomer :one
UPDATE app.customers
SET customer_name = @customer_name,
    email         = @email,
    phone         = @phone,
    address_line1 = @address_line1,
    address_line2 = @address_line2,
    suburb        = @suburb,
    state         = @state,
    postcode      = @postcode,
    stripe_customer_id = @stripe_customer_id,
    is_enabled    = @is_enabled
WHERE customer_id = @customer_id::uuid
RETURNING *;

-- name: DeleteCustomer :exec
DELETE FROM app.customers WHERE customer_id = @customer_id::uuid;
