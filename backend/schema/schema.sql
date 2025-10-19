-- ---------- Base / Extensions ----------
CREATE SCHEMA IF NOT EXISTS app;

-- UUIDs via uuid-ossp
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------- ENUM Types ----------
CREATE TYPE app.subscription_status AS ENUM ('active', 'paused', 'canceled');
CREATE TYPE app.payment_status      AS ENUM ('pending', 'paid', 'failed', 'refunded');
CREATE TYPE app.delivery_status     AS ENUM ('scheduled', 'completed', 'skipped', 'failed');

-- ---------- Customers ----------
CREATE TABLE IF NOT EXISTS app.customers (
    customer_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_name       TEXT NOT NULL,                 -- person or household name
    email               TEXT UNIQUE,                    -- optional but unique when present
    phone               TEXT,
    address_line1       TEXT,
    address_line2       TEXT,
    suburb              TEXT,
    state               TEXT,
    postcode            TEXT,
    country             TEXT DEFAULT 'Australia',
    -- Stripe linkage
    stripe_customer_id  TEXT UNIQUE,
    -- housekeeping
    is_enabled          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP NOT NULL DEFAULT now()
);

-- basic search/indexes
CREATE INDEX IF NOT EXISTS idx_customers_name ON app.customers(customer_name);
CREATE INDEX IF NOT EXISTS idx_customers_email ON app.customers(email);

-- ---------- Admins ----------
CREATE TABLE IF NOT EXISTS app.admins (
    admin_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    hashed_password TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'admin', -- simple role field for now
    is_enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------- Subscriptions ----------
CREATE TABLE IF NOT EXISTS app.subscriptions (
    subscription_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id             UUID NOT NULL REFERENCES app.customers(customer_id) ON DELETE CASCADE,
    plan_name               TEXT NOT NULL,             -- e.g., "Yearly"
    quantity_m3             NUMERIC(6,3) NOT NULL,     -- cubic meters per delivery
    cadence_days            INT NOT NULL,              -- e.g., 30, 90
    status                  app.subscription_status NOT NULL DEFAULT 'active',
    next_delivery_date      DATE,                      -- used by admin dashboard
    start_date              DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date                DATE,                      -- optional (canceled/ended)
    -- Stripe linkage
    stripe_subscription_id  TEXT UNIQUE,
    -- free-form config (delivery instructions, stacking preferences, etc.)
    config                  JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- housekeeping
    is_enabled              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMP NOT NULL DEFAULT now(),
    updated_at              TIMESTAMP NOT NULL DEFAULT now()
);

-- Foreign key indexes & useful filters
CREATE INDEX IF NOT EXISTS idx_subscriptions_customer_id  ON app.subscriptions(customer_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status       ON app.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_next_date    ON app.subscriptions(next_delivery_date);

-- Business rule: one active subscription per customer (adjust if you want to allow multiple)
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_subscription_per_customer
    ON app.subscriptions(customer_id)
    WHERE status = 'active';

-- ---------- Deliveries ----------
CREATE TABLE IF NOT EXISTS app.deliveries (
    delivery_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id     UUID NOT NULL REFERENCES app.subscriptions(subscription_id) ON DELETE CASCADE,
    scheduled_date      DATE NOT NULL,
    delivered_at        TIMESTAMP,                     -- when completed
    status              app.delivery_status NOT NULL DEFAULT 'scheduled',
    quantity_m3         NUMERIC(6,3) NOT NULL,         -- actual delivered quantity
    notes               TEXT,                          -- driver/admin notes (e.g., stacking location)
    -- housekeeping
    created_at          TIMESTAMP NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deliveries_subscription_id ON app.deliveries(subscription_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_status          ON app.deliveries(status);
CREATE INDEX IF NOT EXISTS idx_deliveries_schedule        ON app.deliveries(scheduled_date);

-- ---------- Payments ----------
CREATE TABLE IF NOT EXISTS app.payments (
    payment_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id     UUID NOT NULL REFERENCES app.subscriptions(subscription_id) ON DELETE CASCADE,
    amount_cents        BIGINT NOT NULL,               -- store money in integer cents (avoid FP issues)
    currency            TEXT NOT NULL DEFAULT 'AUD',
    status              app.payment_status NOT NULL DEFAULT 'pending',
    -- Stripe linkage
    stripe_invoice_id   TEXT UNIQUE,
    stripe_payment_intent_id TEXT UNIQUE,
    -- derived dates
    invoice_date        TIMESTAMP,                     -- when Stripe created invoice
    paid_at             TIMESTAMP,                     -- when paid/settled
    -- housekeeping
    created_at          TIMESTAMP NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_subscription_id ON app.payments(subscription_id);
CREATE INDEX IF NOT EXISTS idx_payments_status          ON app.payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at      ON app.payments(created_at);

-- ---------- Helpful updated_at trigger (optional, but handy) ----------
-- If you prefer DB-managed updated_at, keep this; otherwise manage in app layer.
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
                FROM   pg_trigger
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
