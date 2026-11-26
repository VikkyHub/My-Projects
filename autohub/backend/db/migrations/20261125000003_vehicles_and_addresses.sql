-- migrate:up
-- Master vehicle catalog (admin-managed). Drives fitment search.
CREATE TABLE vehicle_makes (
  id         serial PRIMARY KEY,
  name       text NOT NULL,
  slug       text NOT NULL UNIQUE,
  logo_url   text,
  is_active  boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0
);

CREATE TABLE vehicle_models (
  id         serial PRIMARY KEY,
  make_id    int NOT NULL REFERENCES vehicle_makes(id),
  name       text NOT NULL,
  slug       text NOT NULL,
  body_type  text,                              -- hatchback, sedan, suv, muv, pickup...
  is_active  boolean NOT NULL DEFAULT true,
  UNIQUE (make_id, slug)
);

CREATE TABLE vehicle_variants (
  id           serial PRIMARY KEY,
  model_id     int NOT NULL REFERENCES vehicle_models(id),
  name         text NOT NULL,                   -- e.g. "VXi 1.2 K-Series"
  fuel_type    fuel_type NOT NULL,
  transmission transmission_type,
  engine_cc    int CHECK (engine_cc IS NULL OR engine_cc BETWEEN 50 AND 10000),
  year_from    smallint NOT NULL CHECK (year_from BETWEEN 1950 AND 2100),
  year_to      smallint CHECK (year_to IS NULL OR year_to >= year_from),  -- NULL = still on sale
  is_active    boolean NOT NULL DEFAULT true
);
CREATE INDEX vehicle_variants_model_idx ON vehicle_variants (model_id);

-- Customer garage
CREATE TABLE vehicles (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  make_id             int NOT NULL REFERENCES vehicle_makes(id),
  model_id            int NOT NULL REFERENCES vehicle_models(id),
  variant_id          int REFERENCES vehicle_variants(id),          -- optional, sharper fitment
  manufacture_year    smallint NOT NULL CHECK (manufacture_year BETWEEN 1950 AND 2100),
  fuel_type           fuel_type NOT NULL,
  transmission        transmission_type,
  registration_number text,                                         -- normalised: MH12AB1234 / 22BH1234AA
  nickname            text,
  odometer_km         int CHECK (odometer_km IS NULL OR odometer_km >= 0),
  is_default          boolean NOT NULL DEFAULT false,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz,
  CONSTRAINT vehicles_reg_format CHECK (
    registration_number IS NULL
    OR registration_number ~ '^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{1,4}$'   -- state series
    OR registration_number ~ '^[0-9]{2}BH[0-9]{4}[A-Z]{1,2}$'              -- BH series
  )
);
CREATE INDEX vehicles_user_idx ON vehicles (user_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX vehicles_user_reg_uq ON vehicles (user_id, registration_number)
  WHERE registration_number IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX vehicles_one_default_uq ON vehicles (user_id) WHERE is_default AND deleted_at IS NULL;
CREATE TRIGGER vehicles_updated_at BEFORE UPDATE ON vehicles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE addresses (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label          text NOT NULL DEFAULT 'home',     -- home / work / other
  contact_name   text NOT NULL,
  contact_phone  text NOT NULL CHECK (contact_phone ~ '^\+[1-9][0-9]{7,14}$'),
  line1          text NOT NULL,
  line2          text,
  landmark       text,
  city           text NOT NULL,
  state          text NOT NULL,
  pincode        char(6) NOT NULL CHECK (pincode ~ '^[1-9][0-9]{5}$'),
  location       geography(Point, 4326),
  is_default     boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz
);
CREATE INDEX addresses_user_idx ON addresses (user_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX addresses_one_default_uq ON addresses (user_id) WHERE is_default AND deleted_at IS NULL;
CREATE TRIGGER addresses_updated_at BEFORE UPDATE ON addresses FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- migrate:down
DROP TABLE IF EXISTS addresses, vehicles, vehicle_variants, vehicle_models, vehicle_makes;
