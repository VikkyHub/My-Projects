-- migrate:up
CREATE TYPE order_status AS ENUM (
  'pending_payment',   -- created, waiting for Razorpay capture (prepaid only)
  'placed',            -- paid (or COD confirmed), waiting for vendor
  'accepted',
  'packed',
  'dispatched',
  'out_for_delivery',
  'delivered',
  'rejected',          -- vendor declined -> auto refund
  'cancelled',
  'payment_failed'
);
CREATE TYPE payment_mode   AS ENUM ('prepaid', 'cod');
CREATE TYPE return_status  AS ENUM ('requested', 'approved', 'rejected', 'pickup_scheduled', 'received', 'refunded', 'cancelled');
CREATE TYPE return_reason  AS ENUM ('wrong_part', 'does_not_fit', 'damaged', 'defective', 'missing_items', 'not_as_described', 'other');

CREATE TABLE carts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  vehicle_id  uuid REFERENCES vehicles(id) ON DELETE SET NULL,   -- vehicle the cart is "for", used for fit warnings
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE cart_items (
  cart_id     uuid NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  product_id  uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity    int NOT NULL CHECK (quantity BETWEEN 1 AND 100),
  added_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (cart_id, product_id)
);

-- One checkout = one payment, split into one order per vendor.
CREATE TABLE order_groups (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id   uuid NOT NULL REFERENCES users(id),
  payment_mode  payment_mode NOT NULL,
  total_paise   bigint NOT NULL CHECK (total_paise >= 0),
  wallet_used_paise bigint NOT NULL DEFAULT 0 CHECK (wallet_used_paise >= 0),
  idempotency_key text NOT NULL UNIQUE,        -- from the client; double taps on "Pay" create one checkout
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT order_groups_wallet_le_total CHECK (wallet_used_paise <= total_paise)
);
CREATE INDEX order_groups_customer_idx ON order_groups (customer_id, created_at DESC);

CREATE TABLE orders (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number         text NOT NULL UNIQUE DEFAULT make_ref('ORD', 'order_number_seq'),
  group_id             uuid NOT NULL REFERENCES order_groups(id),
  customer_id          uuid NOT NULL REFERENCES users(id),
  vendor_id            uuid NOT NULL REFERENCES vendors(id),
  vehicle_id           uuid REFERENCES vehicles(id),
  status               order_status NOT NULL,
  payment_mode         payment_mode NOT NULL,
  payment_state        payment_state NOT NULL DEFAULT 'unpaid',
  shipping_address     jsonb NOT NULL,         -- snapshot: name, phone, lines, city, state, pincode, lat/lng
  -- Totals (paise). tax is included in item prices (Indian MRP is tax-inclusive) and broken out for the invoice.
  items_total_paise    bigint NOT NULL CHECK (items_total_paise >= 0),
  discount_paise       bigint NOT NULL DEFAULT 0 CHECK (discount_paise >= 0),
  delivery_fee_paise   bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_paise >= 0),
  tax_paise            bigint NOT NULL CHECK (tax_paise >= 0),
  total_paise          bigint NOT NULL CHECK (total_paise >= 0),
  -- Platform economics, frozen when the order is placed
  commission_bps       int NOT NULL CHECK (commission_bps BETWEEN 0 AND 5000),
  commission_paise     bigint NOT NULL CHECK (commission_paise >= 0),
  tcs_paise            bigint NOT NULL DEFAULT 0 CHECK (tcs_paise >= 0),   -- GST s.52 TCS withheld from vendor
  vendor_payout_paise  bigint NOT NULL,
  -- Fulfilment
  courier_name         text,
  tracking_number      text,
  tracking_url         text,
  expected_delivery_at timestamptz,
  invoice_number       text UNIQUE,
  invoice_url          text,
  customer_note        text,
  accepted_at          timestamptz,
  dispatched_at        timestamptz,
  delivered_at         timestamptz,
  cancelled_at         timestamptz,
  cancelled_by         actor_kind,
  cancellation_reason  text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT orders_total_math CHECK (total_paise = items_total_paise - discount_paise + delivery_fee_paise),
  CONSTRAINT orders_payout_math CHECK (vendor_payout_paise = total_paise - commission_paise - tcs_paise),
  CONSTRAINT orders_delivered_meta CHECK (status <> 'delivered' OR delivered_at IS NOT NULL),
  CONSTRAINT orders_cancel_meta CHECK (status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL))
);
CREATE INDEX orders_customer_idx      ON orders (customer_id, created_at DESC);
CREATE INDEX orders_vendor_idx        ON orders (vendor_id, created_at DESC);
CREATE INDEX orders_vendor_active_idx ON orders (vendor_id, status)
  WHERE status IN ('placed', 'accepted', 'packed', 'dispatched', 'out_for_delivery');
CREATE INDEX orders_group_idx         ON orders (group_id);
CREATE INDEX orders_pending_payment_idx ON orders (created_at) WHERE status = 'pending_payment';  -- expiry sweeper
CREATE TRIGGER orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE order_items (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id          uuid NOT NULL REFERENCES products(id),
  -- Snapshot: invoices and disputes must not change when the vendor edits the listing
  name_snapshot       text NOT NULL,
  sku_snapshot        text NOT NULL,
  part_number_snapshot text,
  hsn_code            text NOT NULL,
  quantity            int NOT NULL CHECK (quantity > 0),
  mrp_paise           bigint NOT NULL CHECK (mrp_paise > 0),
  unit_price_paise    bigint NOT NULL CHECK (unit_price_paise > 0),
  gst_rate_bps        int NOT NULL CHECK (gst_rate_bps BETWEEN 0 AND 4000),
  tax_paise           bigint NOT NULL CHECK (tax_paise >= 0),
  line_total_paise    bigint NOT NULL CHECK (line_total_paise >= 0),
  returned_qty        int NOT NULL DEFAULT 0,
  return_window_ends_at timestamptz,            -- set on delivery
  CONSTRAINT order_items_line_math CHECK (line_total_paise = unit_price_paise * quantity),
  CONSTRAINT order_items_returned_le_qty CHECK (returned_qty BETWEEN 0 AND quantity),
  UNIQUE (order_id, product_id)
);
CREATE INDEX order_items_product_idx ON order_items (product_id);

CREATE TABLE order_status_history (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id     uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  from_status  order_status,
  to_status    order_status NOT NULL,
  actor        actor_kind NOT NULL,
  actor_id     uuid REFERENCES users(id),
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX order_status_history_order_idx ON order_status_history (order_id, created_at);

CREATE TABLE return_requests (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_item_id    uuid NOT NULL REFERENCES order_items(id),
  customer_id      uuid NOT NULL REFERENCES users(id),
  quantity         int NOT NULL CHECK (quantity > 0),
  reason           return_reason NOT NULL,
  description      text,
  photo_urls       text[] NOT NULL DEFAULT '{}',
  status           return_status NOT NULL DEFAULT 'requested',
  refund_amount_paise bigint CHECK (refund_amount_paise IS NULL OR refund_amount_paise >= 0),
  vendor_note      text,
  resolved_by      uuid REFERENCES users(id),
  resolved_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX return_requests_item_idx   ON return_requests (order_item_id);
CREATE INDEX return_requests_open_idx   ON return_requests (status, created_at) WHERE status IN ('requested', 'approved', 'pickup_scheduled', 'received');
CREATE UNIQUE INDEX return_requests_one_open_uq ON return_requests (order_item_id)
  WHERE status IN ('requested', 'approved', 'pickup_scheduled', 'received');
CREATE TRIGGER return_requests_updated_at BEFORE UPDATE ON return_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- migrate:down
DROP TABLE IF EXISTS return_requests, order_status_history, order_items, orders, order_groups, cart_items, carts;
DROP TYPE IF EXISTS return_reason, return_status, payment_mode, order_status;
