-- ---------- Base / Extensions ----------
CREATE SCHEMA IF NOT EXISTS app;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------- ENUM Types ----------
CREATE TYPE app.subscription_status AS ENUM ('active', 'paused', 'canceled');
CREATE TYPE app.payment_status      AS ENUM ('pending', 'paid', 'failed', 'refunded');
CREATE TYPE app.delivery_status     AS ENUM ('scheduled', 'completed', 'skipped', 'failed');

-- ---------- Customers ----------
CREATE TABLE IF NOT EXISTS app.customers (
    customer_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_name       TEXT NOT NULL,
    email               TEXT UNIQUE,
    phone               TEXT,
    address_line1       TEXT,
    address_line2       TEXT,
    suburb              TEXT,
    state               TEXT,
    postcode            TEXT,
    country             TEXT DEFAULT 'Australia',
    stripe_customer_id  TEXT UNIQUE,
    is_enabled          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customers_name ON app.customers(customer_name);
CREATE INDEX IF NOT EXISTS idx_customers_email ON app.customers(email);

-- ---------- Admins ----------
CREATE TABLE IF NOT EXISTS app.admins (
    admin_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    hashed_password TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'admin',
    is_enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------- Subscriptions ----------
CREATE TABLE IF NOT EXISTS app.subscriptions (
    subscription_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id             UUID NOT NULL REFERENCES app.customers(customer_id) ON DELETE CASCADE,
    plan_name               TEXT NOT NULL,                 -- e.g. "Quarterly 1 tonne"
    quantity_tonnes         NUMERIC(6,3) NOT NULL,         -- wood volume
    flat_rate_cents         BIGINT NOT NULL,               -- base price per tonne (AUD cents)
    cadence_days            INT NOT NULL,                  -- e.g. 30 or 90 days
    status                  app.subscription_status NOT NULL DEFAULT 'active',
    next_delivery_date      DATE,
    start_date              DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date                DATE,
    stripe_subscription_id  TEXT UNIQUE,
    config                  JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_enabled              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP NOT NULL DEFAULT now(),
    updated_at              TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_customer_id ON app.subscriptions(customer_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON app.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_next_date ON app.subscriptions(next_delivery_date);

-- Optional: Only one active subscription per customer
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_subscription_per_customer
    ON app.subscriptions(customer_id)
    WHERE status = 'active';

-- ---------- Deliveries ----------
CREATE TABLE IF NOT EXISTS app.deliveries (
    delivery_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id     UUID NOT NULL REFERENCES app.subscriptions(subscription_id) ON DELETE CASCADE,
    scheduled_date      DATE NOT NULL,
    delivered_at        TIMESTAMP,
    status              app.delivery_status NOT NULL DEFAULT 'scheduled',

    -- --- Cost fields ---
    base_cost_cents     BIGINT DEFAULT 0,                  -- derived from subscription flat_rate
    delivery_hours      NUMERIC(4,2) DEFAULT 0,            -- e.g. 1.50 hours
    stacking_hours      NUMERIC(4,2) DEFAULT 0,
    delivery_fee_cents  BIGINT GENERATED ALWAYS AS (delivery_hours * 50 * 100) STORED,
    stacking_fee_cents  BIGINT GENERATED ALWAYS AS (stacking_hours * 50 * 100) STORED,
    total_cost_cents    BIGINT GENERATED ALWAYS AS (base_cost_cents + delivery_fee_cents + stacking_fee_cents) STORED,

    notes               TEXT,
    created_at          TIMESTAMP NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deliveries_subscription_id ON app.deliveries(subscription_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_status ON app.deliveries(status);
CREATE INDEX IF NOT EXISTS idx_deliveries_schedule ON app.deliveries(scheduled_date);

-- ---------- Payments ----------
CREATE TABLE IF NOT EXISTS app.payments (
    payment_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id          UUID NOT NULL REFERENCES app.subscriptions(subscription_id) ON DELETE CASCADE,
    delivery_id              UUID REFERENCES app.deliveries(delivery_id) ON DELETE SET NULL,
    amount_cents             BIGINT NOT NULL,
    currency                 TEXT NOT NULL DEFAULT 'AUD',
    status                   app.payment_status NOT NULL DEFAULT 'pending',
    stripe_invoice_id        TEXT UNIQUE,
    stripe_payment_intent_id TEXT UNIQUE,
    invoice_date             TIMESTAMP,
    paid_at                  TIMESTAMP,
    created_at               TIMESTAMP NOT NULL DEFAULT now(),
    updated_at               TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_subscription_id ON app.payments(subscription_id);
CREATE INDEX IF NOT EXISTS idx_payments_delivery_id ON app.payments(delivery_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON app.payments(status);

-- ---------- updated_at trigger ----------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'app_set_updated_at') THEN
        CREATE OR REPLACE FUNCTION app.app_set_updated_at()
        RETURNS TRIGGER AS $func$
        BEGIN
            NEW.updated_at := now();
            RETURN NEW;
        END
        $func$ LANGUAGE plpgsql;
    END IF;
END$$;

CREATE OR REPLACE FUNCTION app.ensure_trigger(tbl regclass) RETURNS VOID AS $$
BEGIN
    EXECUTE format('
        DO $I$
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM pg_trigger
                WHERE  tgname = %L
            ) THEN
                CREATE TRIGGER %I
                BEFORE UPDATE ON %s
                FOR EACH ROW
                EXECUTE FUNCTION app.app_set_updated_at();
            END IF;
        END
        $I$', 'trg_set_updated_at_'||tbl::text, 'trg_set_updated_at_'||tbl::text, tbl::text);
END;
$$ LANGUAGE plpgsql;

SELECT app.ensure_trigger('app.customers');
SELECT app.ensure_trigger('app.admins');
SELECT app.ensure_trigger('app.subscriptions');
SELECT app.ensure_trigger('app.deliveries');
SELECT app.ensure_trigger('app.payments');
