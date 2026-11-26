-- Smoke test: run against a freshly migrated + seeded DB. Everything rolls back.
\set ON_ERROR_STOP 1
\set QUIET 1
\pset footer off
BEGIN;

-- helper: assert a statement fails with a given SQLSTATE
CREATE FUNCTION pg_temp.expect_fail(stmt text, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RAISE EXCEPTION 'EXPECTED FAILURE DID NOT HAPPEN: %', label;
EXCEPTION WHEN check_violation OR unique_violation OR foreign_key_violation OR not_null_violation THEN
  RAISE NOTICE 'ok (rejected): %', label;
END $$;

INSERT INTO users (id, phone, full_name) VALUES
  ('00000000-0000-0000-0000-000000000001', '+919800000001', 'Customer One'),
  ('00000000-0000-0000-0000-000000000002', '+919800000002', 'Vendor Owner'),
  ('00000000-0000-0000-0000-000000000003', '+919800000003', 'Admin');
UPDATE users SET admin_role = 'super_admin' WHERE id = '00000000-0000-0000-0000-000000000003';

SELECT pg_temp.expect_fail($$INSERT INTO users (phone) VALUES ('9800000001')$$, 'phone not E.164');
SELECT pg_temp.expect_fail($$INSERT INTO users (phone) VALUES ('+919800000001')$$, 'duplicate live phone');

INSERT INTO vehicles (id, user_id, make_id, model_id, manufacture_year, fuel_type, registration_number, is_default)
SELECT '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', mk.id, m.id, 2021, 'petrol', 'MH12AB1234', true
FROM vehicle_models m JOIN vehicle_makes mk ON mk.id = m.make_id WHERE m.slug = 'swift';
SELECT pg_temp.expect_fail($$INSERT INTO vehicles (user_id, make_id, model_id, manufacture_year, fuel_type, registration_number)
  VALUES ('00000000-0000-0000-0000-000000000001', 1, 1, 2021, 'petrol', 'mh 12 ab 1234')$$, 'unnormalised reg number');

-- Vendor in Pune (Kothrud), sells parts + service
INSERT INTO vendors (id, owner_user_id, business_name, slug, business_domains, phone, address_line1, city, state, pincode, location, gstin, status)
VALUES ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000002', 'Shree Auto Parts & Service', 'shree-auto',
        '{parts,service}', '+919800000002', 'Paud Road', 'Pune', 'Maharashtra', '411038',
        ST_SetSRID(ST_MakePoint(73.8077, 18.5074), 4326)::geography, '27AAPFU0939F1ZV', 'pending_review');
SELECT pg_temp.expect_fail($$UPDATE vendors SET status = 'approved' WHERE slug = 'shree-auto'$$, 'approve without reviewer');
UPDATE vendors SET status = 'approved', reviewed_by = '00000000-0000-0000-0000-000000000003', reviewed_at = now() WHERE slug = 'shree-auto';
SELECT pg_temp.expect_fail($$UPDATE vendors SET gstin = 'BADGSTIN1234567' WHERE slug = 'shree-auto'$$, 'invalid GSTIN');

-- Nearby search: vendors within 10 km of Pune station, nearest first
SELECT business_name, round((ST_Distance(location, ST_MakePoint(73.8745, 18.5286)::geography) / 1000)::numeric, 1) AS km
FROM vendors WHERE status = 'approved' AND ST_DWithin(location, ST_MakePoint(73.8745, 18.5286)::geography, 10000)
ORDER BY location <-> ST_MakePoint(73.8745, 18.5286)::geography;

-- Product + fitment
INSERT INTO products (id, vendor_id, subcategory_id, brand_id, sku, name, part_number, part_type, mrp_paise, price_paise, gst_rate_bps, hsn_code, stock_qty, status)
SELECT '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', s.id, b.id, 'BP-SW-01',
       'Front Brake Pad Set', '55810M68K00', 'oes', 180000, 149900, 1800, '87083000', 10, 'active'
FROM subcategories s, brands b WHERE s.slug = 'brake-pads' AND b.slug = 'bosch';
INSERT INTO product_fitments (product_id, make_id, model_id, year_from, year_to)
SELECT '00000000-0000-0000-0000-0000000000c1', make_id, id, 2018, NULL FROM vehicle_models WHERE slug = 'swift';
SELECT pg_temp.expect_fail($$UPDATE products SET price_paise = 200000 WHERE sku = 'BP-SW-01'$$, 'price above MRP');
SELECT pg_temp.expect_fail($$UPDATE products SET reserved_qty = 11 WHERE sku = 'BP-SW-01'$$, 'reserve more than stock');

-- Fitment-aware search for the customer's car ("brake pad" + my Swift 2021)
SELECT p.name, p.price_paise / 100.0 AS price_inr
FROM products p
WHERE p.status = 'active' AND p.deleted_at IS NULL
  AND p.search_vector @@ plainto_tsquery('simple', 'brake pad')
  AND (p.is_universal_fit OR EXISTS (
        SELECT 1 FROM product_fitments f, vehicles v
        WHERE v.id = '00000000-0000-0000-0000-0000000000a1' AND f.product_id = p.id AND f.make_id = v.make_id
          AND (f.model_id IS NULL OR f.model_id = v.model_id)
          AND (f.variant_id IS NULL OR f.variant_id = v.variant_id)
          AND v.manufacture_year BETWEEN coalesce(f.year_from, 1950) AND coalesce(f.year_to, 2100)));

-- Order with math constraints
INSERT INTO order_groups (id, customer_id, payment_mode, total_paise, idempotency_key)
VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001', 'prepaid', 299800, 'k1');
INSERT INTO orders (id, group_id, customer_id, vendor_id, status, payment_mode, shipping_address,
                    items_total_paise, tax_paise, total_paise, commission_bps, commission_paise, commission_gst_paise, tcs_paise, tds_paise, vendor_payout_paise)
VALUES ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000b1', 'pending_payment', 'prepaid', '{"city":"Pune"}',
        299800, 45732, 299800, 800, 23984, 4317, 2541, 254, 268704);
SELECT order_number FROM orders WHERE id = '00000000-0000-0000-0000-0000000000e1';
SELECT pg_temp.expect_fail($$UPDATE orders SET vendor_payout_paise = 1 WHERE order_number IS NOT NULL$$, 'payout math mismatch');
INSERT INTO order_items (order_id, product_id, name_snapshot, sku_snapshot, hsn_code, quantity, mrp_paise, unit_price_paise, gst_rate_bps, tax_paise, line_total_paise)
VALUES ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 'Front Brake Pad Set', 'BP-SW-01', '87083000', 2, 180000, 149900, 1800, 45732, 299800);
SELECT pg_temp.expect_fail($$INSERT INTO payments (user_id, purpose, booking_id, amount_paise, razorpay_order_id)
  VALUES ('00000000-0000-0000-0000-000000000001', 'order_checkout', NULL, 299800, 'order_X')$$, 'checkout payment without order group');
INSERT INTO payments (user_id, purpose, order_group_id, amount_paise, razorpay_order_id)
VALUES ('00000000-0000-0000-0000-000000000001', 'order_checkout', '00000000-0000-0000-0000-0000000000d1', 299800, 'order_RZP123');
SELECT pg_temp.expect_fail($$UPDATE payments SET status = 'captured' WHERE razorpay_order_id = 'order_RZP123'$$, 'captured without payment id');
SELECT pg_temp.expect_fail($$INSERT INTO payment_webhook_events (event_id, event_type, payload) VALUES ('evt_1','payment.captured','{}'),('evt_1','payment.captured','{}')$$, 'duplicate webhook event');

-- Slot capacity race: capacity 1, second increment must fail
INSERT INTO vendor_slots (id, vendor_id, starts_at, ends_at, capacity)
VALUES ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b1', '2026-12-01 10:00+05:30', '2026-12-01 11:00+05:30', 1);
UPDATE vendor_slots SET booked_count = booked_count + 1 WHERE id = '00000000-0000-0000-0000-0000000000f1';
SELECT pg_temp.expect_fail($$UPDATE vendor_slots SET booked_count = booked_count + 1 WHERE id = '00000000-0000-0000-0000-0000000000f1'$$, 'slot overbooking');

-- Booking + estimates
INSERT INTO bookings (id, customer_id, vendor_id, vehicle_id, domain, slot_id, scheduled_start)
VALUES ('00000000-0000-0000-0000-0000000000a9', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1',
        '00000000-0000-0000-0000-0000000000a1', 'service', '00000000-0000-0000-0000-0000000000f1', '2026-12-01 10:00+05:30');
SELECT booking_number FROM bookings WHERE id = '00000000-0000-0000-0000-0000000000a9';
SELECT pg_temp.expect_fail($$INSERT INTO bookings (customer_id, vendor_id, vehicle_id, domain, scheduled_start)
  VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'parts', now())$$, 'booking in parts domain');
SELECT pg_temp.expect_fail($$UPDATE bookings SET status = 'completed' WHERE id = '00000000-0000-0000-0000-0000000000a9'$$, 'complete without final total');
INSERT INTO booking_estimates (booking_id, version, subtotal_paise, tax_paise, total_paise, created_by)
VALUES ('00000000-0000-0000-0000-0000000000a9', 1, 300000, 54000, 354000, '00000000-0000-0000-0000-000000000002');
SELECT pg_temp.expect_fail($$INSERT INTO booking_estimates (booking_id, version, subtotal_paise, tax_paise, total_paise, created_by)
  VALUES ('00000000-0000-0000-0000-0000000000a9', 2, 1, 0, 1, '00000000-0000-0000-0000-000000000002')$$, 'two pending estimates');

-- Booking settlement math must hold on completion (₹3,540 job, 12% commission)
SELECT pg_temp.expect_fail($$UPDATE bookings SET status = 'completed', completed_at = now(), final_total_paise = 354000,
  commission_paise = 42480, commission_gst_paise = 7646, tcs_paise = 3000, tds_paise = 300, vendor_payout_paise = 999
  WHERE id = '00000000-0000-0000-0000-0000000000a9'$$, 'booking payout math mismatch');
UPDATE bookings SET status = 'completed', completed_at = now(), final_total_paise = 354000,
  commission_paise = 42480, commission_gst_paise = 7646, tcs_paise = 3000, tds_paise = 300, vendor_payout_paise = 300574
  WHERE id = '00000000-0000-0000-0000-0000000000a9';
UPDATE bookings SET idempotency_key = 'bk-1' WHERE id = '00000000-0000-0000-0000-0000000000a9';
SELECT pg_temp.expect_fail($$INSERT INTO bookings (customer_id, vendor_id, vehicle_id, domain, scheduled_start, idempotency_key)
  VALUES ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'service', now(), 'bk-1')$$, 'duplicate booking idempotency key');

-- Reviews update vendor + product rating aggregates via trigger
UPDATE orders SET status = 'delivered', delivered_at = now(), payment_state = 'paid' WHERE id = '00000000-0000-0000-0000-0000000000e1';
INSERT INTO reviews (author_id, vendor_id, order_id, product_id, rating) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000c1', 4);
INSERT INTO reviews (author_id, vendor_id, booking_id, rating) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a9', 5);
INSERT INTO reviews (author_id, vendor_id, order_id, rating) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000e1', 3);
SELECT 'vendor' AS what, rating_avg, rating_count FROM vendors WHERE slug = 'shree-auto'
UNION ALL SELECT 'product', rating_avg, rating_count FROM products WHERE sku = 'BP-SW-01';
SELECT pg_temp.expect_fail($$INSERT INTO reviews (author_id, vendor_id, booking_id, rating) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a9', 1)$$, 'second review of same booking');
SELECT pg_temp.expect_fail($$INSERT INTO reviews (author_id, vendor_id, rating) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', 5)$$, 'review without purchase');

INSERT INTO review_reports (review_id, reporter_id, reason) SELECT id, '00000000-0000-0000-0000-000000000002', 'fake' FROM reviews WHERE booking_id IS NOT NULL;
SELECT pg_temp.expect_fail($$INSERT INTO review_reports (review_id, reporter_id, reason) SELECT id, '00000000-0000-0000-0000-000000000002', 'spam' FROM reviews WHERE booking_id IS NOT NULL$$, 'same user reports twice');

-- Wallet can't go negative; payouts: one in flight
INSERT INTO wallets (user_id) VALUES ('00000000-0000-0000-0000-000000000001');
SELECT pg_temp.expect_fail($$UPDATE wallets SET balance_paise = balance_paise - 100$$, 'negative wallet');
INSERT INTO vendor_bank_accounts (id, vendor_id, account_holder_name, account_number_last4, ifsc, is_primary)
VALUES ('00000000-0000-0000-0000-0000000000ba', '00000000-0000-0000-0000-0000000000b1', 'Shree Auto', '4321', 'HDFC0001234', true);
INSERT INTO payouts (vendor_id, bank_account_id, amount_paise, requested_by)
VALUES ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000ba', 50000, '00000000-0000-0000-0000-000000000002');
SELECT pg_temp.expect_fail($$INSERT INTO payouts (vendor_id, bank_account_id, amount_paise, requested_by)
  VALUES ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000ba', 50000, '00000000-0000-0000-0000-000000000002')$$, 'second in-flight payout');
INSERT INTO vendor_ledger_entries (vendor_id, type, amount_paise, order_id) VALUES ('00000000-0000-0000-0000-0000000000b1', 'order_earning', 268704, '00000000-0000-0000-0000-0000000000e1');
SELECT pg_temp.expect_fail($$INSERT INTO vendor_ledger_entries (vendor_id, type, amount_paise, order_id) VALUES ('00000000-0000-0000-0000-0000000000b1', 'order_earning', 268704, '00000000-0000-0000-0000-0000000000e1')$$, 'order credited twice');
SELECT pg_temp.expect_fail($$INSERT INTO vendor_ledger_entries (vendor_id, type, amount_paise) VALUES ('00000000-0000-0000-0000-0000000000b1', 'payout', 500)$$, 'payout entry with positive sign');

-- Disputes: one open per order
INSERT INTO disputes (raised_by, raised_by_role, vendor_id, customer_id, order_id, reason, description)
VALUES ('00000000-0000-0000-0000-000000000001', 'customer', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000e1', 'wrong_or_damaged_part', 'Received pads for a different model');
SELECT pg_temp.expect_fail($$INSERT INTO disputes (raised_by, raised_by_role, vendor_id, customer_id, order_id, reason, description)
VALUES ('00000000-0000-0000-0000-000000000001', 'customer', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000e1', 'other', 'Raising it a second time')$$, 'second open dispute');

-- Soft-deleted user frees the phone number
UPDATE users SET status = 'deleted', deleted_at = now() WHERE id = '00000000-0000-0000-0000-000000000001';
INSERT INTO users (phone) VALUES ('+919800000001');
\echo 'ALL SMOKE TESTS PASSED'
ROLLBACK;
