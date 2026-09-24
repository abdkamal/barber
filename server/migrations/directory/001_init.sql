-- Directory database: one row per salon; each salon has its own database (ق1، ق8).

CREATE TABLE salons (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code            text NOT NULL,
  name            text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 80),
  db_name         text NOT NULL CHECK (db_name ~ '^[a-z][a-z0-9_]{0,62}$'),
  timezone        text NOT NULL,
  currency        char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  status          text NOT NULL DEFAULT 'pending_activation'
                    CHECK (status IN ('pending_activation', 'active', 'suspended')),
  registered_at   timestamptz NOT NULL DEFAULT now(),
  activated_at    timestamptz,
  suspended_at    timestamptz,
  -- Last migration version successfully applied to the salon database (0 = not provisioned yet).
  schema_version  integer NOT NULL DEFAULT 0 CHECK (schema_version >= 0),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT salons_code_format CHECK (code ~ '^[A-Z]{2,6}-[0-9]{2,4}$'),
  CONSTRAINT salons_code_key UNIQUE (code),
  CONSTRAINT salons_db_name_key UNIQUE (db_name),
  CONSTRAINT salons_active_has_activation CHECK (status <> 'active' OR activated_at IS NOT NULL)
);

CREATE INDEX salons_status_idx ON salons (status, registered_at);
