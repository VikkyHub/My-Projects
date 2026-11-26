-- migrate:up
CREATE TYPE dispute_status AS ENUM ('open', 'under_review', 'awaiting_customer', 'awaiting_vendor',
                                    'resolved_refund', 'resolved_partial_refund', 'resolved_no_action', 'closed');
CREATE TYPE dispute_reason AS ENUM ('not_delivered', 'wrong_or_damaged_part', 'poor_service_quality', 'overcharged',
                                    'vehicle_damaged', 'refund_not_received', 'vendor_behaviour', 'other');

CREATE TABLE disputes (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dispute_number     text NOT NULL UNIQUE DEFAULT make_ref('DSP', 'dispute_number_seq'),
  raised_by          uuid NOT NULL REFERENCES users(id),
  raised_by_role     actor_kind NOT NULL CHECK (raised_by_role IN ('customer', 'vendor')),
  vendor_id          uuid NOT NULL REFERENCES vendors(id),
  customer_id        uuid NOT NULL REFERENCES users(id),
  order_id           uuid REFERENCES orders(id),
  booking_id         uuid REFERENCES bookings(id),
  reason             dispute_reason NOT NULL,
  description        text NOT NULL CHECK (length(description) BETWEEN 10 AND 4000),
  claimed_amount_paise bigint CHECK (claimed_amount_paise IS NULL OR claimed_amount_paise > 0),
  status             dispute_status NOT NULL DEFAULT 'open',
  priority           smallint NOT NULL DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),
  assigned_admin_id  uuid REFERENCES users(id),
  resolution_note    text,
  sla_due_at         timestamptz NOT NULL DEFAULT now() + interval '72 hours',
  resolved_at        timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT disputes_one_target CHECK ((order_id IS NULL) <> (booking_id IS NULL)),
  CONSTRAINT disputes_resolved_meta CHECK (status NOT IN ('resolved_refund', 'resolved_partial_refund', 'resolved_no_action', 'closed')
                                           OR resolved_at IS NOT NULL)
);
CREATE INDEX disputes_queue_idx    ON disputes (status, sla_due_at) WHERE status IN ('open', 'under_review', 'awaiting_customer', 'awaiting_vendor');
CREATE INDEX disputes_vendor_idx   ON disputes (vendor_id, created_at DESC);
CREATE INDEX disputes_customer_idx ON disputes (customer_id, created_at DESC);
CREATE INDEX disputes_assignee_idx ON disputes (assigned_admin_id) WHERE assigned_admin_id IS NOT NULL;
-- One open dispute per order / booking
CREATE UNIQUE INDEX disputes_open_order_uq ON disputes (order_id)
  WHERE order_id IS NOT NULL AND status IN ('open', 'under_review', 'awaiting_customer', 'awaiting_vendor');
CREATE UNIQUE INDEX disputes_open_booking_uq ON disputes (booking_id)
  WHERE booking_id IS NOT NULL AND status IN ('open', 'under_review', 'awaiting_customer', 'awaiting_vendor');
CREATE TRIGGER disputes_updated_at BEFORE UPDATE ON disputes FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE refunds ADD CONSTRAINT refunds_dispute_fk FOREIGN KEY (dispute_id) REFERENCES disputes(id);

CREATE TABLE dispute_messages (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  dispute_id      uuid NOT NULL REFERENCES disputes(id) ON DELETE CASCADE,
  author_id       uuid NOT NULL REFERENCES users(id),
  author_role     actor_kind NOT NULL,
  body            text NOT NULL,
  attachment_urls text[] NOT NULL DEFAULT '{}',
  is_internal     boolean NOT NULL DEFAULT false,     -- admin-only notes
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX dispute_messages_dispute_idx ON dispute_messages (dispute_id, id);

-- Every admin action and every money-moving action is audited.
CREATE TABLE audit_logs (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id     uuid REFERENCES users(id),
  actor_role   text NOT NULL,
  action       text NOT NULL,                  -- vendor.approve, refund.create, payout.approve ...
  entity_type  text NOT NULL,
  entity_id    text NOT NULL,
  before_data  jsonb,
  after_data   jsonb,
  ip           inet,
  request_id   text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_entity_idx ON audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX audit_logs_actor_idx  ON audit_logs (actor_id, created_at DESC);

-- Daily roll-up for vendor analytics (views, conversions). Views are counted in Redis and
-- flushed here by a nightly job; orders/bookings/revenue are recomputed from source tables.
CREATE TABLE vendor_daily_stats (
  vendor_id          uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  day                date NOT NULL,
  profile_views      int NOT NULL DEFAULT 0,
  listing_views      int NOT NULL DEFAULT 0,
  search_impressions int NOT NULL DEFAULT 0,
  call_clicks        int NOT NULL DEFAULT 0,
  chat_starts        int NOT NULL DEFAULT 0,
  orders_count       int NOT NULL DEFAULT 0,
  bookings_count     int NOT NULL DEFAULT 0,
  gmv_paise          bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (vendor_id, day)
);

-- Customer favourites (shops)
CREATE TABLE favorite_vendors (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  vendor_id  uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, vendor_id)
);

-- migrate:down
DROP TABLE IF EXISTS favorite_vendors, vendor_daily_stats, audit_logs, dispute_messages;
ALTER TABLE refunds DROP CONSTRAINT IF EXISTS refunds_dispute_fk;
DROP TABLE IF EXISTS disputes;
DROP TYPE IF EXISTS dispute_reason, dispute_status;
