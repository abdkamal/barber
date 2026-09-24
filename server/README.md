# Saloni server (صالوني — السيرفر)

NestJS + PostgreSQL 16. One **directory** database (`salons`) plus **one database per salon**
(design §1–2, ق1/ق8), reached through PgBouncer (transaction pooling). API contract: `docs/api.md`
(all routes under `/v1`).

## Run (development)

```bash
docker compose -f infra/docker-compose.yml up -d --wait   # PostgreSQL :5432 + PgBouncer :6432
npm install                                               # from the repo root (npm workspaces)
cd server
cp .env.example .env        # optional — defaults match the compose file
npm run migrate             # directory DB, then every salon DB
npm run start:dev           # http://localhost:3000/v1/health
```

Production: `npm run build && npm start` (set `NODE_ENV=production` and the secrets below).

## Tests

```bash
npm test            # unit tests (no database)
npm run test:int    # integration tests against real PostgreSQL + PgBouncer
```

`test:int` needs the compose stack (it tries `docker compose up -d --wait` itself if the
databases are unreachable). It drops and recreates every database named `saloni_test_*`; it never
touches the development databases. Covered: cross-tenant isolation (crafted headers/query/body,
tampered/foreign tokens, directory→database identity check), refresh rotation & reuse detection,
logout, progressive backoff, rate limits, reset codes, approval/suspension, append-only
`booking_events`/`audit_log`, commit-ordered change sequence, migration runner (stop at first failure,
checksums), provisioning rollback, pool eviction.

## Environment variables

See `.env.example` for the full list with defaults. The important ones:

| Variable | Purpose |
|---|---|
| `PG_HOST` / `PG_PORT` / `PG_USER` / `PG_PASSWORD` | runtime connections (PgBouncer) |
| `PG_ADMIN_*` | direct PostgreSQL connection for `CREATE DATABASE` and migrations (role needs `CREATEDB`) |
| `DIRECTORY_DB_NAME`, `SALON_DB_PREFIX` | directory DB name; prefix of per-salon DB names (`<prefix><code>`) |
| `TENANT_POOL_MAX`, `TENANT_POOL_IDLE_TTL_MS`, `TENANT_POOLS_MAX` | small lazily-created pool per salon, closed when idle, capped in number |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `RESET_CODE_PEPPER` | **required in production**, ≥ 32 chars, all different |
| `ACCESS_TOKEN_TTL_SEC` (900), `REFRESH_TOKEN_TTL_DAYS` (30), `RESET_CODE_TTL_HOURS` (24) | token lifetimes |
| `ARGON2_*` | Argon2id cost (default 19 MiB, t=2, p=1) |
| `TRUST_PROXY` | proxy hops to trust for the client IP (rate limits/backoff). Keep `false` unless behind a proxy |
| `CORS_ORIGINS` | comma-separated browser origins; empty = CORS off (mobile apps don't need it) |
| `BACKOFF_*` | progressive login backoff |

## CLI

```bash
npm run migrate                                        # directory, then each salon DB in turn; stops at first failure
npm run vendor -- list [--status pending_activation|active|suspended]
npm run vendor -- pending                              # salons waiting for activation
npm run vendor -- activate RAHA-27
npm run vendor -- suspend RAHA-27
npm run vendor -- reset-manager-password RAHA-27 [--username owner]   # prints a one-time code (24 h)
```

## Endpoints in this milestone

| Route | Auth |
|---|---|
| `GET /v1/health` | public |
| `POST /v1/salons/register` | public, rate-limited — creates a `pending_activation` salon + its DB + the owner as manager; returns the code and an owner session |
| `GET /v1/salons/{code}` | public — profile of **active** salons only (404 otherwise) |
| `POST /v1/auth/customer/register`, `/customer/login`, `/staff/login` | public, rate-limited + backoff |
| `POST /v1/auth/refresh`, `/logout`, `/reset` | public (refresh token / one-time code) |
| `GET /v1/auth/session` | any signed-in user |
| `GET/POST/PUT /v1/manager/staff`, `POST /v1/manager/staff/{id}/reset-code` | manager |
| `GET /v1/manager/customers`, `POST …/{id}/approve\|suspend\|reset-code` | manager |
| `GET/PUT /v1/manager/settings` | manager |

Errors: `{"error":{"code":"UPPER_SNAKE","message":"نص عربي"}}`; `429` carries `Retry-After`.

## Layout

```
src/
  config/        env → typed config
  db/            pools (PgBouncer runtime + direct admin), migration runner, migrate-all
  directory/     salons table access, salon-code generation
  tenancy/       TenantContext (tenant-bound DB handle), TenantResolver, @Tenant()
  auth/          passwords (Argon2id), JWTs, sessions/refresh rotation, backoff, reset codes, guard
  security/      rate limiter + guard, audit log, client IP
  provisioning/  self-registration, public salon profile, vendor service
  staff/ customers/ settings/   manager endpoints + repositories
  cli/           migrate.ts, vendor.ts
migrations/
  directory/NNN_*.sql
  salon/NNN_*.sql
test/            integration tests (*.int-spec.ts)
```

## Tenancy rules (for later milestones)

- The salon of an authenticated request comes **only** from the verified access token
  (`AuthGuard` → `req.tenant`). Use `@Tenant() t: TenantContext` and pass `t.db` (or a `t.db.tx`
  handle) to repositories; repositories accept only the branded `TenantQueryable` type.
- Never read a salon id/code from headers, query or body on authenticated routes.
- Background jobs (timers, notifications) must obtain a context per salon through `TenantResolver`.
- Scheduling logic lives in `packages/engine`; bookings/sync/timers/reports modules plug into `AppModule`.
