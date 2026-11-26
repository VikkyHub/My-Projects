-- migrate:up
CREATE TYPE payment_purpose AS ENUM ('order_checkout', 'booking_advance', 'booking_balance');
CREATE TYPE payment_status  AS ENUM ('created', 'authorized', 'captured', 'failed', 'refunded', 'partially_refunded');
CREATE TYPE refund_status   AS ENUM ('pending', 'processed', 'failed');
CREATE TYPE refund_destination AS ENUM ('source', 'wallet');
CREATE TYPE wallet_txn_type AS ENUM ('credit', 'debit');
CREATE TYPE wallet_txn_reason AS ENUM ('refund', 'cashback', 'referral', 'order_payment', 'booking_payment', 'admin_adjustment', 'expiry');
CREATE TYPE ledger_entry_type AS ENUM ('order_earning', 'booking_earning', 'refund_reversal', 'payout', 'payout_reversal', 'adjustment');
CREATE TYPE payout_status AS ENUM ('requested', 'approved', 'processing', 'paid', 'failed', 'rejected');

-- One row per Razorpay order. Status only becomes 'captured' after server-side signature
-- verification or a verified webhook — never because the app says so.
CREATE TABLE payments (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid NOT NULL REFERENCES users(id),
  purpose              payment_purpose NOT NULL,
  order_group_id       uuid REFERENCES order_groups(id),
  booking_id           uuid REFERENCES bookings(id),
  amount_paise         bigint NOT NULL CHECK (amount_paise >= 100),   -- Razorpay minimum ₹1
  currency             char(3) NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
  status               payment_status NOT NULL DEFAULT 'created',
  razorpay_order_id    text NOT NULL UNIQUE,
  razorpay_payment_id  text UNIQUE,
  method               text,                    -- upi / card / netbanking / wallet / emi
  method_detail        jsonb,                   -- vpa, card network+last4, bank — never full PAN
  refunded_paise       bigint NOT NULL DEFAULT 0 CHECK (refunded_paise >= 0),
  failure_code         text,
  failure_reason       text,
  captured_at          timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payments_one_target CHECK (
    (purpose = 'order_checkout' AND order_group_id IS NOT NULL AND booking_id IS NULL) OR
    (purpose IN ('booking_advance', 'booking_balance') AND booking_id IS NOT NULL AND order_group_id IS NULL)
  ),
  CONSTRAINT payments_refund_le_amount CHECK (refunded_paise <= amount_paise),
  CONSTRAINT payments_captured_meta CHECK (status NOT IN ('captured', 'refunded', 'partially_refunded')
                                           OR (razorpay_payment_id IS NOT NULL AND captured_at IS NOT NULL))
);
CREATE INDEX payments_user_idx    ON payments (user_id, created_at DESC);
CREATE INDEX payments_group_idx   ON payments (order_group_id) WHERE order_group_id IS NOT NULL;
CREATE INDEX payments_booking_idx ON payments (booking_id) WHERE booking_id IS NOT NULL;
CREATE INDEX payments_stale_idx   ON payments (created_at) WHERE status = 'created';   -- reconciliation job
CREATE TRIGGER payments_updated_at BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE refunds (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id         uuid REFERENCES payments(id),       -- NULL for COD refunds paid to wallet
  order_id           uuid REFERENCES orders(id),
  booking_id         uuid REFERENCES bookings(id),
  return_request_id  uuid REFERENCES return_requests(id),
  dispute_id         uuid,                                -- FK added in disputes migration
  amount_paise       bigint NOT NULL CHECK (amount_paise > 0),
  destination        refund_destination NOT NULL DEFAULT 'source',
  status             refund_status NOT NULL DEFAULT 'pending',
  razorpay_refund_id text UNIQUE,
  reason             text NOT NULL,
  initiated_by       uuid REFERENCES users(id),
  idempotency_key    text NOT NULL UNIQUE,
  processed_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT refunds_has_target CHECK (order_id IS NOT NULL OR booking_id IS NOT NULL),
  CONSTRAINT refunds_source_needs_payment CHECK (destination = 'wallet' OR payment_id IS NOT NULL)
);
CREATE INDEX refunds_payment_idx ON refunds (payment_id);
CREATE INDEX refunds_pending_idx ON refunds (created_at) WHERE status = 'pending';

-- Webhook inbox: dedupe by Razorpay event id, process asynchronously, keep raw payload for audits.
CREATE TABLE payment_webhook_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider      text NOT NULL DEFAULT 'razorpay',
  event_id      text NOT NULL,                  -- x-razorpay-event-id header
  event_type    text NOT NULL,                  -- payment.captured, refund.processed, ...
  payload       jsonb NOT NULL,
  received_at   timestamptz NOT NULL DEFAULT now(),
  processed_at  timestamptz,
  error         text,
  UNIQUE (provider, event_id)
);
CREATE INDEX payment_webhook_unprocessed_idx ON payment_webhook_events (received_at) WHERE processed_at IS NULL;

-- Closed-loop wallet (refunds/cashback, spendable only on-platform, not withdrawable)
-- so no RBI PPI licence is needed. No top-ups in MVP.
CREATE TABLE wallets (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL UNIQUE REFERENCES users(id),
  balance_paise  bigint NOT NULL DEFAULT 0 CHECK (balance_paise >= 0),
  is_frozen      boolean NOT NULL DEFAULT false,
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER wallets_updated_at BEFORE UPDATE ON wallets FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Append-only ledger. The service updates wallets.balance and inserts here in one transaction
-- (SELECT ... FOR UPDATE on the wallet row).
CREATE TABLE wallet_transactions (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  wallet_id           uuid NOT NULL REFERENCES wallets(id),
  type                wallet_txn_type NOT NULL,
  reason              wallet_txn_reason NOT NULL,
  amount_paise        bigint NOT NULL CHECK (amount_paise > 0),
  balance_after_paise bigint NOT NULL CHECK (balance_after_paise >= 0),
  ref_type            text,
  ref_id              uuid,
  description         text,
  idempotency_key     text NOT NULL UNIQUE,
  expires_at          timestamptz,              -- cashback expiry
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX wallet_transactions_wallet_idx ON wallet_transactions (wallet_id, created_at DESC);

CREATE TABLE payouts (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendor_id             uuid NOT NULL REFERENCES vendors(id),
  bank_account_id       uuid NOT NULL REFERENCES vendor_bank_accounts(id),
  amount_paise          bigint NOT NULL CHECK (amount_paise >= 10000),   -- min ₹100
  status                payout_status NOT NULL DEFAULT 'requested',
  razorpay_transfer_id  text UNIQUE,            -- Route transfer / RazorpayX payout id
  utr                   text,                   -- bank reference shown to vendor
  requested_by          uuid NOT NULL REFERENCES users(id),
  reviewed_by           uuid REFERENCES users(id),
  admin_note            text,
  failure_reason        text,
  requested_at          timestamptz NOT NULL DEFAULT now(),
  processed_at          timestamptz,
  updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX payouts_vendor_idx ON payouts (vendor_id, requested_at DESC);
CREATE INDEX payouts_queue_idx  ON payouts (status, requested_at) WHERE status IN ('requested', 'approved', 'processing');
-- One payout in flight per vendor prevents double-withdrawal races
CREATE UNIQUE INDEX payouts_one_inflight_uq ON payouts (vendor_id) WHERE status IN ('requested', 'approved', 'processing');
CREATE TRIGGER payouts_updated_at BEFORE UPDATE ON payouts FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Vendor earnings ledger (signed amounts). Balance = SUM(amount) where available_at <= now().
-- Earnings become available after the return window closes.
CREATE TABLE vendor_ledger_entries (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vendor_id     uuid NOT NULL REFERENCES vendors(id),
  type          ledger_entry_type NOT NULL,
  amount_paise  bigint NOT NULL CHECK (amount_paise <> 0),
  order_id      uuid REFERENCES orders(id),
  booking_id    uuid REFERENCES bookings(id),
  refund_id     uuid REFERENCES refunds(id),
  payout_id     uuid REFERENCES payouts(id),
  description   text,
  available_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ledger_sign CHECK (
    (type IN ('order_earning', 'booking_earning', 'payout_reversal') AND amount_paise > 0) OR
    (type IN ('refund_reversal', 'payout') AND amount_paise < 0) OR
    type = 'adjustment'
  )
);
CREATE INDEX vendor_ledger_vendor_idx ON vendor_ledger_entries (vendor_id, available_at);
-- An order / booking is credited to the vendor exactly once
CREATE UNIQUE INDEX vendor_ledger_order_earning_uq   ON vendor_ledger_entries (order_id)   WHERE type = 'order_earning';
CREATE UNIQUE INDEX vendor_ledger_booking_earning_uq ON vendor_ledger_entries (booking_id) WHERE type = 'booking_earning';

-- migrate:down
DROP TABLE IF EXISTS vendor_ledger_entries, payouts, wallet_transactions, wallets,
  payment_webhook_events, refunds, payments;
DROP TYPE IF EXISTS payout_status, ledger_entry_type, wallet_txn_reason, wallet_txn_type,
  refund_destination, refund_status, payment_status, payment_purpose;
