-- migrate:up
CREATE TYPE review_status   AS ENUM ('published', 'pending', 'hidden', 'removed');
CREATE TYPE chat_message_type AS ENUM ('text', 'image', 'estimate', 'location', 'system');
CREATE TYPE notification_channel AS ENUM ('push', 'in_app', 'sms', 'whatsapp', 'email');

-- Verified-purchase reviews only: each review hangs off a delivered order or completed booking.
CREATE TABLE reviews (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id        uuid NOT NULL REFERENCES users(id),
  vendor_id        uuid NOT NULL REFERENCES vendors(id),
  order_id         uuid REFERENCES orders(id),
  product_id       uuid REFERENCES products(id),
  booking_id       uuid REFERENCES bookings(id),
  rating           smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title            text CHECK (title IS NULL OR length(title) <= 120),
  body             text CHECK (body IS NULL OR length(body) <= 2000),
  language         app_language,
  status           review_status NOT NULL DEFAULT 'published',
  moderation_note  text,
  moderated_by     uuid REFERENCES users(id),
  moderated_at     timestamptz,
  vendor_reply     text CHECK (vendor_reply IS NULL OR length(vendor_reply) <= 1000),
  vendor_replied_at timestamptz,
  report_count     int NOT NULL DEFAULT 0,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reviews_source CHECK (
    (order_id IS NOT NULL AND booking_id IS NULL) OR (booking_id IS NOT NULL AND order_id IS NULL)
  ),
  CONSTRAINT reviews_product_needs_order CHECK (product_id IS NULL OR order_id IS NOT NULL)
);
-- One review per product per order, one vendor review per order, one per booking
CREATE UNIQUE INDEX reviews_order_product_uq ON reviews (order_id, product_id) WHERE product_id IS NOT NULL;
CREATE UNIQUE INDEX reviews_order_vendor_uq  ON reviews (order_id) WHERE product_id IS NULL AND order_id IS NOT NULL;
CREATE UNIQUE INDEX reviews_booking_uq       ON reviews (booking_id) WHERE booking_id IS NOT NULL;
CREATE INDEX reviews_vendor_idx   ON reviews (vendor_id, created_at DESC) WHERE status = 'published';
CREATE INDEX reviews_product_idx  ON reviews (product_id, created_at DESC) WHERE status = 'published';
CREATE INDEX reviews_moderation_idx ON reviews (created_at) WHERE status = 'pending' OR report_count > 0;
CREATE TRIGGER reviews_updated_at BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE review_media (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id   uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  url         text NOT NULL,
  public_id   text NOT NULL,
  moderation  moderation_status NOT NULL DEFAULT 'pending',
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX review_media_review_idx ON review_media (review_id);
CREATE INDEX review_media_pending_idx ON review_media (created_at) WHERE moderation = 'pending';

-- Keep vendor/product rating aggregates in sync with published reviews.
CREATE OR REPLACE FUNCTION refresh_rating_aggregates() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_vendor  uuid := COALESCE(NEW.vendor_id, OLD.vendor_id);
  v_product uuid := COALESCE(NEW.product_id, OLD.product_id);
BEGIN
  UPDATE vendors v SET
    rating_avg   = COALESCE(s.avg, 0),
    rating_count = s.cnt
  FROM (SELECT round(avg(rating)::numeric, 2) AS avg, count(*)::int AS cnt
          FROM reviews WHERE vendor_id = v_vendor AND status = 'published' AND product_id IS NULL) s
  WHERE v.id = v_vendor;

  IF v_product IS NOT NULL THEN
    UPDATE products p SET
      rating_avg   = COALESCE(s.avg, 0),
      rating_count = s.cnt
    FROM (SELECT round(avg(rating)::numeric, 2) AS avg, count(*)::int AS cnt
            FROM reviews WHERE product_id = v_product AND status = 'published') s
    WHERE p.id = v_product;
  END IF;
  RETURN NULL;
END;
$$;
CREATE TRIGGER reviews_rating_aggregates
  AFTER INSERT OR DELETE OR UPDATE OF rating, status ON reviews
  FOR EACH ROW EXECUTE FUNCTION refresh_rating_aggregates();

-- One conversation per customer-vendor pair; messages can point at an order or booking for context.
CREATE TABLE chat_conversations (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id           uuid NOT NULL REFERENCES users(id),
  vendor_id             uuid NOT NULL REFERENCES vendors(id),
  last_message_at       timestamptz,
  last_message_preview  text,
  customer_last_read_id bigint NOT NULL DEFAULT 0,
  vendor_last_read_id   bigint NOT NULL DEFAULT 0,
  is_blocked            boolean NOT NULL DEFAULT false,
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (customer_id, vendor_id)
);
CREATE INDEX chat_conversations_customer_idx ON chat_conversations (customer_id, last_message_at DESC);
CREATE INDEX chat_conversations_vendor_idx   ON chat_conversations (vendor_id, last_message_at DESC);

-- bigint id doubles as a monotonic cursor for pagination and read receipts.
-- At ~1M users, convert to monthly range partitions on created_at.
CREATE TABLE chat_messages (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
  sender_id       uuid REFERENCES users(id),           -- NULL for system messages
  sender_role     actor_kind NOT NULL,
  type            chat_message_type NOT NULL DEFAULT 'text',
  body            text CHECK (body IS NULL OR length(body) <= 4000),
  attachment_url  text,
  order_id        uuid REFERENCES orders(id),
  booking_id      uuid REFERENCES bookings(id),
  metadata        jsonb,
  client_msg_id   text,                                 -- client-generated, dedupes retries on flaky networks
  created_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  CONSTRAINT chat_messages_content CHECK (body IS NOT NULL OR attachment_url IS NOT NULL OR type IN ('system', 'estimate', 'location'))
);
CREATE INDEX chat_messages_conversation_idx ON chat_messages (conversation_id, id DESC);
CREATE UNIQUE INDEX chat_messages_client_dedupe_uq ON chat_messages (conversation_id, sender_id, client_msg_id)
  WHERE client_msg_id IS NOT NULL;

CREATE TABLE notifications (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  app         client_app NOT NULL,
  type        text NOT NULL,                    -- order.dispatched, booking.estimate_shared, ...
  title       text NOT NULL,
  body        text NOT NULL,
  data        jsonb NOT NULL DEFAULT '{}',      -- deep link payload: {"route": "/orders/<id>"}
  channels    notification_channel[] NOT NULL DEFAULT '{push,in_app}',
  sent_at     timestamptz,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx   ON notifications (user_id, app, created_at DESC);
CREATE INDEX notifications_unread_idx ON notifications (user_id, app) WHERE read_at IS NULL;

-- migrate:down
DROP TABLE IF EXISTS notifications, chat_messages, chat_conversations;
DROP TRIGGER IF EXISTS reviews_rating_aggregates ON reviews;
DROP FUNCTION IF EXISTS refresh_rating_aggregates();
DROP TABLE IF EXISTS review_media, reviews;
DROP TYPE IF EXISTS notification_channel, chat_message_type, review_status;
