-- migrate:up
-- Core extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid(), digest()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive email
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- fuzzy search on part names / numbers
CREATE EXTENSION IF NOT EXISTS postgis;    -- geo queries (nearby vendors)

-- Keep updated_at fresh on every UPDATE
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Shared enums
CREATE TYPE app_language     AS ENUM ('en', 'hi', 'mr');
CREATE TYPE fuel_type        AS ENUM ('petrol', 'diesel', 'cng', 'lpg', 'electric', 'hybrid');
CREATE TYPE transmission_type AS ENUM ('manual', 'automatic', 'amt', 'cvt', 'dct');
CREATE TYPE business_domain  AS ENUM ('parts', 'service', 'decor');

-- Human-readable reference numbers, e.g. ORD-261125-000042
CREATE SEQUENCE order_number_seq;
CREATE SEQUENCE booking_number_seq;
CREATE SEQUENCE dispute_number_seq;
CREATE SEQUENCE invoice_number_seq;

CREATE OR REPLACE FUNCTION make_ref(prefix text, seq regclass) RETURNS text
LANGUAGE sql VOLATILE AS $$
  SELECT prefix || '-' || to_char(now() AT TIME ZONE 'Asia/Kolkata', 'YYMMDD') || '-' ||
         lpad(nextval(seq)::text, 6, '0');
$$;

-- migrate:down
DROP FUNCTION IF EXISTS make_ref(text, regclass);
DROP SEQUENCE IF EXISTS invoice_number_seq, dispute_number_seq, booking_number_seq, order_number_seq;
DROP TYPE IF EXISTS business_domain, transmission_type, fuel_type, app_language;
DROP FUNCTION IF EXISTS set_updated_at();
-- extensions intentionally left installed
