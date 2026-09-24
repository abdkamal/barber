-- ق40 review (F2): every suspension interval of a staff account is kept, so events done while the
-- account was suspended and uploaded after its reactivation (normal sync) are flagged for review.
-- Additive and backward compatible with 006.

CREATE TABLE staff_suspensions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id       uuid NOT NULL REFERENCES staff(id),
  suspended_at   timestamptz NOT NULL,
  -- NULL while the account is still suspended.
  reactivated_at timestamptz,
  CHECK (reactivated_at IS NULL OR reactivated_at >= suspended_at)
);
CREATE INDEX staff_suspensions_staff_idx ON staff_suspensions (staff_id, suspended_at DESC);
-- At most one open interval per account.
CREATE UNIQUE INDEX staff_suspensions_open_idx ON staff_suspensions (staff_id) WHERE reactivated_at IS NULL;

-- Accounts suspended right now (006 recorded when): their open interval. Earlier, already closed
-- intervals were not recorded before this migration.
INSERT INTO staff_suspensions (staff_id, suspended_at)
SELECT id, suspended_at FROM staff WHERE NOT active AND suspended_at IS NOT NULL;
