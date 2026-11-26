-- DEMO DATA for local testing. Never load this into production.
-- Idempotent (fixed ids + ON CONFLICT). Requires 001_reference_data.sql.
--
-- Test logins (OTP is shown in the API response / log while OTP_DEV_ECHO=true):
--   Customer            +919000000001   Rahul Patil   (Swift 2021, MH12AB1234)
--   Vendor (parts+svc)  +919000000002   Shree Auto Parts & Service, Kothrud
--   Vendor (decor)      +919000000004   GlossUp Car Decor, Baner
--   Vendor (service)    +919000000005   Pitstop Car Care, Viman Nagar
--   Admin               +919000000003   (admin app)
BEGIN;

-- ---------- users ----------
INSERT INTO users (id, phone, phone_verified_at, full_name, email, admin_role) VALUES
  ('d0000000-0000-4000-8000-000000000001', '+919000000001', now(), 'Rahul Patil',     'rahul@example.com',  NULL),
  ('d0000000-0000-4000-8000-000000000002', '+919000000002', now(), 'Suresh Kulkarni', 'suresh@example.com', NULL),
  ('d0000000-0000-4000-8000-000000000003', '+919000000003', now(), 'Priya Admin',     'admin@example.com',  'super_admin'),
  ('d0000000-0000-4000-8000-000000000004', '+919000000004', now(), 'Amit Shah',       'amit@example.com',   NULL),
  ('d0000000-0000-4000-8000-000000000005', '+919000000005', now(), 'Neha Joshi',      'neha@example.com',   NULL)
ON CONFLICT (id) DO NOTHING;
INSERT INTO wallets (user_id, balance_paise)
SELECT id, CASE WHEN id = 'd0000000-0000-4000-8000-000000000001' THEN 15000 ELSE 0 END FROM users
WHERE id::text LIKE 'd0000000-0000-4000-8000-00000000000%'
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO vehicles (id, user_id, make_id, model_id, variant_id, manufacture_year, fuel_type, transmission, registration_number, nickname, odometer_km, is_default)
SELECT 'd0000000-0000-4000-8000-0000000000a1', 'd0000000-0000-4000-8000-000000000001', m.make_id, m.id,
       (SELECT id FROM vehicle_variants WHERE model_id = m.id AND name = 'LXi/VXi/ZXi 1.2 K-Series'),
       2021, 'petrol', 'manual', 'MH12AB1234', 'Daily Swift', 42000, true
FROM vehicle_models m WHERE m.slug = 'swift'
ON CONFLICT (id) DO NOTHING;
INSERT INTO vehicles (id, user_id, make_id, model_id, manufacture_year, fuel_type, transmission, registration_number, nickname, odometer_km, is_default)
SELECT 'd0000000-0000-4000-8000-0000000000a2', 'd0000000-0000-4000-8000-000000000001', m.make_id, m.id,
       2022, 'diesel', 'automatic', 'MH14CD5678', 'Family Creta', 31000, false
FROM vehicle_models m WHERE m.slug = 'creta'
ON CONFLICT (id) DO NOTHING;

INSERT INTO addresses (id, user_id, label, contact_name, contact_phone, line1, line2, landmark, city, state, pincode, location, is_default)
VALUES ('d0000000-0000-4000-8000-0000000000c1', 'd0000000-0000-4000-8000-000000000001', 'home', 'Rahul Patil', '+919000000001',
        'Flat 302, Sai Residency', 'Karve Nagar', 'Near Kamins Hospital', 'Pune', 'Maharashtra', '411052',
        ST_SetSRID(ST_MakePoint(73.8203, 18.4893), 4326)::geography, true)
ON CONFLICT (id) DO NOTHING;

-- ---------- vendors ----------
INSERT INTO vendors (id, owner_user_id, business_name, slug, description, business_domains, status, reviewed_by, reviewed_at, submitted_at,
                     legal_name, gstin, pan, phone, whatsapp_phone, email, address_line1, address_line2, city, state, pincode, location,
                     delivery_radius_km, offers_doorstep, cod_enabled, logo_url, cover_url)
VALUES
  ('d0000000-0000-4000-8000-0000000000b1', 'd0000000-0000-4000-8000-000000000002', 'Shree Auto Parts & Service', 'shree-auto',
   'Genuine and OES spares for Maruti, Hyundai and Tata, plus a 4-bay service workshop. 20 years in Kothrud.',
   '{parts,service}', 'approved', 'd0000000-0000-4000-8000-000000000003', now(), now(),
   'Shree Auto Parts', '27AAPFU0939F1ZV', 'AAPFU0939F', '+919000000002', '+919000000002', 'shree@example.com',
   'Shop 4, Paud Road', 'Kothrud', 'Pune', 'Maharashtra', '411038', ST_SetSRID(ST_MakePoint(73.8077, 18.5074), 4326)::geography,
   12, false, true, 'https://placehold.co/240x240/png?text=Shree', 'https://placehold.co/960x400/png?text=Shree+Auto'),
  ('d0000000-0000-4000-8000-0000000000b2', 'd0000000-0000-4000-8000-000000000004', 'GlossUp Car Decor', 'glossup-decor',
   'Ceramic coating, PPF, seat covers, Android stereos and ambient lighting.',
   '{decor}', 'approved', 'd0000000-0000-4000-8000-000000000003', now(), now(),
   'GlossUp Detailing LLP', '27ABCDE1234F1Z5', 'ABCDE1234F', '+919000000004', NULL, 'amit@example.com',
   'Baner Road', 'Baner', 'Pune', 'Maharashtra', '411045', ST_SetSRID(ST_MakePoint(73.7868, 18.5590), 4326)::geography,
   NULL, false, false, 'https://placehold.co/240x240/png?text=GlossUp', 'https://placehold.co/960x400/png?text=GlossUp'),
  ('d0000000-0000-4000-8000-0000000000b3', 'd0000000-0000-4000-8000-000000000005', 'Pitstop Car Care', 'pitstop-care',
   'Express service, washing and detailing. Doorstep wash available.',
   '{service}', 'approved', 'd0000000-0000-4000-8000-000000000003', now(), now(),
   'Pitstop Car Care', NULL, 'AFGPJ1234K', '+919000000005', NULL, 'neha@example.com',
   'Lane 5, Viman Nagar', NULL, 'Pune', 'Maharashtra', '411014', ST_SetSRID(ST_MakePoint(73.9143, 18.5679), 4326)::geography,
   NULL, true, false, 'https://placehold.co/240x240/png?text=Pitstop', 'https://placehold.co/960x400/png?text=Pitstop')
ON CONFLICT (id) DO NOTHING;

INSERT INTO vendor_members (vendor_id, user_id, role) VALUES
  ('d0000000-0000-4000-8000-0000000000b1', 'd0000000-0000-4000-8000-000000000002', 'owner'),
  ('d0000000-0000-4000-8000-0000000000b2', 'd0000000-0000-4000-8000-000000000004', 'owner'),
  ('d0000000-0000-4000-8000-0000000000b3', 'd0000000-0000-4000-8000-000000000005', 'owner')
ON CONFLICT DO NOTHING;

INSERT INTO vendor_bank_accounts (id, vendor_id, account_holder_name, account_number_last4, ifsc, bank_name, is_primary, verified_at) VALUES
  ('d0000000-0000-4000-8000-0000000000e1', 'd0000000-0000-4000-8000-0000000000b1', 'Shree Auto Parts', '4321', 'HDFC0001234', 'HDFC Bank', true, now())
ON CONFLICT (id) DO NOTHING;

-- Working hours: weekday 0 = Sunday
INSERT INTO vendor_working_hours (vendor_id, weekday, opens_at, closes_at, slot_minutes, capacity_per_slot)
SELECT 'd0000000-0000-4000-8000-0000000000b1'::uuid, wd, o::time, c::time, 60, 3
FROM generate_series(1, 6) wd, (VALUES ('09:30', '13:30'), ('14:30', '19:30')) AS h(o, c)
UNION ALL
SELECT 'd0000000-0000-4000-8000-0000000000b3'::uuid, wd, '08:00', '20:00', 60, 2 FROM generate_series(0, 6) wd
UNION ALL
SELECT 'd0000000-0000-4000-8000-0000000000b2'::uuid, wd, '10:00', '19:00', 120, 1 FROM generate_series(0, 6) wd WHERE wd <> 1
ON CONFLICT (vendor_id, weekday, opens_at) DO NOTHING;

SELECT generate_vendor_slots(14);

-- ---------- spare parts (Shree) ----------
INSERT INTO products (id, vendor_id, subcategory_id, brand_id, sku, name, description, part_number, part_type, mrp_paise, price_paise,
                      gst_rate_bps, hsn_code, stock_qty, low_stock_threshold, max_per_order, warranty_months, return_window_days, is_universal_fit, status)
SELECT p.id::uuid, 'd0000000-0000-4000-8000-0000000000b1', s.id, b.id, p.sku, p.name, p.descr, p.part_no, p.ptype::part_type,
       p.mrp, p.price, 1800, p.hsn, p.stock, 3, p.maxq, p.warranty, 7, p.universal, 'active'
FROM (VALUES
  ('d0000000-0000-4000-8000-000000000101', 'brake-pads',      'bosch',               'BP-SW-01',  'Front Brake Pad Set',               'Ceramic compound, low dust, quiet braking. Set of 4 pads.', '55810M68K00', 'oes', 180000, 149900, '87083000', 18, 4, 6, false),
  ('d0000000-0000-4000-8000-000000000102', 'oil-filters',     'maruti-genuine-parts','OF-MS-01',  'Engine Oil Filter',                 'Genuine Maruti oil filter for K-Series engines.',            '16510M68K00', 'oem',  35000,  29900, '84212300', 40, 6, 0, false),
  ('d0000000-0000-4000-8000-000000000103', 'air-filters',     'bosch',               'AF-SW-01',  'Engine Air Filter',                 'High-flow paper element. Replace every 10,000 km.',          '13780M68K00', 'oes',  65000,  54900, '84213100', 25, 6, 0, false),
  ('d0000000-0000-4000-8000-000000000104', 'spark-plugs',     'ngk',                 'SP-NGK-IR', 'Iridium Spark Plug',                'Iridium tip, 60,000 km life. Sold individually.',            'ILZKR7B11',   'aftermarket', 79000, 64900, '85111000', 60, 8, 0, false),
  ('d0000000-0000-4000-8000-000000000105', 'batteries',       'exide',               'BT-EX-35',  'Exide Mileage 35Ah Battery',        'Maintenance-free, 48-month warranty (24 free + 24 pro-rata).', 'ML38B20LMF', 'aftermarket', 549900, 489900, '85071000', 6, 1, 48, false),
  ('d0000000-0000-4000-8000-000000000106', 'engine-oil',      'castrol',             'EO-CM-35',  'Castrol Magnatec 5W-30 (3.5 L)',    'Fully synthetic, suits most petrol hatchbacks and sedans.',  '3427285',     'aftermarket', 320000, 279900, '27101980', 20, 3, 0, true),
  ('d0000000-0000-4000-8000-000000000107', 'brake-pads',      'hyundai-mobis',       'BP-CR-01',  'Creta Front Brake Pads',            'Hyundai Mobis genuine pads for Creta (2020 onwards).',       '58101BVA00', 'oem', 290000, 259900, '87083000', 2, 2, 6, false),
  ('d0000000-0000-4000-8000-000000000108', 'shock-absorbers', 'gabriel',             'SA-SW-F',   'Front Shock Absorber (each)',       'Gas-charged strut, OE-equivalent ride quality.',             'G60431',      'aftermarket', 340000, 289900, '87088000', 8, 2, 12, false),
  ('d0000000-0000-4000-8000-000000000109', 'bulbs',           'uno-minda',           'BL-H4-01',  'H4 Halogen Headlight Bulb 60/55W',  'Fits most Indian cars with H4 headlamps.',                   'H4-12V-6055', 'aftermarket', 45000, 34900, '85392120', 50, 4, 0, true),
  ('d0000000-0000-4000-8000-000000000110', 'air-filters',     'bosch',               'CF-NX-01',  'Nexon Cabin AC Filter',             'Activated carbon, removes dust and odour.',                  'F002H23510', 'oes', 79900, 59900, '84213100', 12, 4, 0, false),
  ('d0000000-0000-4000-8000-000000000111', 'wiper-blades',    'bosch',               'WB-BS-2416','Bosch Clear Advantage Wiper Set',   'Frameless 24" + 16" pair.',                                   '3397016270', 'aftermarket', 99900, 74900, '85124000', 15, 4, 0, true),
  ('d0000000-0000-4000-8000-000000000112', 'coolant',         'mahle',               'CL-MH-1L',  'Long-Life Coolant 1 L (ready mix)', 'Ethylene-glycol based, pink. Do not mix with green coolant.', 'MCL-1000',    'aftermarket', 49900, 39900, '38200000', 30, 4, 0, true)
) AS p(id, sub, brand, sku, name, descr, part_no, ptype, mrp, price, hsn, stock, maxq, warranty, universal)
JOIN subcategories s ON s.slug = p.sub
JOIN brands b ON b.slug = p.brand
ON CONFLICT (id) DO NOTHING;

INSERT INTO product_images (product_id, url, public_id, sort_order)
SELECT p.id, 'https://placehold.co/600x600/png?text=' || replace(left(p.name, 24), ' ', '+'), 'demo/' || p.sku, 0
FROM products p WHERE p.vendor_id = 'd0000000-0000-4000-8000-0000000000b1'
  AND NOT EXISTS (SELECT 1 FROM product_images i WHERE i.product_id = p.id);

INSERT INTO product_fitments (product_id, make_id, model_id, year_from, year_to)
SELECT f.pid::uuid, m.make_id, m.id, f.y_from::smallint, f.y_to::smallint
FROM (VALUES
  ('d0000000-0000-4000-8000-000000000101', 'swift', 2018, NULL), ('d0000000-0000-4000-8000-000000000101', 'dzire', 2018, NULL),
  ('d0000000-0000-4000-8000-000000000102', 'swift', 2018, NULL), ('d0000000-0000-4000-8000-000000000102', 'baleno', 2019, NULL),
  ('d0000000-0000-4000-8000-000000000102', 'dzire', 2018, NULL), ('d0000000-0000-4000-8000-000000000102', 'ertiga', 2018, NULL),
  ('d0000000-0000-4000-8000-000000000103', 'swift', 2018, NULL), ('d0000000-0000-4000-8000-000000000103', 'dzire', 2018, NULL),
  ('d0000000-0000-4000-8000-000000000104', 'swift', 2018, NULL), ('d0000000-0000-4000-8000-000000000104', 'baleno', 2019, NULL),
  ('d0000000-0000-4000-8000-000000000105', 'swift', 2010, NULL), ('d0000000-0000-4000-8000-000000000105', 'wagon-r', 2010, NULL),
  ('d0000000-0000-4000-8000-000000000105', 'i20', 2014, NULL),   ('d0000000-0000-4000-8000-000000000105', 'baleno', 2015, NULL),
  ('d0000000-0000-4000-8000-000000000107', 'creta', 2020, NULL),
  ('d0000000-0000-4000-8000-000000000108', 'swift', 2018, NULL),
  ('d0000000-0000-4000-8000-000000000110', 'nexon', 2017, NULL)
) AS f(pid, model, y_from, y_to)
JOIN vehicle_models m ON m.slug = f.model
WHERE NOT EXISTS (SELECT 1 FROM product_fitments x WHERE x.product_id = f.pid::uuid AND x.model_id = m.id);

INSERT INTO inventory_movements (product_id, delta, reason, note)
SELECT id, stock_qty, 'restock', 'Opening stock (demo)' FROM products p
WHERE vendor_id = 'd0000000-0000-4000-8000-0000000000b1' AND stock_qty > 0
  AND NOT EXISTS (SELECT 1 FROM inventory_movements m WHERE m.product_id = p.id);

-- ---------- services & decor ----------
INSERT INTO services (id, vendor_id, subcategory_id, name, description, inclusions, price_type, price_paise, gst_rate_bps, sac_code,
                      duration_minutes, applicable_body_types, warranty_days, advance_paise, doorstep_available, status)
SELECT s.id::uuid, s.vendor::uuid, sc.id, s.name, s.descr, s.incl::text[], s.ptype::price_type, s.price, 1800, '998714',
       s.mins, s.body::text[], s.warranty, s.advance, s.doorstep, 'active'
FROM (VALUES
  ('d0000000-0000-4000-8000-000000000201', 'd0000000-0000-4000-8000-0000000000b1', 'basic-service', 'Basic Service (Hatchback / Sedan)',
   'Every 10,000 km or 6 months.', '{"Engine oil replacement","Oil filter","Air filter cleaning","Coolant top-up","15-point check"}', 'fixed', 299900, 180, '{hatchback,sedan}', 30, 20000, false),
  ('d0000000-0000-4000-8000-000000000202', 'd0000000-0000-4000-8000-0000000000b1', 'comprehensive-service', 'Comprehensive Service (Hatchback / Sedan)',
   'Every 20,000 km or yearly.', '{"Everything in Basic","Spark plugs","Brake cleaning","AC filter","Wheel rotation","40-point check"}', 'fixed', 549900, 300, '{hatchback,sedan}', 30, 50000, false),
  ('d0000000-0000-4000-8000-000000000203', 'd0000000-0000-4000-8000-0000000000b1', 'basic-service', 'Basic Service (SUV / MUV)',
   'Every 10,000 km or 6 months.', '{"Engine oil replacement","Oil filter","Air filter cleaning","Coolant top-up","15-point check"}', 'fixed', 399900, 180, '{suv,muv}', 30, 20000, false),
  ('d0000000-0000-4000-8000-000000000204', 'd0000000-0000-4000-8000-0000000000b1', 'ac-gas-refill', 'AC Gas Refill (R134a)',
   'Leak test and refill up to 600 g.', '{"Leak test","Gas up to 600 g","Cooling check"}', 'fixed', 149900, 90, NULL, 30, 20000, false),
  ('d0000000-0000-4000-8000-000000000205', 'd0000000-0000-4000-8000-0000000000b1', 'wheel-alignment', 'Wheel Alignment & Balancing',
   'Computerised 3D alignment.', '{"Alignment","Balancing (4 wheels)","Tyre pressure"}', 'fixed', 79900, 60, NULL, 0, 0, false),
  ('d0000000-0000-4000-8000-000000000206', 'd0000000-0000-4000-8000-0000000000b1', 'suspension-repair', 'Suspension Noise Inspection',
   'Diagnosis of knocking / rattling noises. Estimate shared before any work.', '{"Test drive","Lift inspection","Photo report"}', 'on_inspection', NULL, 60, NULL, 0, 0, false),
  ('d0000000-0000-4000-8000-000000000207', 'd0000000-0000-4000-8000-0000000000b1', 'brake-repair', 'Brake Inspection & Repair',
   'Squeaking, vibration or soft pedal.', '{"Brake inspection","Photo report","Estimate"}', 'on_inspection', NULL, 60, NULL, 0, 0, false),
  ('d0000000-0000-4000-8000-000000000211', 'd0000000-0000-4000-8000-0000000000b3', 'car-wash', 'Foam Wash (Exterior + Interior Vacuum)',
   '45-minute wash.', '{"Foam wash","Tyre dressing","Interior vacuum"}', 'fixed', 49900, 45, NULL, 0, 0, true),
  ('d0000000-0000-4000-8000-000000000212', 'd0000000-0000-4000-8000-0000000000b3', 'interior-cleaning', 'Interior Deep Cleaning',
   'Seats, roof liner, carpets, dashboard.', '{"Shampoo seats","Roof liner","Carpets","Dashboard polish"}', 'fixed', 199900, 180, NULL, 0, 20000, false),
  ('d0000000-0000-4000-8000-000000000213', 'd0000000-0000-4000-8000-0000000000b3', 'polishing', 'Rubbing & Polishing',
   'Removes light scratches and swirl marks.', '{"Clay bar","3-step polish","Wax"}', 'fixed', 249900, 240, NULL, 0, 30000, false),
  ('d0000000-0000-4000-8000-000000000214', 'd0000000-0000-4000-8000-0000000000b3', 'basic-service', 'Express Basic Service',
   'Done in 90 minutes while you wait.', '{"Engine oil","Oil filter","Top-ups","10-point check"}', 'fixed', 279900, 90, '{hatchback,sedan}', 15, 20000, false),
  ('d0000000-0000-4000-8000-000000000221', 'd0000000-0000-4000-8000-0000000000b2', 'ceramic-coating', '9H Ceramic Coating',
   '3-year coating with paint correction. Price for hatchbacks; SUVs quoted on inspection.', '{"Paint correction","2 layers 9H","3-year warranty card"}', 'starting_from', 1499900, 480, NULL, 1095, 100000, false),
  ('d0000000-0000-4000-8000-000000000222', 'd0000000-0000-4000-8000-0000000000b2', 'seat-covers', 'Custom-fit Seat Covers (PU leather)',
   'Model-specific stitching, 12 colours.', '{"Front + rear","Headrest covers","Fitting"}', 'starting_from', 699900, 120, NULL, 365, 50000, false),
  ('d0000000-0000-4000-8000-000000000223', 'd0000000-0000-4000-8000-0000000000b2', 'infotainment', '9" Android Stereo with Install',
   'Wireless CarPlay / Android Auto, 4+64 GB, reverse camera input.', '{"Stereo unit","Frame + harness","Installation"}', 'fixed', 999900, 120, NULL, 365, 50000, false),
  ('d0000000-0000-4000-8000-000000000224', 'd0000000-0000-4000-8000-0000000000b2', 'ppf', 'Paint Protection Film (PPF)',
   'Self-healing TPU film. Quoted after inspection.', '{"Inspection","Quote"}', 'on_inspection', NULL, 60, NULL, 0, 0, false)
) AS s(id, vendor, sub, name, descr, incl, ptype, price, mins, body, warranty, advance, doorstep)
JOIN subcategories sc ON sc.slug = s.sub
ON CONFLICT (id) DO NOTHING;

INSERT INTO service_images (service_id, url, public_id)
SELECT s.id, 'https://placehold.co/800x450/png?text=' || replace(left(s.name, 22), ' ', '+'), 'demo/svc-' || s.id
FROM services s WHERE s.vendor_id::text LIKE 'd0000000-%' AND NOT EXISTS (SELECT 1 FROM service_images i WHERE i.service_id = s.id);

-- ---------- a week of history for Shree (dashboard chart, earnings, ratings) ----------
-- Completed basic services, settled at 12% commission + 18% GST on it, 1% TCS and 0.1% TDS on the taxable value.
WITH h AS (
  SELECT n, ('d0000000-0000-4000-8000-0000000003' || lpad(n::text, 2, '0'))::uuid AS id,
         date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') - make_interval(days => n) + interval '11 hours' AS local_start,
         (ARRAY[299900, 549900, 149900, 379800, 299900, 229800])[n] AS gross
  FROM generate_series(1, 6) n
), calc AS (
  SELECT h.*, (h.local_start AT TIME ZONE 'Asia/Kolkata') AS starts_at,
         round(gross * 10000.0 / 11800) AS taxable,
         round(gross * 0.12) AS commission
  FROM h
)
INSERT INTO bookings (id, customer_id, vendor_id, vehicle_id, domain, scheduled_start, status, quoted_total_paise, final_total_paise,
                      amount_paid_paise, payment_state, commission_bps, commission_paise, commission_gst_paise, tcs_paise, tds_paise,
                      vendor_payout_paise, confirmed_at, started_at, completed_at, created_at)
SELECT id, 'd0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-0000000000b1', 'd0000000-0000-4000-8000-0000000000a1',
       'service', starts_at, 'completed', gross, gross, gross, 'paid', 1200, commission, round(commission * 0.18),
       round(taxable * 0.01), round(taxable * 0.001),
       gross - commission - round(commission * 0.18) - round(taxable * 0.01) - round(taxable * 0.001),
       starts_at - interval '1 day', starts_at, starts_at + interval '3 hours', starts_at - interval '2 days'
FROM calc
ON CONFLICT (id) DO NOTHING;

INSERT INTO booking_services (booking_id, service_id, name_snapshot, price_type, price_paise, gst_rate_bps)
SELECT b.id, 'd0000000-0000-4000-8000-000000000201', 'Basic Service (Hatchback / Sedan)', 'fixed', b.final_total_paise, 1800
FROM bookings b WHERE b.id::text LIKE 'd0000000-0000-4000-8000-0000000003%'
ON CONFLICT DO NOTHING;

INSERT INTO vendor_ledger_entries (vendor_id, type, amount_paise, booking_id, description, available_at)
SELECT vendor_id, 'booking_earning', vendor_payout_paise, id, 'Booking ' || booking_number, completed_at + interval '48 hours'
FROM bookings b WHERE b.id::text LIKE 'd0000000-0000-4000-8000-0000000003%'
ON CONFLICT DO NOTHING;

INSERT INTO reviews (author_id, vendor_id, booking_id, rating, body)
SELECT 'd0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-0000000000b1', b.id,
       (ARRAY[5, 4, 5, 5, 4, 5])[row_number() OVER (ORDER BY b.id)],
       (ARRAY['Explained everything with photos before starting.', 'Good work, slight delay.', 'AC is ice cold now!',
              'Fair pricing, genuine parts.', 'Friendly staff.', 'Car feels new. Will come back.'])[row_number() OVER (ORDER BY b.id)]
FROM bookings b WHERE b.id::text LIKE 'd0000000-0000-4000-8000-0000000003%'
ON CONFLICT DO NOTHING;

INSERT INTO vendor_daily_stats (vendor_id, day, profile_views, listing_views, search_impressions, call_clicks, chat_starts)
SELECT 'd0000000-0000-4000-8000-0000000000b1', (now() AT TIME ZONE 'Asia/Kolkata')::date - n,
       120 + n * 17 % 60, 300 + n * 29 % 120, 1500 + n * 97 % 400, 6 + n % 5, 3 + n % 4
FROM generate_series(0, 6) n
ON CONFLICT (vendor_id, day) DO NOTHING;

COMMIT;
