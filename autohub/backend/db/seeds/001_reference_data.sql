-- Reference data: categories (en/hi/mr), commission defaults, brands, popular Indian makes/models.
-- Idempotent: safe to re-run. Hindi/Marathi strings should be reviewed by a native speaker before launch.
BEGIN;

INSERT INTO categories (domain, slug, name_i18n, sort_order) VALUES
  ('parts',   'engine-parts',          '{"en":"Engine Parts","hi":"इंजन पार्ट्स","mr":"इंजिन पार्ट्स"}', 1),
  ('parts',   'brakes',                '{"en":"Brakes","hi":"ब्रेक","mr":"ब्रेक"}', 2),
  ('parts',   'suspension-steering',   '{"en":"Suspension & Steering","hi":"सस्पेंशन और स्टीयरिंग","mr":"सस्पेन्शन आणि स्टीअरिंग"}', 3),
  ('parts',   'electrical-batteries',  '{"en":"Electrical & Batteries","hi":"इलेक्ट्रिकल और बैटरी","mr":"इलेक्ट्रिकल आणि बॅटरी"}', 4),
  ('parts',   'filters-oils',          '{"en":"Filters & Oils","hi":"फ़िल्टर और ऑयल","mr":"फिल्टर आणि ऑइल"}', 5),
  ('parts',   'lights',                '{"en":"Lights","hi":"लाइट्स","mr":"लाइट्स"}', 6),
  ('parts',   'body-parts',            '{"en":"Body Parts","hi":"बॉडी पार्ट्स","mr":"बॉडी पार्ट्स"}', 7),
  ('parts',   'tyres-wheels',          '{"en":"Tyres & Wheels","hi":"टायर और व्हील","mr":"टायर आणि व्हील"}', 8),
  ('service', 'periodic-service',      '{"en":"Periodic Service","hi":"पीरियॉडिक सर्विस","mr":"नियमित सर्व्हिसिंग"}', 1),
  ('service', 'ac-service',            '{"en":"AC Service & Repair","hi":"एसी सर्विस और रिपेयर","mr":"एसी सर्व्हिस आणि दुरुस्ती"}', 2),
  ('service', 'denting-painting',      '{"en":"Denting & Painting","hi":"डेंटिंग और पेंटिंग","mr":"डेंटिंग आणि पेंटिंग"}', 3),
  ('service', 'mechanical-repairs',    '{"en":"Mechanical Repairs","hi":"मैकेनिकल रिपेयर","mr":"मेकॅनिकल दुरुस्ती"}', 4),
  ('service', 'tyre-wheel-care',       '{"en":"Tyre & Wheel Care","hi":"टायर और व्हील केयर","mr":"टायर आणि व्हील केअर"}', 5),
  ('service', 'wash-detailing',        '{"en":"Car Wash & Detailing","hi":"कार वॉश और डिटेलिंग","mr":"कार वॉश आणि डिटेलिंग"}', 6),
  ('service', 'inspection',            '{"en":"Car Inspection","hi":"कार इंस्पेक्शन","mr":"कार तपासणी"}', 7),
  ('decor',   'interior-styling',      '{"en":"Interior Styling","hi":"इंटीरियर स्टाइलिंग","mr":"इंटिरियर स्टायलिंग"}', 1),
  ('decor',   'exterior-styling',      '{"en":"Exterior Styling","hi":"एक्सटीरियर स्टाइलिंग","mr":"एक्सटिरियर स्टायलिंग"}', 2),
  ('decor',   'audio-electronics',     '{"en":"Audio & Electronics","hi":"ऑडियो और इलेक्ट्रॉनिक्स","mr":"ऑडिओ आणि इलेक्ट्रॉनिक्स"}', 3),
  ('decor',   'paint-protection',      '{"en":"Paint Protection (PPF & Ceramic)","hi":"पेंट प्रोटेक्शन (PPF और सिरेमिक)","mr":"पेंट प्रोटेक्शन (PPF आणि सिरॅमिक)"}', 4),
  ('decor',   'wraps-graphics',        '{"en":"Wraps & Graphics","hi":"रैप्स और ग्राफ़िक्स","mr":"रॅप्स आणि ग्राफिक्स"}', 5)
ON CONFLICT (slug) DO UPDATE SET name_i18n = EXCLUDED.name_i18n, sort_order = EXCLUDED.sort_order;

INSERT INTO subcategories (category_id, slug, name_i18n, sort_order)
SELECT c.id, s.slug, s.name_i18n::jsonb, s.sort_order
FROM (VALUES
  ('engine-parts',         'spark-plugs',        '{"en":"Spark Plugs","hi":"स्पार्क प्लग","mr":"स्पार्क प्लग"}', 1),
  ('engine-parts',         'belts-pulleys',      '{"en":"Belts & Pulleys","hi":"बेल्ट और पुली","mr":"बेल्ट आणि पुली"}', 2),
  ('engine-parts',         'gaskets-seals',      '{"en":"Gaskets & Seals","hi":"गैस्केट और सील","mr":"गॅस्केट आणि सील"}', 3),
  ('engine-parts',         'cooling-system',     '{"en":"Radiator & Cooling","hi":"रेडिएटर और कूलिंग","mr":"रेडिएटर आणि कूलिंग"}', 4),
  ('brakes',               'brake-pads',         '{"en":"Brake Pads","hi":"ब्रेक पैड","mr":"ब्रेक पॅड"}', 1),
  ('brakes',               'brake-discs',        '{"en":"Brake Discs & Drums","hi":"ब्रेक डिस्क और ड्रम","mr":"ब्रेक डिस्क आणि ड्रम"}', 2),
  ('brakes',               'brake-fluid',        '{"en":"Brake Fluid","hi":"ब्रेक फ्लूइड","mr":"ब्रेक फ्लुइड"}', 3),
  ('suspension-steering',  'shock-absorbers',    '{"en":"Shock Absorbers","hi":"शॉक एब्ज़ॉर्बर","mr":"शॉक ॲब्सॉर्बर"}', 1),
  ('suspension-steering',  'steering-parts',     '{"en":"Steering Parts","hi":"स्टीयरिंग पार्ट्स","mr":"स्टीअरिंग पार्ट्स"}', 2),
  ('electrical-batteries', 'batteries',          '{"en":"Batteries","hi":"बैटरी","mr":"बॅटरी"}', 1),
  ('electrical-batteries', 'wiper-motors-horns', '{"en":"Horns, Wipers & Motors","hi":"हॉर्न, वाइपर और मोटर","mr":"हॉर्न, वायपर आणि मोटर"}', 2),
  ('electrical-batteries', 'sensors',            '{"en":"Sensors","hi":"सेंसर","mr":"सेन्सर"}', 3),
  ('filters-oils',         'oil-filters',        '{"en":"Oil Filters","hi":"ऑयल फ़िल्टर","mr":"ऑइल फिल्टर"}', 1),
  ('filters-oils',         'air-filters',        '{"en":"Air & Cabin Filters","hi":"एयर और केबिन फ़िल्टर","mr":"एअर आणि केबिन फिल्टर"}', 2),
  ('filters-oils',         'engine-oil',         '{"en":"Engine Oil","hi":"इंजन ऑयल","mr":"इंजिन ऑइल"}', 3),
  ('filters-oils',         'coolant',            '{"en":"Coolant","hi":"कूलेंट","mr":"कूलंट"}', 4),
  ('lights',               'headlights',         '{"en":"Headlights","hi":"हेडलाइट","mr":"हेडलाइट"}', 1),
  ('lights',               'tail-lights',        '{"en":"Tail Lights","hi":"टेल लाइट","mr":"टेल लाइट"}', 2),
  ('lights',               'bulbs',              '{"en":"Bulbs & LEDs","hi":"बल्ब और एलईडी","mr":"बल्ब आणि एलईडी"}', 3),
  ('body-parts',           'bumpers',            '{"en":"Bumpers","hi":"बम्पर","mr":"बंपर"}', 1),
  ('body-parts',           'mirrors',            '{"en":"Side Mirrors","hi":"साइड मिरर","mr":"साइड मिरर"}', 2),
  ('body-parts',           'wiper-blades',       '{"en":"Wiper Blades","hi":"वाइपर ब्लेड","mr":"वायपर ब्लेड"}', 3),
  ('tyres-wheels',         'tyres',              '{"en":"Tyres","hi":"टायर","mr":"टायर"}', 1),
  ('tyres-wheels',         'alloy-wheels',       '{"en":"Alloy Wheels","hi":"अलॉय व्हील","mr":"अलॉय व्हील"}', 2),
  ('periodic-service',     'basic-service',      '{"en":"Basic Service","hi":"बेसिक सर्विस","mr":"बेसिक सर्व्हिस"}', 1),
  ('periodic-service',     'comprehensive-service','{"en":"Comprehensive Service","hi":"कम्प्लीट सर्विस","mr":"संपूर्ण सर्व्हिस"}', 2),
  ('periodic-service',     'oil-change',         '{"en":"Oil Change","hi":"ऑयल चेंज","mr":"ऑइल चेंज"}', 3),
  ('ac-service',           'ac-gas-refill',      '{"en":"AC Gas Refill","hi":"एसी गैस रिफ़िल","mr":"एसी गॅस रिफिल"}', 1),
  ('ac-service',           'ac-repair',          '{"en":"AC Repair","hi":"एसी रिपेयर","mr":"एसी दुरुस्ती"}', 2),
  ('denting-painting',     'panel-paint',        '{"en":"Panel Painting","hi":"पैनल पेंटिंग","mr":"पॅनल पेंटिंग"}', 1),
  ('denting-painting',     'full-body-paint',    '{"en":"Full Body Paint","hi":"फुल बॉडी पेंट","mr":"फुल बॉडी पेंट"}', 2),
  ('denting-painting',     'dent-removal',       '{"en":"Dent Removal","hi":"डेंट रिमूवल","mr":"डेंट काढणे"}', 3),
  ('mechanical-repairs',   'clutch-repair',      '{"en":"Clutch Repair","hi":"क्लच रिपेयर","mr":"क्लच दुरुस्ती"}', 1),
  ('mechanical-repairs',   'brake-repair',       '{"en":"Brake Repair","hi":"ब्रेक रिपेयर","mr":"ब्रेक दुरुस्ती"}', 2),
  ('mechanical-repairs',   'suspension-repair',  '{"en":"Suspension Repair","hi":"सस्पेंशन रिपेयर","mr":"सस्पेन्शन दुरुस्ती"}', 3),
  ('mechanical-repairs',   'electrical-repair',  '{"en":"Electrical Repair","hi":"इलेक्ट्रिकल रिपेयर","mr":"इलेक्ट्रिकल दुरुस्ती"}', 4),
  ('tyre-wheel-care',      'wheel-alignment',    '{"en":"Wheel Alignment & Balancing","hi":"व्हील अलाइनमेंट और बैलेंसिंग","mr":"व्हील अलाइनमेंट आणि बॅलन्सिंग"}', 1),
  ('tyre-wheel-care',      'puncture-repair',    '{"en":"Puncture Repair","hi":"पंक्चर रिपेयर","mr":"पंक्चर दुरुस्ती"}', 2),
  ('wash-detailing',       'car-wash',           '{"en":"Car Wash","hi":"कार वॉश","mr":"कार वॉश"}', 1),
  ('wash-detailing',       'interior-cleaning',  '{"en":"Interior Deep Cleaning","hi":"इंटीरियर डीप क्लीनिंग","mr":"इंटिरियर डीप क्लीनिंग"}', 2),
  ('wash-detailing',       'polishing',          '{"en":"Rubbing & Polishing","hi":"रबिंग और पॉलिशिंग","mr":"रबिंग आणि पॉलिशिंग"}', 3),
  ('inspection',           'pre-purchase',       '{"en":"Used Car Inspection","hi":"पुरानी कार इंस्पेक्शन","mr":"जुनी कार तपासणी"}', 1),
  ('inspection',           'health-check',       '{"en":"Car Health Check","hi":"कार हेल्थ चेक","mr":"कार हेल्थ चेक"}', 2),
  ('interior-styling',     'seat-covers',        '{"en":"Seat Covers","hi":"सीट कवर","mr":"सीट कव्हर"}', 1),
  ('interior-styling',     'floor-mats',         '{"en":"Floor Mats","hi":"फ़्लोर मैट","mr":"फ्लोर मॅट"}', 2),
  ('interior-styling',     'steering-covers',    '{"en":"Steering Covers","hi":"स्टीयरिंग कवर","mr":"स्टीअरिंग कव्हर"}', 3),
  ('interior-styling',     'ambient-lighting',   '{"en":"Ambient Lighting","hi":"एम्बिएंट लाइटिंग","mr":"ॲम्बियंट लाइटिंग"}', 4),
  ('exterior-styling',     'body-kits',          '{"en":"Body Kits & Spoilers","hi":"बॉडी किट और स्पॉयलर","mr":"बॉडी किट आणि स्पॉयलर"}', 1),
  ('exterior-styling',     'chrome-accessories', '{"en":"Chrome Accessories","hi":"क्रोम एक्सेसरीज़","mr":"क्रोम ॲक्सेसरीज"}', 2),
  ('exterior-styling',     'led-upgrades',       '{"en":"LED Headlight Upgrades","hi":"एलईडी हेडलाइट अपग्रेड","mr":"एलईडी हेडलाइट अपग्रेड"}', 3),
  ('audio-electronics',    'infotainment',       '{"en":"Android / Touchscreen Stereo","hi":"टचस्क्रीन स्टीरियो","mr":"टचस्क्रीन स्टिरिओ"}', 1),
  ('audio-electronics',    'speakers-amps',      '{"en":"Speakers & Amplifiers","hi":"स्पीकर और एम्प्लीफ़ायर","mr":"स्पीकर आणि ॲम्प्लिफायर"}', 2),
  ('audio-electronics',    'cameras-sensors',    '{"en":"Reverse Camera & Sensors","hi":"रिवर्स कैमरा और सेंसर","mr":"रिव्हर्स कॅमेरा आणि सेन्सर"}', 3),
  ('audio-electronics',    'dashcams',           '{"en":"Dashcams","hi":"डैशकैम","mr":"डॅशकॅम"}', 4),
  ('paint-protection',     'ceramic-coating',    '{"en":"Ceramic Coating","hi":"सिरेमिक कोटिंग","mr":"सिरॅमिक कोटिंग"}', 1),
  ('paint-protection',     'ppf',                '{"en":"Paint Protection Film","hi":"पेंट प्रोटेक्शन फ़िल्म","mr":"पेंट प्रोटेक्शन फिल्म"}', 2),
  ('paint-protection',     'teflon-coating',     '{"en":"Teflon Coating","hi":"टेफ़्लॉन कोटिंग","mr":"टेफ्लॉन कोटिंग"}', 3),
  ('wraps-graphics',       'full-wrap',          '{"en":"Full Body Wrap","hi":"फुल बॉडी रैप","mr":"फुल बॉडी रॅप"}', 1),
  ('wraps-graphics',       'roof-wrap',          '{"en":"Roof & Bonnet Wrap","hi":"रूफ और बोनट रैप","mr":"रूफ आणि बॉनेट रॅप"}', 2),
  ('wraps-graphics',       'sun-film',           '{"en":"Window Sun Film","hi":"विंडो सन फ़िल्म","mr":"विंडो सन फिल्म"}', 3)
) AS s(cat_slug, slug, name_i18n, sort_order)
JOIN categories c ON c.slug = s.cat_slug
ON CONFLICT (category_id, slug) DO UPDATE SET name_i18n = EXCLUDED.name_i18n, sort_order = EXCLUDED.sort_order;

-- Default commission per domain (category-level rules can override; vendor override beats both)
INSERT INTO commission_rules (domain, category_id, rate_bps)
SELECT d.domain::business_domain, NULL, d.rate
FROM (VALUES ('parts', 800), ('service', 1200), ('decor', 1000)) AS d(domain, rate)
WHERE NOT EXISTS (SELECT 1 FROM commission_rules r WHERE r.domain = d.domain::business_domain AND r.category_id IS NULL);

INSERT INTO brands (name, slug, is_vehicle_oem) VALUES
  ('Maruti Genuine Parts', 'maruti-genuine-parts', true),
  ('Hyundai Mobis', 'hyundai-mobis', true),
  ('Tata Genuine Parts', 'tata-genuine-parts', true),
  ('Mahindra Genuine Spares', 'mahindra-genuine-spares', true),
  ('Bosch', 'bosch', false),
  ('Uno Minda', 'uno-minda', false),
  ('Lumax', 'lumax', false),
  ('Exide', 'exide', false),
  ('Amaron', 'amaron', false),
  ('Castrol', 'castrol', false),
  ('Mobil', 'mobil', false),
  ('Valeo', 'valeo', false),
  ('Brakes India', 'brakes-india', false),
  ('Rane', 'rane', false),
  ('Mahle', 'mahle', false),
  ('NGK', 'ngk', false),
  ('Gabriel', 'gabriel', false),
  ('MRF', 'mrf', false),
  ('Apollo Tyres', 'apollo-tyres', false),
  ('CEAT', 'ceat', false)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO vehicle_makes (name, slug, sort_order) VALUES
  ('Maruti Suzuki', 'maruti-suzuki', 1), ('Hyundai', 'hyundai', 2), ('Tata', 'tata', 3),
  ('Mahindra', 'mahindra', 4), ('Kia', 'kia', 5), ('Toyota', 'toyota', 6), ('Honda', 'honda', 7),
  ('Renault', 'renault', 8), ('Skoda', 'skoda', 9), ('Volkswagen', 'volkswagen', 10), ('MG', 'mg', 11)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO vehicle_models (make_id, name, slug, body_type)
SELECT mk.id, m.name, m.slug, m.body
FROM (VALUES
  ('maruti-suzuki', 'Swift', 'swift', 'hatchback'), ('maruti-suzuki', 'Baleno', 'baleno', 'hatchback'),
  ('maruti-suzuki', 'Dzire', 'dzire', 'sedan'),     ('maruti-suzuki', 'Wagon R', 'wagon-r', 'hatchback'),
  ('maruti-suzuki', 'Alto K10', 'alto-k10', 'hatchback'), ('maruti-suzuki', 'Brezza', 'brezza', 'suv'),
  ('maruti-suzuki', 'Ertiga', 'ertiga', 'muv'),     ('maruti-suzuki', 'Fronx', 'fronx', 'suv'),
  ('hyundai', 'i20', 'i20', 'hatchback'), ('hyundai', 'Creta', 'creta', 'suv'),
  ('hyundai', 'Venue', 'venue', 'suv'),   ('hyundai', 'Verna', 'verna', 'sedan'),
  ('hyundai', 'Grand i10 Nios', 'grand-i10-nios', 'hatchback'),
  ('tata', 'Nexon', 'nexon', 'suv'), ('tata', 'Punch', 'punch', 'suv'), ('tata', 'Tiago', 'tiago', 'hatchback'),
  ('tata', 'Altroz', 'altroz', 'hatchback'), ('tata', 'Harrier', 'harrier', 'suv'),
  ('mahindra', 'XUV700', 'xuv700', 'suv'), ('mahindra', 'Scorpio-N', 'scorpio-n', 'suv'),
  ('mahindra', 'Thar', 'thar', 'suv'), ('mahindra', 'Bolero', 'bolero', 'suv'), ('mahindra', 'XUV 3XO', 'xuv-3xo', 'suv'),
  ('kia', 'Seltos', 'seltos', 'suv'), ('kia', 'Sonet', 'sonet', 'suv'), ('kia', 'Carens', 'carens', 'muv'),
  ('toyota', 'Innova Crysta', 'innova-crysta', 'muv'), ('toyota', 'Fortuner', 'fortuner', 'suv'),
  ('toyota', 'Glanza', 'glanza', 'hatchback'),
  ('honda', 'City', 'city', 'sedan'), ('honda', 'Amaze', 'amaze', 'sedan'), ('honda', 'Elevate', 'elevate', 'suv'),
  ('renault', 'Kwid', 'kwid', 'hatchback'), ('renault', 'Kiger', 'kiger', 'suv'),
  ('skoda', 'Kushaq', 'kushaq', 'suv'), ('skoda', 'Slavia', 'slavia', 'sedan'),
  ('volkswagen', 'Virtus', 'virtus', 'sedan'), ('volkswagen', 'Taigun', 'taigun', 'suv'),
  ('mg', 'Hector', 'hector', 'suv'), ('mg', 'Windsor EV', 'windsor-ev', 'suv')
) AS m(make_slug, name, slug, body)
JOIN vehicle_makes mk ON mk.slug = m.make_slug
ON CONFLICT (make_id, slug) DO NOTHING;

-- Example variants (fill the rest from a fitment dataset or admin panel)
INSERT INTO vehicle_variants (model_id, name, fuel_type, transmission, engine_cc, year_from, year_to)
SELECT vm.id, v.name, v.fuel::fuel_type, v.trans::transmission_type, v.cc, v.y_from, v.y_to
FROM (VALUES
  ('swift', 'LXi/VXi/ZXi 1.2 K-Series', 'petrol', 'manual', 1197, 2018, 2024),
  ('swift', 'VXi/ZXi AMT 1.2 K-Series', 'petrol', 'amt',    1197, 2018, 2024),
  ('swift', 'LXi/VXi/ZXi 1.2 Z-Series', 'petrol', 'manual', 1197, 2024, NULL),
  ('swift', 'VXi CNG 1.2 Z-Series',     'cng',    'manual', 1197, 2024, NULL),
  ('creta', '1.5 MPi',                  'petrol', 'manual', 1497, 2020, NULL),
  ('creta', '1.5 CRDi',                 'diesel', 'manual', 1493, 2020, NULL),
  ('creta', '1.5 CRDi AT',              'diesel', 'automatic', 1493, 2020, NULL),
  ('nexon', '1.2 Turbo Petrol',         'petrol', 'manual', 1199, 2017, NULL),
  ('nexon', '1.5 Diesel',               'diesel', 'manual', 1497, 2017, NULL)
) AS v(model_slug, name, fuel, trans, cc, y_from, y_to)
JOIN vehicle_models vm ON vm.slug = v.model_slug
WHERE NOT EXISTS (SELECT 1 FROM vehicle_variants x WHERE x.model_id = vm.id AND x.name = v.name);

COMMIT;
