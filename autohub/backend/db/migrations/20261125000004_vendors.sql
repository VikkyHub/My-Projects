-- migrate:up
CREATE TYPE vendor_status AS ENUM ('draft', 'pending_review', 'approved', 'rejected', 'suspended');
CREATE TYPE vendor_member_role AS ENUM ('owner', 'manager', 'staff');
CREATE TYPE vendor_document_type AS ENUM (
  'gst_certificate', 'pan_card', 'shop_establishment_license', 'trade_license',
  'udyam_certificate', 'cancelled_cheque', 'owner_id_proof', 'shop_photo', 'other'
);
CREATE TYPE document_status AS ENUM ('pending', 'verified', 'rejected');

CREATE TABLE vendors (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id         uuid NOT NULL REFERENCES users(id),
  business_name         text NOT NULL,
  slug                  text NOT NULL UNIQUE,
  description           text,
  -- One vendor can be several things (e.g. a service centre that also sells parts).
  business_domains      business_domain[] NOT NULL,
  status                vendor_status NOT NULL DEFAULT 'draft',
  status_reason         text,                          -- rejection / suspension reason shown to vendor
  reviewed_by           uuid REFERENCES users(id),
  reviewed_at           timestamptz,
  submitted_at          timestamptz,

  legal_name            text,
  gstin                 char(15),
  pan                   char(10),
  phone                 text NOT NULL CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),
  whatsapp_phone        text CHECK (whatsapp_phone IS NULL OR whatsapp_phone ~ '^\+[1-9][0-9]{7,14}$'),
  email                 citext,

  address_line1         text NOT NULL,
  address_line2         text,
  city                  text NOT NULL,
  state                 text NOT NULL,
  pincode               char(6) NOT NULL CHECK (pincode ~ '^[1-9][0-9]{5}$'),
  location              geography(Point, 4326) NOT NULL,
  delivery_radius_km    numeric(5,1) CHECK (delivery_radius_km IS NULL OR delivery_radius_km > 0),
  offers_doorstep       boolean NOT NULL DEFAULT false,
  cod_enabled           boolean NOT NULL DEFAULT false,

  logo_url              text,
  cover_url             text,
  opening_hours         jsonb,                         -- display only; bookable slots come from vendor_working_hours
  is_accepting_orders   boolean NOT NULL DEFAULT true,
  commission_bps_override int CHECK (commission_bps_override IS NULL OR commission_bps_override BETWEEN 0 AND 5000),

  razorpay_linked_account_id text UNIQUE,              -- Razorpay Route account for split settlements

  rating_avg            numeric(3,2) NOT NULL DEFAULT 0 CHECK (rating_avg BETWEEN 0 AND 5),
  rating_count          int NOT NULL DEFAULT 0 CHECK (rating_count >= 0),

  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz,

  CONSTRAINT vendors_domains_nonempty CHECK (cardinality(business_domains) >= 1),
  CONSTRAINT vendors_gstin_format CHECK (gstin IS NULL OR gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
  CONSTRAINT vendors_pan_format   CHECK (pan IS NULL OR pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'),
  -- Selling parts requires GST registration; approval requires review metadata.
  CONSTRAINT vendors_parts_need_gstin CHECK (status <> 'approved' OR NOT ('parts' = ANY(business_domains)) OR gstin IS NOT NULL),
  CONSTRAINT vendors_review_meta CHECK (status NOT IN ('approved', 'rejected') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);
CREATE INDEX vendors_location_gix   ON vendors USING gist (location) WHERE status = 'approved' AND deleted_at IS NULL;
CREATE INDEX vendors_domains_gin    ON vendors USING gin (business_domains);
CREATE INDEX vendors_status_idx     ON vendors (status, submitted_at);
CREATE INDEX vendors_owner_idx      ON vendors (owner_user_id);
CREATE INDEX vendors_city_idx       ON vendors (city) WHERE status = 'approved';
CREATE INDEX vendors_name_trgm      ON vendors USING gin (business_name gin_trgm_ops);
CREATE UNIQUE INDEX vendors_gstin_uq ON vendors (gstin) WHERE gstin IS NOT NULL AND deleted_at IS NULL;
CREATE TRIGGER vendors_updated_at BEFORE UPDATE ON vendors FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Who can act for a vendor in the Vendor app
CREATE TABLE vendor_members (
  vendor_id  uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role       vendor_member_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (vendor_id, user_id)
);
CREATE INDEX vendor_members_user_idx ON vendor_members (user_id);
CREATE UNIQUE INDEX vendor_members_one_owner_uq ON vendor_members (vendor_id) WHERE role = 'owner';

CREATE TABLE vendor_documents (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id    uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  doc_type     vendor_document_type NOT NULL,
  doc_number   text,
  storage_key  text NOT NULL,           -- private bucket key; served via short-lived signed URL only
  mime_type    text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  size_bytes   int NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 10485760),
  status       document_status NOT NULL DEFAULT 'pending',
  review_note  text,
  reviewed_by  uuid REFERENCES users(id),
  reviewed_at  timestamptz,
  expires_on   date,
  uploaded_by  uuid NOT NULL REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vendor_documents_review_meta CHECK (status = 'pending' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);
CREATE INDEX vendor_documents_vendor_idx  ON vendor_documents (vendor_id, doc_type);
CREATE INDEX vendor_documents_pending_idx ON vendor_documents (created_at) WHERE status = 'pending';

-- Bank details live with Razorpay; we keep only references and masked values.
CREATE TABLE vendor_bank_accounts (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id                   uuid NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
  account_holder_name         text NOT NULL,
  account_number_last4        char(4) NOT NULL,
  ifsc                        char(11) NOT NULL CHECK (ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  bank_name                   text,
  razorpay_fund_account_id    text UNIQUE,
  is_primary                  boolean NOT NULL DEFAULT false,
  verified_at                 timestamptz,              -- penny-drop verification
  created_at                  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX vendor_bank_one_primary_uq ON vendor_bank_accounts (vendor_id) WHERE is_primary;

-- migrate:down
DROP TABLE IF EXISTS vendor_bank_accounts, vendor_documents, vendor_members, vendors;
DROP TYPE IF EXISTS document_status, vendor_document_type, vendor_member_role, vendor_status;
