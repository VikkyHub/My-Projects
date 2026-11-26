-- migrate:up
CREATE TYPE booking_status AS ENUM (
  'requested',          -- customer booked, waiting for vendor
  'confirmed',          -- vendor accepted the slot
  'vehicle_received',   -- car checked in at shop / technician arrived
  'estimate_shared',    -- vendor sent a revised estimate after inspection
  'in_progress',        -- customer approved, work under way
  'ready',              -- work done, awaiting payment / pickup
  'completed',
  'rejected',           -- vendor declined
  'cancelled',
  'no_show'
);
CREATE TYPE service_location AS ENUM ('at_shop', 'doorstep', 'pickup_drop');
CREATE TYPE payment_state    AS ENUM ('unpaid', 'partially_paid', 'paid', 'partially_refunded', 'refunded');
CREATE TYPE estimate_status  AS ENUM ('pending', 'approved', 'rejected', 'superseded');
CREATE TYPE line_kind        AS ENUM ('service', 'labour', 'part', 'consumable', 'discount', 'other');
CREATE TYPE actor_kind       AS ENUM ('customer', 'vendor', 'admin', 'system');
CREATE TYPE attachment_kind  AS ENUM ('issue_photo', 'inspection_photo', 'before', 'after', 'invoice', 'other');

-- Weekly template used by a job to generate vendor_slots ~30 days ahead.
CREATE TABLE vendor_working_hours (
  id                 serial PRIMARY KEY,
  vendor_id          uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  weekday            smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),   -- 0 = Sunday
  opens_at           time NOT NULL,
  closes_at          time NOT NULL,
  slot_minutes       smallint NOT NULL DEFAULT 60 CHECK (slot_minutes BETWEEN 15 AND 480),
  capacity_per_slot  smallint NOT NULL DEFAULT 2 CHECK (capacity_per_slot BETWEEN 1 AND 100),  -- service bays
  CONSTRAINT working_hours_order CHECK (closes_at > opens_at),
  UNIQUE (vendor_id, weekday, opens_at)
);

CREATE TABLE vendor_holidays (
  vendor_id  uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  day        date NOT NULL,
  reason     text,
  PRIMARY KEY (vendor_id, day)
);

-- Concrete bookable slots. booked_count <= capacity is enforced by the DB, so two
-- customers racing for the last bay cannot both win (UPDATE ... SET booked_count = booked_count + 1).
CREATE TABLE vendor_slots (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id     uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  starts_at     timestamptz NOT NULL,
  ends_at       timestamptz NOT NULL,
  capacity      smallint NOT NULL CHECK (capacity >= 0),
  booked_count  smallint NOT NULL DEFAULT 0,
  is_blocked    boolean NOT NULL DEFAULT false,
  CONSTRAINT vendor_slots_window   CHECK (ends_at > starts_at),
  CONSTRAINT vendor_slots_capacity CHECK (booked_count BETWEEN 0 AND capacity),
  UNIQUE (vendor_id, starts_at)
);
CREATE INDEX vendor_slots_open_idx ON vendor_slots (vendor_id, starts_at) WHERE NOT is_blocked;

CREATE TABLE bookings (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_number         text NOT NULL UNIQUE DEFAULT make_ref('BKG', 'booking_number_seq'),
  customer_id            uuid NOT NULL REFERENCES users(id),
  vendor_id              uuid NOT NULL REFERENCES vendors(id),
  vehicle_id             uuid NOT NULL REFERENCES vehicles(id),
  domain                 business_domain NOT NULL CHECK (domain IN ('service', 'decor')),
  slot_id                uuid REFERENCES vendor_slots(id),
  scheduled_start        timestamptz NOT NULL,
  location_type          service_location NOT NULL DEFAULT 'at_shop',
  address_id             uuid REFERENCES addresses(id),
  address_snapshot       jsonb,                       -- frozen copy for doorstep / pickup
  status                 booking_status NOT NULL DEFAULT 'requested',
  customer_notes         text,
  odometer_km            int CHECK (odometer_km IS NULL OR odometer_km >= 0),

  quoted_total_paise     bigint NOT NULL DEFAULT 0 CHECK (quoted_total_paise >= 0),  -- at booking time
  final_total_paise      bigint CHECK (final_total_paise IS NULL OR final_total_paise >= 0),
  advance_paise          bigint NOT NULL DEFAULT 0 CHECK (advance_paise >= 0),
  amount_paid_paise      bigint NOT NULL DEFAULT 0 CHECK (amount_paid_paise >= 0),
  payment_state          payment_state NOT NULL DEFAULT 'unpaid',
  commission_bps         int CHECK (commission_bps IS NULL OR commission_bps BETWEEN 0 AND 5000),
  commission_paise       bigint CHECK (commission_paise IS NULL OR commission_paise >= 0),

  invoice_number         text UNIQUE,
  invoice_url            text,

  confirmed_at           timestamptz,
  started_at             timestamptz,
  completed_at           timestamptz,
  cancelled_at           timestamptz,
  cancelled_by           actor_kind,
  cancellation_reason    text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bookings_address_required CHECK (location_type = 'at_shop' OR address_snapshot IS NOT NULL),
  CONSTRAINT bookings_cancel_meta CHECK (status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL)),
  CONSTRAINT bookings_completed_meta CHECK (status <> 'completed' OR (completed_at IS NOT NULL AND final_total_paise IS NOT NULL))
);
CREATE INDEX bookings_customer_idx       ON bookings (customer_id, created_at DESC);
CREATE INDEX bookings_vendor_schedule_idx ON bookings (vendor_id, scheduled_start);
CREATE INDEX bookings_vendor_status_idx   ON bookings (vendor_id, status)
  WHERE status IN ('requested', 'confirmed', 'vehicle_received', 'estimate_shared', 'in_progress', 'ready');
CREATE INDEX bookings_vehicle_idx        ON bookings (vehicle_id, completed_at DESC);   -- service history
CREATE INDEX bookings_slot_idx           ON bookings (slot_id) WHERE slot_id IS NOT NULL;
CREATE TRIGGER bookings_updated_at BEFORE UPDATE ON bookings FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- What the customer picked at booking time (prices frozen)
CREATE TABLE booking_services (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id       uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  service_id       uuid NOT NULL REFERENCES services(id),
  name_snapshot    text NOT NULL,
  price_type       price_type NOT NULL,
  price_paise      bigint CHECK (price_paise IS NULL OR price_paise >= 0),
  gst_rate_bps     int NOT NULL,
  UNIQUE (booking_id, service_id)
);

-- Vendor estimates after inspection; the approved one becomes the invoice basis.
CREATE TABLE booking_estimates (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  version        smallint NOT NULL CHECK (version >= 1),
  status         estimate_status NOT NULL DEFAULT 'pending',
  subtotal_paise bigint NOT NULL CHECK (subtotal_paise >= 0),
  tax_paise      bigint NOT NULL CHECK (tax_paise >= 0),
  total_paise    bigint NOT NULL CHECK (total_paise >= 0),
  vendor_note    text,
  valid_until    timestamptz,
  created_by     uuid NOT NULL REFERENCES users(id),
  responded_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (booking_id, version),
  CONSTRAINT estimate_total CHECK (total_paise = subtotal_paise + tax_paise)
);
CREATE UNIQUE INDEX booking_estimates_one_approved_uq ON booking_estimates (booking_id) WHERE status = 'approved';
CREATE UNIQUE INDEX booking_estimates_one_pending_uq  ON booking_estimates (booking_id) WHERE status = 'pending';

CREATE TABLE booking_estimate_items (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  estimate_id      uuid NOT NULL REFERENCES booking_estimates(id) ON DELETE CASCADE,
  kind             line_kind NOT NULL,
  description      text NOT NULL,
  service_id       uuid REFERENCES services(id),
  product_id       uuid REFERENCES products(id),
  hsn_sac_code     text,
  quantity         numeric(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price_paise bigint NOT NULL,                -- negative only for discount lines
  gst_rate_bps     int NOT NULL CHECK (gst_rate_bps BETWEEN 0 AND 4000),
  is_optional      boolean NOT NULL DEFAULT false, -- "recommended" items the customer may decline
  is_accepted      boolean NOT NULL DEFAULT true,
  sort_order       smallint NOT NULL DEFAULT 0,
  CONSTRAINT estimate_item_sign CHECK ((kind = 'discount') = (unit_price_paise < 0) OR unit_price_paise = 0)
);
CREATE INDEX booking_estimate_items_estimate_idx ON booking_estimate_items (estimate_id, sort_order);

CREATE TABLE booking_attachments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id   uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  uploaded_by  uuid NOT NULL REFERENCES users(id),
  kind         attachment_kind NOT NULL,
  url          text NOT NULL,
  public_id    text NOT NULL,
  caption      text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX booking_attachments_booking_idx ON booking_attachments (booking_id, created_at);

-- Timeline shown in "track booking"
CREATE TABLE booking_status_history (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id   uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  from_status  booking_status,
  to_status    booking_status NOT NULL,
  actor        actor_kind NOT NULL,
  actor_id     uuid REFERENCES users(id),
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX booking_status_history_booking_idx ON booking_status_history (booking_id, created_at);

-- migrate:down
DROP TABLE IF EXISTS booking_status_history, booking_attachments, booking_estimate_items,
  booking_estimates, booking_services, bookings, vendor_slots, vendor_holidays, vendor_working_hours;
DROP TYPE IF EXISTS attachment_kind, actor_kind, line_kind, estimate_status, payment_state, service_location, booking_status;
