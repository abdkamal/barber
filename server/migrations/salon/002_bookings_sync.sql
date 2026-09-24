-- Milestone 4b: bookings/queues, device sync, scheduler, notifications (design §3–§8).
-- Backward compatible with 001 (only additions).

-- ─── Bookings: engine state that must survive restarts ──────────────────────────────
ALTER TABLE bookings
  ADD COLUMN estimated_duration_seconds integer CHECK (estimated_duration_seconds IS NULL OR estimated_duration_seconds > 0),
  ADD COLUMN service_set_key            text,
  -- Latest projection (engine timeline) — for the customer screen, the ق5 check and reports.
  ADD COLUMN projected_start            timestamptz,
  ADD COLUMN projected_end              timestamptz,
  ADD COLUMN last_change_reason         text,
  ADD COLUMN last_change_at             timestamptz,
  ADD COLUMN called_at                  timestamptz,
  ADD COLUMN cancelled_at               timestamptz,
  ADD COLUMN overrun_alerted_at         timestamptz,       -- ق27: once per booking
  ADD COLUMN serve_late                 boolean NOT NULL DEFAULT false,   -- ق24 decision taken
  -- A change-time offer (§5.12) holds a place for an existing booking; accepting moves that booking.
  ADD COLUMN replaces_booking_id        uuid REFERENCES bookings(id),
  -- Sync conflict (design §3: offline start after cancellation…) — shown to the manager.
  ADD COLUMN needs_review               boolean NOT NULL DEFAULT false;

CREATE INDEX bookings_active_customer_idx ON bookings (customer_id)
  WHERE status IN ('offered', 'waiting', 'called', 'in_service');
CREATE INDEX bookings_day_idx ON bookings (work_date, staff_id);

-- ─── Change feed: explicit change type for the SyncChange contract ─────────────────
ALTER TABLE changes ADD COLUMN type text;

-- ─── Barber day (design §4) ──────────────────────────────────────────────────────────
ALTER TABLE barber_days
  ADD COLUMN known_work_end_at          timestamptz,   -- projected end of known work at the last heartbeat (ق3)
  ADD COLUMN offline_since              timestamptz,
  ADD COLUMN not_connected_alerted_at   timestamptz,   -- ق32: manager alerted once
  ADD COLUMN last_device_seq            bigint;

-- Breaks started from the barber device (emergency/rest/prayer) stay open until break_ended.
ALTER TABLE breaks ADD COLUMN open boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX breaks_one_open_per_staff ON breaks (staff_id) WHERE open;

-- ─── Device events (design §6.2): each event applied once, result kept for retries ──
CREATE TABLE device_events (
  id            uuid PRIMARY KEY,                       -- client event id
  staff_id      uuid NOT NULL REFERENCES staff(id),
  device_id     uuid NOT NULL,                          -- the staff session (one login = one device, ق28)
  device_seq    bigint NOT NULL,
  type          text NOT NULL,
  booking_id    uuid,
  payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at   timestamptz NOT NULL,
  approximate   boolean NOT NULL DEFAULT false,
  result        text NOT NULL CHECK (result IN ('applied', 'rejected')),
  reason        text,
  flagged       boolean NOT NULL DEFAULT false,         -- needs manager review
  received_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX device_events_staff_idx ON device_events (staff_id, received_at DESC);

-- Sync conflicts / rejected transitions for the manager (design §3, §6.2, §9.6).
CREATE TABLE sync_conflicts (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id              uuid REFERENCES staff(id),
  booking_id            uuid REFERENCES bookings(id),
  device_event_id       uuid,
  kind                  text NOT NULL,
  details               jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at            timestamptz NOT NULL DEFAULT now(),
  resolved_at           timestamptz,
  resolved_by_staff_id  uuid REFERENCES staff(id)
);
CREATE INDEX sync_conflicts_open_idx ON sync_conflicts (created_at DESC) WHERE resolved_at IS NULL;

-- ─── Idempotency-Key results (api.md "قواعد عامة") ──────────────────────────────────
CREATE TABLE idempotency_keys (
  subject_kind  text NOT NULL CHECK (subject_kind IN ('staff', 'customer')),
  subject_id    uuid NOT NULL,
  key           uuid NOT NULL,
  scope         text NOT NULL,
  status_code   integer NOT NULL,
  response      jsonb NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (subject_kind, subject_id, key)
);

-- ─── Notifications (design §8): outbox + record of what was sent ────────────────────
CREATE TABLE notifications (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_kind  text NOT NULL CHECK (recipient_kind IN ('staff', 'customer')),
  recipient_id    uuid NOT NULL,
  type            text NOT NULL,
  booking_id      uuid REFERENCES bookings(id),
  title           text NOT NULL,
  body            text NOT NULL,
  data            jsonb NOT NULL DEFAULT '{}'::jsonb,
  high_priority   boolean NOT NULL DEFAULT false,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'sent', 'failed', 'no_device', 'disabled')),
  attempts        integer NOT NULL DEFAULT 0,
  last_error      text,
  dedupe_key      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  sent_at         timestamptz
);
CREATE UNIQUE INDEX notifications_dedupe_key ON notifications (dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX notifications_pending_idx ON notifications (created_at) WHERE status = 'pending';
CREATE INDEX notifications_recipient_idx ON notifications (recipient_kind, recipient_id, created_at DESC);
CREATE INDEX notifications_booking_idx ON notifications (booking_id, created_at);
