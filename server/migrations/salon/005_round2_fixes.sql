-- Round-2 fixes after the phase-10 verification. Additive and backward compatible with 004.

-- ─── Stale operational day is bounded (item 1) ──────────────────────────────────────
-- A past business day stays "operational" after closing (ق24) at most this long after its shift
-- end — or until the next shift's booking window opens, whichever comes first.
ALTER TABLE settings
  ADD COLUMN day_close_grace_minutes integer NOT NULL DEFAULT 360 CHECK (day_close_grace_minutes BETWEEN 60 AND 720);

-- ─── ق23 on server-issued times only (H1 residual) ──────────────────────────────────
-- The last expected time the SERVER itself gave the customer (confirmation, call, ق5 notice,
-- postponement, transfer, change-time). Never written from the client's "seen" report, which only
-- feeds last_shown_expected_start (the ق5 reference). reference_before_advance is derived from it.
ALTER TABLE bookings ADD COLUMN told_expected_start timestamptz;
UPDATE bookings SET told_expected_start = original_expected_start WHERE told_expected_start IS NULL;

-- ─── Refresh-token grace on flaky networks (item 7) ─────────────────────────────────
ALTER TABLE refresh_tokens
  -- The one grace re-issue this (already rotated) token was allowed.
  ADD COLUMN grace_used_at timestamptz,
  -- Tokens issued in parallel for one rotation (the normal successor and the grace re-issue):
  -- rotating either one revokes the other, so the family never keeps two live branches.
  ADD COLUMN sibling_id    uuid;
