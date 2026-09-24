-- ق40: offline events of a suspended staff account, uploaded by a manager from that device.
-- Additive and backward compatible with 005.

-- ─── Suspension time ─────────────────────────────────────────────────────────────────
-- When the account was last suspended (active → false); cleared when it is reactivated. Only events
-- whose (monotonic-clock-corrected) device time is strictly before it can be recovered.
ALTER TABLE staff ADD COLUMN suspended_at timestamptz;

-- Accounts already suspended before this migration: the audit entry that deactivated them (the
-- latest one), else the row's last update — the best record the database has.
UPDATE staff s
   SET suspended_at = COALESCE(
         (SELECT max(a.occurred_at) FROM audit_log a
           WHERE a.action = 'staff.access_changed' AND a.target_id = s.id
             AND a.details -> 'to' ->> 'active' = 'false'),
         s.updated_at)
 WHERE NOT s.active AND s.suspended_at IS NULL;

-- ─── Recovered-by-manager marker ─────────────────────────────────────────────────────
-- The manager who uploaded the event on behalf of the suspended account (NULL = normal sync).
ALTER TABLE device_events  ADD COLUMN recovered_by_staff_id uuid REFERENCES staff(id);
ALTER TABLE booking_events ADD COLUMN recovered_by_staff_id uuid REFERENCES staff(id);

-- Pending review list (sync_conflicts rows of kind 'recovered_event' until acknowledged).
CREATE INDEX sync_conflicts_recovered_open_idx ON sync_conflicts (created_at DESC)
  WHERE kind = 'recovered_event' AND resolved_at IS NULL;
