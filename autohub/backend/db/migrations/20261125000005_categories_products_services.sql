-- migrate:up
CREATE TYPE part_type        AS ENUM ('oem', 'oes', 'aftermarket');   -- OES = original equipment supplier brand
CREATE TYPE item_condition   AS ENUM ('new', 'refurbished', 'used');
CREATE TYPE listing_status   AS ENUM ('draft', 'active', 'inactive', 'blocked');  -- blocked = admin moderation
CREATE TYPE price_type       AS ENUM ('fixed', 'starting_from', 'on_inspection');
CREATE TYPE moderation_status AS ENUM ('pending', 'approved', 'rejected');
CREATE TYPE inventory_reason AS ENUM ('restock', 'adjustment', 'order_reserved', 'order_released', 'order_fulfilled', 'return_restocked');

-- Translations stored as {"en": "...", "hi": "...", "mr": "..."}; English is mandatory.
CREATE TABLE categories (
  id         serial PRIMARY KEY,
  domain     business_domain NOT NULL,
  slug       text NOT NULL UNIQUE,
  name_i18n  jsonb NOT NULL CHECK (name_i18n ? 'en'),
  icon_url   text,
  sort_order int NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX categories_domain_idx ON categories (domain, sort_order) WHERE is_active;
CREATE TRIGGER categories_updated_at BEFORE UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE subcategories (
  id          serial PRIMARY KEY,
  category_id int NOT NULL REFERENCES categories(id),
  slug        text NOT NULL,
  name_i18n   jsonb NOT NULL CHECK (name_i18n ? 'en'),
  icon_url    text,
  sort_order  int NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (category_id, slug)
);
CREATE TRIGGER subcategories_updated_at BEFORE UPDATE ON subcategories FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE brands (
  id        serial PRIMARY KEY,
  name      text NOT NULL,
  slug      text NOT NULL UNIQUE,
  logo_url  text,
  is_vehicle_oem boolean NOT NULL DEFAULT false  -- e.g. Maruti Genuine Parts, Hyundai Mobis
);

-- ---------- Spare parts ----------
-- Money is always integer paise. GST rates are basis points (1800 = 18%).
CREATE TABLE products (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id           uuid NOT NULL REFERENCES vendors(id),
  subcategory_id      int  NOT NULL REFERENCES subcategories(id),
  brand_id            int  REFERENCES brands(id),
  sku                 text NOT NULL,
  name                text NOT NULL,
  description         text,
  part_number         text,                          -- manufacturer / OEM part number
  part_type           part_type NOT NULL,
  condition           item_condition NOT NULL DEFAULT 'new',
  mrp_paise           bigint NOT NULL CHECK (mrp_paise > 0),
  price_paise         bigint NOT NULL CHECK (price_paise > 0),
  gst_rate_bps        int NOT NULL CHECK (gst_rate_bps BETWEEN 0 AND 4000),
  hsn_code            text NOT NULL CHECK (hsn_code ~ '^[0-9]{4,8}$'),
  stock_qty           int NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
  reserved_qty        int NOT NULL DEFAULT 0 CHECK (reserved_qty >= 0),
  low_stock_threshold int NOT NULL DEFAULT 3 CHECK (low_stock_threshold >= 0),
  max_per_order       int NOT NULL DEFAULT 10 CHECK (max_per_order > 0),
  weight_grams        int CHECK (weight_grams IS NULL OR weight_grams > 0),
  warranty_months     smallint NOT NULL DEFAULT 0 CHECK (warranty_months >= 0),
  return_window_days  smallint NOT NULL DEFAULT 7 CHECK (return_window_days BETWEEN 0 AND 30),
  is_universal_fit    boolean NOT NULL DEFAULT false,  -- fits any car (e.g. wiper fluid, air freshener)
  status              listing_status NOT NULL DEFAULT 'draft',
  rating_avg          numeric(3,2) NOT NULL DEFAULT 0 CHECK (rating_avg BETWEEN 0 AND 5),
  rating_count        int NOT NULL DEFAULT 0,
  search_vector       tsvector GENERATED ALWAYS AS (
                        setweight(to_tsvector('simple', coalesce(name, '')), 'A') ||
                        setweight(to_tsvector('simple', coalesce(part_number, '') || ' ' || coalesce(sku, '')), 'A') ||
                        setweight(to_tsvector('simple', coalesce(description, '')), 'C')
                      ) STORED,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz,
  CONSTRAINT products_price_le_mrp CHECK (price_paise <= mrp_paise),
  CONSTRAINT products_reserved_le_stock CHECK (reserved_qty <= stock_qty)
);
CREATE UNIQUE INDEX products_vendor_sku_uq ON products (vendor_id, sku) WHERE deleted_at IS NULL;
CREATE INDEX products_vendor_status_idx ON products (vendor_id, status) WHERE deleted_at IS NULL;
CREATE INDEX products_browse_idx  ON products (subcategory_id, price_paise) WHERE status = 'active' AND deleted_at IS NULL;
CREATE INDEX products_brand_idx   ON products (brand_id) WHERE status = 'active';
CREATE INDEX products_search_gin  ON products USING gin (search_vector);
CREATE INDEX products_name_trgm   ON products USING gin (name gin_trgm_ops);
CREATE INDEX products_partno_idx  ON products (upper(part_number)) WHERE part_number IS NOT NULL;
CREATE INDEX products_updated_idx ON products (updated_at);   -- delta sync for offline cache
CREATE TRIGGER products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE product_images (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  url         text NOT NULL,
  public_id   text NOT NULL,             -- Cloudinary public_id for transforms/deletion
  sort_order  smallint NOT NULL DEFAULT 0,
  moderation  moderation_status NOT NULL DEFAULT 'approved',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_images_product_idx ON product_images (product_id, sort_order);

-- Which vehicles a part fits. Narrower rows (variant) beat broader ones (model / make).
CREATE TABLE product_fitments (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id  uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  make_id     int NOT NULL REFERENCES vehicle_makes(id),
  model_id    int REFERENCES vehicle_models(id),
  variant_id  int REFERENCES vehicle_variants(id),
  fuel_type   fuel_type,
  year_from   smallint CHECK (year_from IS NULL OR year_from BETWEEN 1950 AND 2100),
  year_to     smallint,
  CONSTRAINT fitment_years CHECK (year_to IS NULL OR year_from IS NULL OR year_to >= year_from),
  CONSTRAINT fitment_variant_needs_model CHECK (variant_id IS NULL OR model_id IS NOT NULL)
);
CREATE INDEX product_fitments_lookup_idx ON product_fitments (model_id, year_from, year_to);
CREATE INDEX product_fitments_make_idx   ON product_fitments (make_id) WHERE model_id IS NULL;
CREATE INDEX product_fitments_product_idx ON product_fitments (product_id);

-- Every stock change is recorded: debugging oversells and vendor disputes depends on this.
CREATE TABLE inventory_movements (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id  uuid NOT NULL REFERENCES products(id),
  delta       int NOT NULL CHECK (delta <> 0),
  reason      inventory_reason NOT NULL,
  ref_type    text,                     -- 'order_item', 'return', ...
  ref_id      uuid,
  actor_id    uuid REFERENCES users(id),
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX inventory_movements_product_idx ON inventory_movements (product_id, created_at DESC);

-- ---------- Service & decor catalog ----------
CREATE TABLE services (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id             uuid NOT NULL REFERENCES vendors(id),
  subcategory_id        int  NOT NULL REFERENCES subcategories(id),
  name                  text NOT NULL,
  description           text,
  inclusions            text[] NOT NULL DEFAULT '{}',   -- "Engine oil", "Oil filter", "30-point check"
  price_type            price_type NOT NULL DEFAULT 'fixed',
  price_paise           bigint CHECK (price_paise IS NULL OR price_paise >= 0),
  gst_rate_bps          int NOT NULL DEFAULT 1800 CHECK (gst_rate_bps BETWEEN 0 AND 4000),
  sac_code              text CHECK (sac_code IS NULL OR sac_code ~ '^[0-9]{6}$'),
  duration_minutes      int NOT NULL DEFAULT 60 CHECK (duration_minutes BETWEEN 5 AND 10080),
  applicable_fuel_types fuel_type[],                    -- NULL = all
  applicable_body_types text[],                         -- NULL = all (lets vendors price SUV vs hatchback)
  warranty_days         int NOT NULL DEFAULT 0 CHECK (warranty_days >= 0),
  advance_paise         bigint NOT NULL DEFAULT 0 CHECK (advance_paise >= 0),
  doorstep_available    boolean NOT NULL DEFAULT false,
  status                listing_status NOT NULL DEFAULT 'draft',
  rating_avg            numeric(3,2) NOT NULL DEFAULT 0,
  rating_count          int NOT NULL DEFAULT 0,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz,
  CONSTRAINT services_price_required CHECK (price_type = 'on_inspection' OR price_paise IS NOT NULL),
  CONSTRAINT services_advance_le_price CHECK (price_paise IS NULL OR advance_paise <= price_paise)
);
CREATE INDEX services_vendor_idx ON services (vendor_id, status) WHERE deleted_at IS NULL;
CREATE INDEX services_browse_idx ON services (subcategory_id, price_paise) WHERE status = 'active' AND deleted_at IS NULL;
CREATE INDEX services_name_trgm  ON services USING gin (name gin_trgm_ops);
CREATE TRIGGER services_updated_at BEFORE UPDATE ON services FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE service_images (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id  uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  url         text NOT NULL,
  public_id   text NOT NULL,
  sort_order  smallint NOT NULL DEFAULT 0,
  moderation  moderation_status NOT NULL DEFAULT 'approved',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX service_images_service_idx ON service_images (service_id, sort_order);

-- Admin-defined commission schedule (vendor override lives on vendors)
CREATE TABLE commission_rules (
  id             serial PRIMARY KEY,
  category_id    int REFERENCES categories(id),   -- NULL = domain-wide default
  domain         business_domain NOT NULL,
  rate_bps       int NOT NULL CHECK (rate_bps BETWEEN 0 AND 5000),
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_to   timestamptz,
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commission_rules_window CHECK (effective_to IS NULL OR effective_to > effective_from)
);
CREATE INDEX commission_rules_lookup_idx ON commission_rules (domain, category_id, effective_from DESC);

-- migrate:down
DROP TABLE IF EXISTS commission_rules, service_images, services, inventory_movements,
  product_fitments, product_images, products, brands, subcategories, categories;
DROP TYPE IF EXISTS inventory_reason, moderation_status, price_type, listing_status, item_condition, part_type;
