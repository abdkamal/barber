-- Phase 6 review fixes (independent code review). Additive and backward compatible with 003.

-- ─── ق23 on server-known facts only (review I1/H1) ──────────────────────────────────
-- The reference the customer had BEFORE the system itself moved his time earlier (a call or an
-- "earlier" ق5 notice). The ق23 exemption compares against this, never against client input.
ALTER TABLE bookings
  ADD COLUMN reference_before_advance timestamptz,
  -- Set when an active booking of a past business day was closed out by the server (review C1).
  ADD COLUMN day_closed_at            timestamptz;

-- ─── ق20 linking only after approval (review H2) ────────────────────────────────────
ALTER TABLE customers
  -- Walk-in record matched at registration; becomes linked_walk_in_id only when the manager approves.
  ADD COLUMN proposed_walk_in_id uuid REFERENCES customers(id),
  -- The manager released this account's phone (dispute): the account is suspended and the number
  -- is free for its real owner. The row keeps the number for the audit trail.
  ADD COLUMN phone_released_at   timestamptz;

DROP INDEX customers_account_phone_key;
CREATE UNIQUE INDEX customers_account_phone_key ON customers (phone) WHERE password_hash IS NOT NULL AND phone_released_at IS NULL;

-- ─── Owner protection (review L5) ───────────────────────────────────────────────────
ALTER TABLE staff ADD COLUMN is_owner boolean NOT NULL DEFAULT false;
UPDATE staff SET is_owner = true
 WHERE id = (SELECT id FROM staff WHERE role = 'manager' ORDER BY created_at, id LIMIT 1);
CREATE UNIQUE INDEX staff_one_owner ON staff ((true)) WHERE is_owner;

-- ─── Payments: server price is the expected amount; the device amount is recorded (review) ──
ALTER TABLE payments
  ADD COLUMN confirmed_amount_minor bigint CHECK (confirmed_amount_minor IS NULL OR confirmed_amount_minor >= 0),
  ADD COLUMN discrepancy            boolean NOT NULL DEFAULT false;
UPDATE payments SET confirmed_amount_minor = amount_minor WHERE status = 'confirmed';
