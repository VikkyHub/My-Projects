-- migrate:up
-- Vendor payout = gross − commission − GST on commission − GST TCS (s.52, 1% of taxable value)
--                 − income-tax TDS (s.194-O, 0.1%).  Rates live in config; confirm with your CA.

ALTER TABLE orders
  ADD COLUMN commission_gst_paise bigint NOT NULL DEFAULT 0 CHECK (commission_gst_paise >= 0),
  ADD COLUMN tds_paise            bigint NOT NULL DEFAULT 0 CHECK (tds_paise >= 0);
ALTER TABLE orders DROP CONSTRAINT orders_payout_math;
ALTER TABLE orders ADD CONSTRAINT orders_payout_math CHECK (
  vendor_payout_paise = total_paise - commission_paise - commission_gst_paise - tcs_paise - tds_paise
);

ALTER TABLE bookings
  ADD COLUMN commission_gst_paise bigint CHECK (commission_gst_paise IS NULL OR commission_gst_paise >= 0),
  ADD COLUMN tcs_paise            bigint CHECK (tcs_paise IS NULL OR tcs_paise >= 0),
  ADD COLUMN tds_paise            bigint CHECK (tds_paise IS NULL OR tds_paise >= 0),
  ADD COLUMN vendor_payout_paise  bigint,
  ADD COLUMN idempotency_key      text UNIQUE;
-- Settlement figures are frozen when the booking completes.
ALTER TABLE bookings ADD CONSTRAINT bookings_settlement_math CHECK (
  status <> 'completed' OR (
    commission_paise IS NOT NULL AND commission_gst_paise IS NOT NULL AND tcs_paise IS NOT NULL
    AND tds_paise IS NOT NULL AND vendor_payout_paise IS NOT NULL
    AND vendor_payout_paise = final_total_paise - commission_paise - commission_gst_paise - tcs_paise - tds_paise
  )
);

-- One report per user per review; reviews.report_count is maintained by the service.
CREATE TYPE review_report_reason AS ENUM ('spam', 'abusive', 'fake', 'irrelevant', 'personal_info', 'other');
CREATE TABLE review_reports (
  review_id   uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason      review_report_reason NOT NULL,
  note        text CHECK (note IS NULL OR length(note) <= 500),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (review_id, reporter_id)
);

-- migrate:down
DROP TABLE IF EXISTS review_reports;
DROP TYPE IF EXISTS review_report_reason;
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_settlement_math;
ALTER TABLE bookings
  DROP COLUMN IF EXISTS idempotency_key,
  DROP COLUMN IF EXISTS vendor_payout_paise,
  DROP COLUMN IF EXISTS tds_paise,
  DROP COLUMN IF EXISTS tcs_paise,
  DROP COLUMN IF EXISTS commission_gst_paise;
ALTER TABLE orders DROP CONSTRAINT orders_payout_math;
ALTER TABLE orders DROP COLUMN IF EXISTS tds_paise, DROP COLUMN IF EXISTS commission_gst_paise;
ALTER TABLE orders ADD CONSTRAINT orders_payout_math CHECK (vendor_payout_paise = total_paise - commission_paise - tcs_paise);
