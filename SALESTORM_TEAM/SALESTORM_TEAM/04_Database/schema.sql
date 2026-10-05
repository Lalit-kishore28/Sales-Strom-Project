-- PostgreSQL DDL (core tables; supporting tables abbreviated)
CREATE TABLE customer (customer_id BIGINT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT, created_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE category (category_id BIGINT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE product (
  product_id BIGINT PRIMARY KEY, category_id BIGINT REFERENCES category, name TEXT NOT NULL,
  price NUMERIC(12,2) NOT NULL CHECK (price >= 0), active BOOLEAN DEFAULT true);
CREATE TABLE sale (
  sale_id BIGINT PRIMARY KEY, name TEXT, starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL, CHECK (ends_at > starts_at));
CREATE TABLE sale_item (
  sale_id BIGINT REFERENCES sale, product_id BIGINT REFERENCES product,
  sale_price NUMERIC(12,2) NOT NULL, per_customer_limit INT NOT NULL DEFAULT 1, PRIMARY KEY (sale_id, product_id));
CREATE TABLE coupon (coupon_id BIGINT PRIMARY KEY, code TEXT UNIQUE, discount_pct NUMERIC(5,2), sale_id BIGINT REFERENCES sale);
CREATE TABLE cart (cart_id BIGINT PRIMARY KEY, customer_id BIGINT REFERENCES customer, updated_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE cart_item (cart_id BIGINT REFERENCES cart, product_id BIGINT REFERENCES product, qty INT CHECK (qty > 0), PRIMARY KEY (cart_id, product_id));

-- ===== Inventory service =====
CREATE TABLE inventory (
  inventory_id BIGINT PRIMARY KEY,
  product_id BIGINT NOT NULL UNIQUE REFERENCES product,
  available_quantity INT NOT NULL CHECK (available_quantity >= 0),
  reserved_quantity  INT NOT NULL CHECK (reserved_quantity  >= 0),
  sold_quantity      INT NOT NULL CHECK (sold_quantity      >= 0),
  total_quantity     INT NOT NULL,
  version BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (available_quantity + reserved_quantity + sold_quantity = total_quantity)   -- conservation invariant
);
CREATE TABLE inventory_reservation (
  reservation_id UUID PRIMARY KEY,
  inventory_id BIGINT NOT NULL REFERENCES inventory,
  customer_id BIGINT NOT NULL REFERENCES customer,
  sale_id BIGINT NOT NULL REFERENCES sale,
  quantity INT NOT NULL DEFAULT 1,
  status TEXT NOT NULL CHECK (status IN ('RESERVED','PAYMENT_PENDING','PAYMENT_FAILED','CONFIRMED','SOLD','RELEASED')),
  idempotency_key TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (customer_id, sale_id, inventory_id)            -- one unit per customer per sale
);
CREATE INDEX idx_resv_expiry ON inventory_reservation (status, expires_at) WHERE status IN ('RESERVED','PAYMENT_PENDING');
CREATE TABLE inventory_audit (audit_id BIGSERIAL PRIMARY KEY, inventory_id BIGINT, reservation_id UUID, from_state TEXT, to_state TEXT, delta_available INT, at TIMESTAMPTZ DEFAULT now());

-- Reserve (executed in one transaction; 0 rows updated => sold out)
-- UPDATE inventory SET available_quantity = available_quantity - 1, reserved_quantity = reserved_quantity + 1,
--        version = version + 1, updated_at = now()
--  WHERE product_id = :pid AND available_quantity >= 1;

-- ===== Payment service =====
CREATE TABLE payment (
  payment_id UUID PRIMARY KEY,
  reservation_id UUID NOT NULL UNIQUE,                    -- one payment per reservation
  idempotency_key TEXT NOT NULL UNIQUE,
  gateway_txn_ref TEXT UNIQUE,
  amount NUMERIC(12,2) NOT NULL, currency CHAR(3) NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('INITIATED','SUCCEEDED','FAILED','UNKNOWN','REFUND_PENDING','REFUNDED')),
  created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now());
CREATE INDEX idx_payment_recon ON payment (status, updated_at) WHERE status IN ('UNKNOWN','INITIATED');

-- ===== Order service =====
CREATE TABLE "order" (
  order_id UUID PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customer,
  payment_id UUID NOT NULL UNIQUE,                        -- exactly-once order per payment
  reservation_id UUID NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK (status IN ('CREATED','PAYMENT_PENDING','CONFIRMED','PROCESSING','SHIPPED','OUT_FOR_DELIVERY','DELIVERED','CANCELLED')),
  total NUMERIC(12,2) NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now());
CREATE INDEX idx_order_customer ON "order" (customer_id, created_at DESC);
CREATE TABLE order_item (order_id UUID REFERENCES "order", product_id BIGINT REFERENCES product, qty INT NOT NULL, unit_price NUMERIC(12,2) NOT NULL, PRIMARY KEY (order_id, product_id));
CREATE TABLE shipment (shipment_id UUID PRIMARY KEY, order_id UUID UNIQUE REFERENCES "order", partner TEXT, tracking_no TEXT, status TEXT, updated_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE notification (notification_id UUID PRIMARY KEY, order_id UUID, channel TEXT, template TEXT, status TEXT, dedupe_key TEXT UNIQUE, created_at TIMESTAMPTZ DEFAULT now());

-- ===== Shared pattern tables (per service DB) =====
CREATE TABLE outbox (event_id UUID PRIMARY KEY, aggregate_id TEXT, type TEXT, payload JSONB, created_at TIMESTAMPTZ DEFAULT now(), published_at TIMESTAMPTZ);
CREATE TABLE processed_event (event_id UUID, consumer TEXT, PRIMARY KEY (event_id, consumer));   -- idempotent consumers
