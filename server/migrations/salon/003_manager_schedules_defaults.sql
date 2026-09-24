-- Milestone 4b (manager): salon-wide default weekly schedule rows (design §2, ق30) —
-- a NULL staff_id row means "salon default for that weekday", overridden by a per-barber row.
-- Also a couple of indexes that speed up the manager reports (design §9).

ALTER TABLE work_schedules ALTER COLUMN staff_id DROP NOT NULL;
ALTER TABLE work_schedules DROP CONSTRAINT work_schedules_staff_weekday_key;
-- One row per weekday per barber, and at most one salon-default row per weekday.
CREATE UNIQUE INDEX work_schedules_staff_weekday_key ON work_schedules (staff_id, weekday) WHERE staff_id IS NOT NULL;
CREATE UNIQUE INDEX work_schedules_default_weekday_key ON work_schedules (weekday) WHERE staff_id IS NULL;

CREATE INDEX IF NOT EXISTS bookings_actual_start_idx ON bookings (work_date, actual_start);
CREATE INDEX IF NOT EXISTS booking_events_type_idx ON booking_events (type, occurred_at);
