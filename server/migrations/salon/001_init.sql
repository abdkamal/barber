-- Salon database schema (design.md §2). One database per salon.
-- Conventions: timestamps are timestamptz (UTC); money is bigint minor units in the salon currency
-- (currency lives in the directory); time-of-day values (recurring schedules) are salon-local `time`.

-- Identity of this database, checked by the server when it opens a pool (defence in depth
-- against a wrong directory → database mapping).
CREATE TABLE salon_meta (
  id          smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  salon_id    uuid NOT NULL,
  salon_code  text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ─── Settings (design §11) — single row ─────────────────────────────────────────────
CREATE TABLE settings (
  id                                   smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  require_account_approval             boolean NOT NULL DEFAULT false,
  max_active_bookings_per_customer     integer NOT NULL DEFAULT 1   CHECK (max_active_bookings_per_customer BETWEEN 1 AND 10),
  booking_opens_before_minutes         integer NOT NULL DEFAULT 60  CHECK (booking_opens_before_minutes BETWEEN 0 AND 1440),
  eta_change_notify_minutes            integer NOT NULL DEFAULT 30  CHECK (eta_change_notify_minutes BETWEEN 1 AND 240),
  max_disconnect_window_minutes        integer NOT NULL DEFAULT 120 CHECK (max_disconnect_window_minutes BETWEEN 0 AND 1440),
  gap_margin_min_minutes               integer NOT NULL DEFAULT 10  CHECK (gap_margin_min_minutes BETWEEN 0 AND 240),
  gap_margin_percent                   integer NOT NULL DEFAULT 25  CHECK (gap_margin_percent BETWEEN 0 AND 400),
  offer_hold_minutes                   integer NOT NULL DEFAULT 2   CHECK (offer_hold_minutes BETWEEN 1 AND 60),
  barber_not_connected_alert_minutes   integer NOT NULL DEFAULT 0   CHECK (barber_not_connected_alert_minutes BETWEEN 0 AND 240),
  overrun_alert_percent                integer NOT NULL DEFAULT 100 CHECK (overrun_alert_percent BETWEEN 50 AND 500),
  updated_at                           timestamptz NOT NULL DEFAULT now()
);
INSERT INTO settings DEFAULT VALUES;

-- ─── Salon profile (ق37) ─────────────────────────────────────────────────────────────
CREATE TABLE salon_profile (
  id            smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  name          text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 80),
  about         text CHECK (about IS NULL OR length(about) <= 2000),
  logo_path     text,
  address       text CHECK (address IS NULL OR length(address) <= 300),
  latitude      numeric(9,6) CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  longitude     numeric(9,6) CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  phone         text,
  whatsapp      text,
  social_links  jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(social_links) = 'array'),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CHECK ((latitude IS NULL) = (longitude IS NULL))
);

CREATE TABLE salon_photos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path        text NOT NULL,
  position    smallint NOT NULL CHECK (position BETWEEN 1 AND 6),   -- at most 6 photos
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT salon_photos_position_key UNIQUE (position)
);

-- ─── Staff ───────────────────────────────────────────────────────────────────────────
CREATE TABLE staff (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                   text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  username               text NOT NULL CHECK (username ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
  password_hash          text NOT NULL,
  role                   text NOT NULL CHECK (role IN ('barber', 'manager')),
  active                 boolean NOT NULL DEFAULT true,
  call_ahead_minutes     integer NOT NULL DEFAULT 20 CHECK (call_ahead_minutes BETWEEN 0 AND 240),
  -- Account-wide failed-login counter (for monitoring / manager alerts). Backoff itself is keyed by
  -- account+IP in login_throttle so an attacker cannot slow down a barber's own device (ق31).
  failed_login_count     integer NOT NULL DEFAULT 0,
  last_failed_login_at   timestamptz,
  last_login_at          timestamptz,
  -- Bumped to invalidate every access/refresh token of this account (reset, deactivation…).
  token_version          integer NOT NULL DEFAULT 0,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT staff_username_key UNIQUE (username)
);

-- ─── Services & catalog ─────────────────────────────────────────────────────────────
CREATE TABLE services (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                    text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  base_duration_minutes   integer NOT NULL CHECK (base_duration_minutes BETWEEN 1 AND 600),
  price_minor             bigint NOT NULL CHECK (price_minor >= 0),
  active                  boolean NOT NULL DEFAULT true,
  position                integer NOT NULL DEFAULT 0,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE catalog_items (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind         text NOT NULL CHECK (kind IN ('service', 'product')),
  name         text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  description  text CHECK (description IS NULL OR length(description) <= 2000),
  features     jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(features) = 'array'),
  price_minor  bigint CHECK (price_minor IS NULL OR price_minor >= 0),
  photo_path   text,
  position     integer NOT NULL DEFAULT 0,
  visible      boolean NOT NULL DEFAULT true,
  -- Bookable services are linked to `services`; products are display-only (ق37).
  service_id   uuid REFERENCES services(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (kind = 'service' OR service_id IS NULL)
);
CREATE INDEX catalog_items_order_idx ON catalog_items (kind, position);

-- ─── Working time ───────────────────────────────────────────────────────────────────
-- Weekly schedule; closes_at <= opens_at means the shift crosses midnight (ق30).
CREATE TABLE work_schedules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id    uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  weekday     smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),  -- 0 = Sunday
  opens_at    time NOT NULL,
  closes_at   time NOT NULL,
  CHECK (opens_at <> closes_at),
  CONSTRAINT work_schedules_staff_weekday_key UNIQUE (staff_id, weekday)
);

-- Per-barber per-work-day state (design §4).
CREATE TABLE barber_days (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id                    uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  work_date                   date NOT NULL,
  state                       text NOT NULL DEFAULT 'not_connected_yet'
                                CHECK (state IN ('not_connected_yet', 'connected', 'disconnected', 'absent')),
  first_connected_at          timestamptz,
  last_heartbeat_at           timestamptz,
  known_work_minutes_at_last_heartbeat integer CHECK (known_work_minutes_at_last_heartbeat IS NULL OR known_work_minutes_at_last_heartbeat >= 0),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT barber_days_staff_date_key UNIQUE (staff_id, work_date)
);

CREATE TABLE absences (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id             uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  work_date            date NOT NULL,
  reason               text CHECK (reason IS NULL OR length(reason) <= 300),
  recorded_by_staff_id uuid REFERENCES staff(id),
  created_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT absences_staff_date_key UNIQUE (staff_id, work_date)
);

-- Breaks: either recurring daily (work_date NULL, salon-local start_time/end_time) or dated
-- (work_date set, exact starts_at/ends_at — prayer times, emergencies). 'walk_in_only' = ق33.
CREATE TABLE breaks (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id    uuid NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
  work_date   date,
  type        text NOT NULL CHECK (type IN ('rest', 'prayer', 'emergency', 'walk_in_only')),
  start_time  time,
  end_time    time,
  starts_at   timestamptz,
  ends_at     timestamptz,
  created_by_staff_id uuid REFERENCES staff(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (work_date IS NULL AND start_time IS NOT NULL AND end_time IS NOT NULL AND start_time <> end_time
       AND starts_at IS NULL AND ends_at IS NULL)
    OR
    (work_date IS NOT NULL AND starts_at IS NOT NULL AND ends_at IS NOT NULL AND ends_at > starts_at
       AND start_time IS NULL AND end_time IS NULL)
  )
);
CREATE INDEX breaks_staff_date_idx ON breaks (staff_id, work_date);

-- ─── Customers ──────────────────────────────────────────────────────────────────────
-- password_hash NULL = walk-in record created by a barber (name + phone only, ق6).
-- App accounts have a unique phone; walk-in records may share a phone until linked (ق14، ق20).
CREATE TABLE customers (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                   text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
  phone                  text NOT NULL CHECK (phone ~ '^\+?[0-9]{7,15}$'),
  password_hash          text,
  status                 text NOT NULL DEFAULT 'active' CHECK (status IN ('pending', 'active', 'suspended')),
  no_show_count          integer NOT NULL DEFAULT 0 CHECK (no_show_count >= 0),
  linked_walk_in_id      uuid REFERENCES customers(id),
  created_by_staff_id    uuid REFERENCES staff(id),
  failed_login_count     integer NOT NULL DEFAULT 0,
  last_failed_login_at   timestamptz,
  last_login_at          timestamptz,
  token_version          integer NOT NULL DEFAULT 0,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CHECK (linked_walk_in_id IS NULL OR linked_walk_in_id <> id)
);
CREATE UNIQUE INDEX customers_account_phone_key ON customers (phone) WHERE password_hash IS NOT NULL;
CREATE INDEX customers_phone_idx ON customers (phone);
CREATE INDEX customers_status_idx ON customers (status) WHERE password_hash IS NOT NULL;

-- ─── Bookings (design §3) ───────────────────────────────────────────────────────────
CREATE TABLE bookings (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id                 uuid NOT NULL REFERENCES customers(id),
  staff_id                    uuid NOT NULL REFERENCES staff(id),
  kind                        text NOT NULL CHECK (kind IN ('queue', 'requested')),
  requested_at                timestamptz,
  status                      text NOT NULL
                                CHECK (status IN ('offered', 'waiting', 'called', 'in_service', 'done', 'cancelled', 'no_show', 'expired')),
  queue_position              integer,
  original_expected_start     timestamptz,     -- never rewritten (ق5)
  last_shown_expected_start   timestamptz,     -- reference for the mandatory >30 min notice (ق5، §5.9)
  postpone_used               boolean NOT NULL DEFAULT false,
  actual_start                timestamptz,
  actual_end                  timestamptz,
  source                      text NOT NULL CHECK (source IN ('app', 'barber')),
  work_date                   date NOT NULL,
  idempotency_key             uuid,
  offer_expires_at            timestamptz,
  cancel_reason               text,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'requested') = (requested_at IS NOT NULL)),
  CHECK (status <> 'offered' OR offer_expires_at IS NOT NULL),
  CHECK (actual_end IS NULL OR (actual_start IS NOT NULL AND actual_end >= actual_start))
);
CREATE UNIQUE INDEX bookings_idempotency_key ON bookings (customer_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX bookings_queue_idx ON bookings (staff_id, work_date, status, queue_position);
CREATE INDEX bookings_customer_idx ON bookings (customer_id, created_at DESC);
CREATE INDEX bookings_offer_expiry_idx ON bookings (offer_expires_at) WHERE status = 'offered';

-- Services actually performed, with the price at execution time.
CREATE TABLE booking_services (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id                uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  service_id                uuid NOT NULL REFERENCES services(id),
  name_snapshot             text NOT NULL,
  price_minor               bigint NOT NULL CHECK (price_minor >= 0),
  duration_minutes_snapshot integer NOT NULL CHECK (duration_minutes_snapshot > 0),
  position                  smallint NOT NULL DEFAULT 0,
  created_at                timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX booking_services_booking_idx ON booking_services (booking_id);

-- Immutable audit trail of every booking change (append-only, enforced by trigger below).
CREATE TABLE booking_events (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),   -- client event id when from a device
  booking_id         uuid REFERENCES bookings(id),
  type               text NOT NULL,
  payload            jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at        timestamptz NOT NULL,
  received_at        timestamptz NOT NULL DEFAULT now(),
  actor_kind         text NOT NULL CHECK (actor_kind IN ('staff', 'customer', 'system')),
  actor_id           uuid,
  device_id          uuid,
  device_seq         bigint,
  approximate_time   boolean NOT NULL DEFAULT false,
  reason             text,
  CHECK ((device_id IS NULL) = (device_seq IS NULL))
);
CREATE UNIQUE INDEX booking_events_device_seq_key ON booking_events (device_id, device_seq) WHERE device_id IS NOT NULL;
CREATE INDEX booking_events_booking_idx ON booking_events (booking_id, occurred_at);

CREATE FUNCTION reject_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only: % is not allowed', TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

CREATE TRIGGER booking_events_append_only
  BEFORE UPDATE OR DELETE ON booking_events
  FOR EACH ROW EXECUTE FUNCTION reject_mutation();
CREATE TRIGGER booking_events_no_truncate
  BEFORE TRUNCATE ON booking_events
  FOR EACH STATEMENT EXECUTE FUNCTION reject_mutation();

-- ─── Change feed for staff sync (design §6.3) ───────────────────────────────────────
-- seq is allocated from a single counter row inside the writing transaction, so sequence numbers
-- are strictly increasing in COMMIT order (a reader of "since=N" can never miss a later-committed
-- lower number, which a plain sequence would allow).
CREATE TABLE change_counter (
  id     smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  value  bigint NOT NULL DEFAULT 0
);
INSERT INTO change_counter DEFAULT VALUES;

CREATE TABLE changes (
  seq         bigint PRIMARY KEY,
  entity      text NOT NULL,
  entity_id   uuid,
  op          text NOT NULL CHECK (op IN ('insert', 'update', 'delete')),
  staff_id    uuid,              -- barber the change concerns (NULL = everyone / managers)
  data        jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX changes_staff_seq_idx ON changes (staff_id, seq);

CREATE FUNCTION assign_change_seq() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE change_counter SET value = value + 1 WHERE id = 1 RETURNING value INTO NEW.seq;
  RETURN NEW;
END;
$$;
CREATE TRIGGER changes_assign_seq BEFORE INSERT ON changes
  FOR EACH ROW EXECUTE FUNCTION assign_change_seq();
CREATE TRIGGER changes_append_only BEFORE UPDATE ON changes
  FOR EACH ROW EXECUTE FUNCTION reject_mutation();

-- ─── Payments (independent of service state) ────────────────────────────────────────
CREATE TABLE payments (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id             uuid NOT NULL REFERENCES bookings(id),
  amount_minor           bigint NOT NULL CHECK (amount_minor >= 0),
  status                 text NOT NULL DEFAULT 'awaiting_confirmation'
                           CHECK (status IN ('awaiting_confirmation', 'confirmed')),
  confirmed_by_staff_id  uuid REFERENCES staff(id),
  confirmed_at           timestamptz,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payments_booking_key UNIQUE (booking_id),
  CHECK (status <> 'confirmed' OR (confirmed_by_staff_id IS NOT NULL AND confirmed_at IS NOT NULL))
);
CREATE INDEX payments_status_idx ON payments (status);

-- ─── Duration learning samples (§5.10) ──────────────────────────────────────────────
CREATE TABLE duration_samples (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id          uuid NOT NULL REFERENCES staff(id),
  service_set_key   text NOT NULL,
  customer_id       uuid REFERENCES customers(id),
  booking_id        uuid REFERENCES bookings(id),
  duration_seconds  integer NOT NULL CHECK (duration_seconds >= 0),
  excluded          boolean NOT NULL DEFAULT false,
  exclusion_reason  text,
  recorded_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (excluded = (exclusion_reason IS NOT NULL))
);
CREATE INDEX duration_samples_lookup_idx ON duration_samples (staff_id, service_set_key, recorded_at DESC);
CREATE INDEX duration_samples_customer_idx ON duration_samples (staff_id, customer_id, recorded_at DESC);

-- ─── Devices, sessions & credentials ────────────────────────────────────────────────
CREATE TABLE devices (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_kind              text NOT NULL CHECK (owner_kind IN ('staff', 'customer')),
  owner_id                uuid NOT NULL,
  fcm_token               text,
  notifications_allowed   boolean NOT NULL DEFAULT false,
  has_play_services       boolean,
  last_seen_at            timestamptz,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX devices_fcm_token_key ON devices (fcm_token) WHERE fcm_token IS NOT NULL;
CREATE INDEX devices_owner_idx ON devices (owner_kind, owner_id);

-- A session = one refresh-token family (one login on one device).
CREATE TABLE sessions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_kind       text NOT NULL CHECK (subject_kind IN ('staff', 'customer')),
  subject_id         uuid NOT NULL,
  device_id          uuid REFERENCES devices(id) ON DELETE SET NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  last_refreshed_at  timestamptz,
  revoked_at         timestamptz,
  revoked_reason     text
);
CREATE INDEX sessions_subject_idx ON sessions (subject_kind, subject_id) WHERE revoked_at IS NULL;

CREATE TABLE refresh_tokens (
  id            uuid PRIMARY KEY,              -- = jti claim of the signed refresh token
  session_id    uuid NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  token_hash    text NOT NULL,                 -- sha256 of the full token; the token itself is never stored
  issued_at     timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  used_at       timestamptz,                   -- set when rotated; presenting it again = reuse
  replaced_by   uuid,
  revoked_at    timestamptz,
  CONSTRAINT refresh_tokens_hash_key UNIQUE (token_hash)
);
CREATE INDEX refresh_tokens_session_idx ON refresh_tokens (session_id);

CREATE TABLE reset_codes (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_kind          text NOT NULL CHECK (subject_kind IN ('staff', 'customer')),
  subject_id            uuid NOT NULL,
  code_hash             text NOT NULL,          -- HMAC-SHA256(pepper, code)
  expires_at            timestamptz NOT NULL,
  used_at               timestamptz,
  invalidated_at        timestamptz,
  failed_attempts       integer NOT NULL DEFAULT 0,
  issued_by_kind        text NOT NULL CHECK (issued_by_kind IN ('staff', 'vendor')),
  issued_by_staff_id    uuid REFERENCES staff(id),
  created_at            timestamptz NOT NULL DEFAULT now(),
  CHECK (issued_by_kind = 'vendor' OR issued_by_staff_id IS NOT NULL)
);
CREATE INDEX reset_codes_subject_idx ON reset_codes (subject_kind, subject_id)
  WHERE used_at IS NULL AND invalidated_at IS NULL;

-- Progressive login backoff, keyed by account identifier + client IP (identifier '*' = whole IP).
CREATE TABLE login_throttle (
  scope            text NOT NULL,         -- e.g. 'staff_login', 'customer_login', 'password_reset'
  identifier       text NOT NULL,
  ip               text NOT NULL,
  failures         integer NOT NULL DEFAULT 0,
  next_allowed_at  timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scope, identifier, ip)
);

-- ─── Audit (design §7) — append-only ────────────────────────────────────────────────
CREATE TABLE audit_log (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at  timestamptz NOT NULL DEFAULT now(),
  actor_kind   text NOT NULL CHECK (actor_kind IN ('staff', 'customer', 'vendor', 'system', 'anonymous')),
  actor_id     uuid,
  action       text NOT NULL,
  target_kind  text,
  target_id    uuid,
  ip           text,
  details      jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX audit_log_time_idx ON audit_log (occurred_at DESC);
CREATE INDEX audit_log_action_idx ON audit_log (action, occurred_at DESC);

CREATE TRIGGER audit_log_append_only
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION reject_mutation();
CREATE TRIGGER audit_log_no_truncate
  BEFORE TRUNCATE ON audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION reject_mutation();
