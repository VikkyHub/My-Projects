-- migrate:up
CREATE TYPE user_status AS ENUM ('active', 'suspended', 'deleted');
-- Platform staff roles. NULL = normal user (customer). Vendor access is via vendor_members.
CREATE TYPE admin_role  AS ENUM ('super_admin', 'operations', 'finance', 'support', 'moderator');
CREATE TYPE client_app  AS ENUM ('customer', 'vendor', 'admin');
CREATE TYPE device_platform AS ENUM ('android', 'ios', 'web');
CREATE TYPE otp_purpose AS ENUM ('login', 'change_phone', 'delete_account');

CREATE TABLE users (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone              text NOT NULL,                       -- E.164, e.g. +919876543210
  phone_verified_at  timestamptz,
  email              citext,
  full_name          text,
  avatar_url         text,
  preferred_language app_language NOT NULL DEFAULT 'en',
  admin_role         admin_role,
  status             user_status NOT NULL DEFAULT 'active',
  last_login_at      timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz,                         -- in-app account deletion (Apple 5.1.1(v), DPDP Act)
  CONSTRAINT users_phone_e164 CHECK (phone ~ '^\+[1-9][0-9]{7,14}$'),
  CONSTRAINT users_email_format CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  CONSTRAINT users_deleted_consistency CHECK ((status = 'deleted') = (deleted_at IS NOT NULL))
);
-- Phone is unique among live accounts; a deleted account's number can sign up again.
CREATE UNIQUE INDEX users_phone_live_uq ON users (phone) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_email_live_uq ON users (email) WHERE email IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX users_admin_role_idx ON users (admin_role) WHERE admin_role IS NOT NULL;
CREATE TRIGGER users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- OTP challenges. Only a hash of the code is stored. Rate limits are enforced in Redis;
-- this table is the durable audit trail and the source of truth for verification.
CREATE TABLE otp_requests (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone        text NOT NULL,
  purpose      otp_purpose NOT NULL DEFAULT 'login',
  code_hash    text NOT NULL,                 -- HMAC-SHA256(code, server secret)
  attempts     smallint NOT NULL DEFAULT 0,
  max_attempts smallint NOT NULL DEFAULT 5,
  expires_at   timestamptz NOT NULL,
  consumed_at  timestamptz,
  request_ip   inet,
  device_id    text,
  provider_ref text,                          -- MSG91 request id
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT otp_attempts_range CHECK (attempts >= 0 AND attempts <= max_attempts)
);
CREATE INDEX otp_requests_phone_created_idx ON otp_requests (phone, created_at DESC);
CREATE INDEX otp_requests_ip_created_idx    ON otp_requests (request_ip, created_at DESC);

-- Refresh-token sessions (access tokens are short-lived JWTs and are not stored).
CREATE TABLE user_sessions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  app                client_app NOT NULL,
  refresh_token_hash text NOT NULL UNIQUE,    -- SHA-256 of the opaque refresh token
  device_id          text,
  platform           device_platform,
  app_version        text,
  ip                 inet,
  user_agent         text,
  expires_at         timestamptz NOT NULL,
  revoked_at         timestamptz,
  replaced_by        uuid REFERENCES user_sessions(id),   -- rotation chain; reuse of a rotated token = theft
  created_at         timestamptz NOT NULL DEFAULT now(),
  last_used_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX user_sessions_user_active_idx ON user_sessions (user_id) WHERE revoked_at IS NULL;

-- FCM tokens (FCM relays to APNs on iOS)
CREATE TABLE device_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  app          client_app NOT NULL,
  platform     device_platform NOT NULL,
  fcm_token    text NOT NULL UNIQUE,
  locale       app_language NOT NULL DEFAULT 'en',
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX device_tokens_user_idx ON device_tokens (user_id, app);

-- migrate:down
DROP TABLE IF EXISTS device_tokens, user_sessions, otp_requests, users;
DROP TYPE IF EXISTS otp_purpose, device_platform, client_app, admin_role, user_status;
