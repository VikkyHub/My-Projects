-- migrate:up
-- Materialises bookable slots from each vendor's weekly working hours for the next p_days days (IST).
-- Idempotent: existing slots (and their bookings) are never touched. Holidays are skipped.
-- Called by the API at startup and every few hours (src/modules/slots).
CREATE OR REPLACE FUNCTION generate_vendor_slots(p_days int DEFAULT 14, p_vendor uuid DEFAULT NULL)
RETURNS int LANGUAGE sql AS $$
  WITH days AS (
    SELECT d::date AS day
    FROM generate_series((now() AT TIME ZONE 'Asia/Kolkata')::date,
                         (now() AT TIME ZONE 'Asia/Kolkata')::date + (p_days - 1), interval '1 day') d
  ), candidates AS (
    SELECT h.vendor_id,
           (t AT TIME ZONE 'Asia/Kolkata') AS starts_at,
           ((t + make_interval(mins => h.slot_minutes)) AT TIME ZONE 'Asia/Kolkata') AS ends_at,
           h.capacity_per_slot AS capacity
    FROM vendor_working_hours h
    JOIN vendors v ON v.id = h.vendor_id AND v.status = 'approved' AND v.deleted_at IS NULL
    JOIN days d ON extract(dow FROM d.day) = h.weekday
    -- local (IST) wall-clock timestamps, converted to timestamptz above
    CROSS JOIN LATERAL generate_series(d.day + h.opens_at, d.day + h.closes_at - make_interval(mins => h.slot_minutes),
                                       make_interval(mins => h.slot_minutes)) AS t
    WHERE (p_vendor IS NULL OR h.vendor_id = p_vendor)
      AND NOT EXISTS (SELECT 1 FROM vendor_holidays x WHERE x.vendor_id = h.vendor_id AND x.day = d.day)
  ), ins AS (
    INSERT INTO vendor_slots (vendor_id, starts_at, ends_at, capacity)
    SELECT vendor_id, starts_at, ends_at, capacity FROM candidates
    ON CONFLICT (vendor_id, starts_at) DO NOTHING
    RETURNING 1
  )
  SELECT count(*)::int FROM ins;
$$;

-- migrate:down
DROP FUNCTION IF EXISTS generate_vendor_slots(int, uuid);
