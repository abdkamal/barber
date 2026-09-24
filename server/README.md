# Saloni server (صالوني — السيرفر)

NestJS + PostgreSQL 16. One **directory** database (`salons`) plus **one database per salon**
(design §1–2, ق1/ق8), reached through PgBouncer (transaction pooling). API contract: `docs/api.md`
(all routes under `/v1`).

## Run (development)

```bash
docker compose -f infra/docker-compose.yml up -d --wait   # PostgreSQL :5432 + PgBouncer :6432
npm install                                               # from the repo root (npm workspaces)
cd server
cp .env.example .env        # then fill the three secrets (see below) — required unless NODE_ENV=test
npm run migrate             # directory DB, then every salon DB
npm run start:dev           # http://localhost:3000/v1/health
```

Production: `npm run build && npm start` (set `NODE_ENV=production` and the secrets below).

**Startup checks (review M3):** the server (and the CLIs) refuse to start unless `NODE_ENV` is set
explicitly to `development`, `test` or `production`, and — whenever it is not `test` — unless
`JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` and `RESET_CODE_PEPPER` are real secrets (≥ 32 chars, all
different, not a placeholder). Generate each with
`node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"`.

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
checksums), provisioning rollback, pool eviction; and for milestone 4b: the booking flow end to end,
ق4/ق19 placement, ق13 offers and expiry, booking window, max active bookings, idempotency, parallel
bookings, change-time, cancel, sync ordering/idempotency, ق22 skip, ق10/ق21/ق23 postponement and
no-show, absent barber, offline conflicts, revoked-account events, ق9 impact, ق24, breaks, the
change feed, the WebSocket stream, ق3 offline windows, calling, ق5 in both directions with
suppression and one reconciled notice, ق27, ق32, and cross-tenant isolation of all new endpoints.

## Environment variables

See `.env.example` for the full list with defaults. The important ones:

| Variable | Purpose |
|---|---|
| `PG_HOST` / `PG_PORT` / `PG_USER` / `PG_PASSWORD` | runtime connections (PgBouncer) |
| `PG_ADMIN_*` | direct PostgreSQL connection for `CREATE DATABASE` and migrations (role needs `CREATEDB`) |
| `DIRECTORY_DB_NAME`, `SALON_DB_PREFIX` | directory DB name; prefix of per-salon DB names (`<prefix><code>`) |
| `TENANT_POOL_MAX`, `TENANT_POOL_IDLE_TTL_MS`, `TENANT_POOLS_MAX` | small lazily-created pool per salon, closed when idle, capped in number |
| `NODE_ENV` | **required**: `development` \| `test` \| `production` |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `RESET_CODE_PEPPER` | **required unless `NODE_ENV=test`**, ≥ 32 chars, all different, no placeholders |
| `ACCESS_TOKEN_TTL_SEC` (900), `REFRESH_TOKEN_TTL_DAYS` (30), `RESET_CODE_TTL_HOURS` (24) | token lifetimes |
| `ARGON2_*` | Argon2id cost (default 19 MiB, t=2, p=1) |
| `TRUST_PROXY` | whose `X-Forwarded-For` to trust for the client IP (rate limits/backoff): `false`, a hop count, or a comma-separated list of proxy IPs/CIDRs. `true` is refused in production — see "Behind nginx" |
| `CORS_ORIGINS` | comma-separated browser origins; empty = CORS off (mobile apps don't need it) |
| `BACKOFF_*` | progressive login backoff per account+IP and per IP; `BACKOFF_ACCOUNT_*` a slow account-wide delay (all IPs, capped at a few seconds, never a lockout) |
| `MAX_PENDING_SALONS` | self-registration pauses (`503 REGISTRATION_PAUSED`) while this many salons wait for activation (default 50) |

### Behind nginx (TLS termination)

Run nginx on the same host and let it be the only way in (bind the Node server to `127.0.0.1`):

```nginx
server {
    listen 443 ssl http2;
    server_name api.example.com;
    # ssl_certificate … / ssl_certificate_key …; TLS 1.2+ only
    client_max_body_size 6m;                       # photo uploads (5 MB) + multipart overhead

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host              $host;
        proxy_set_header X-Forwarded-For   $remote_addr;   # overwrite, never append the client's header
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location /v1/staff/stream {                    # WebSocket
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_read_timeout 120s;
    }
}
```

and set `HOST=127.0.0.1`, `TRUST_PROXY=1` (one hop) — or `TRUST_PROXY=127.0.0.1` (trust only that
proxy's address). Because nginx *overwrites* `X-Forwarded-For` with the real peer address, a client
cannot spoof its IP. Never use `TRUST_PROXY=true`: any client could then choose the IP that rate
limits and login backoff are keyed on. Do not log query strings of `/v1/staff/stream` (tokens are no
longer accepted there, but old clients may still send them).

## CLI

```bash
npm run migrate                                        # directory, then each salon DB in turn; stops at first failure
npm run vendor -- list [--status pending_activation|active|suspended]
npm run vendor -- pending                              # salons waiting for activation
npm run vendor -- activate RAHA-27
npm run vendor -- suspend RAHA-27
npm run vendor -- reset-manager-password RAHA-27 [--username owner]   # prints a one-time code (24 h)
npm run vendor -- cleanup-pending [--older-than-days 14] [--dry-run] # drop never-activated salons (DB + directory row)
```

Run `cleanup-pending` from cron (e.g. daily) so abandoned self-registrations do not accumulate; the
global `MAX_PENDING_SALONS` cap bounds them in between.

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

### Milestone 4b — bookings, sync, scheduler, notifications

| Route | Auth |
|---|---|
| `GET /v1/customer/today`, `POST /v1/bookings/quote`, `POST /v1/bookings`, `DELETE /v1/offers/{id}`, `GET /v1/bookings/current`, `POST /v1/bookings/{id}/seen\|change-time\|cancel`, `GET /v1/customer/history` | customer (booking needs an **active** account) |
| `GET /v1/staff/today`, `POST /v1/staff/walk-ins`, `POST /v1/staff/impact`, `GET /v1/staff/payments`, `POST /v1/heartbeat`, `POST /v1/sync/events`, `GET /v1/sync?since=` | barber, manager (own queue; managers see all payments/changes) |
| `WS /v1/staff/stream` | barber, manager — access token in `Authorization`, in `Sec-WebSocket-Protocol: saloni.v1, bearer.<token>`, or a first message `{"type":"auth","token":…}` (never in the URL); ≤ 3 sockets per account |
| `POST /v1/devices` | any signed-in user |
| `GET /v1/manager/queues`, `POST /v1/manager/bookings/{id}/transfer` | manager (ق25: all queues today; manual transfer under ق4, both barber days locked in id order, customer notified) |

Shapes are pinned in `docs/api.md` ("أشكال مثبّتة"). Booking-changing requests honour `Idempotency-Key`
(stored per account in `idempotency_keys`; a replay returns the first result, including a remembered 409 offer).

**How it works**

- `src/scheduling/` — the bridge to `@saloni/engine`: salon-timezone business day (ق30, `time.ts`),
  loading a barber's day into engine types (`day.ts`: schedule incl. salon defaults, recurring/dated
  breaks, walk-in-only windows, absences, queue in service order, day state from heartbeats), and
  persisting a new queue (`commitQueue`: positions, projections, an `eta_changed` booking event with
  its reason for everyone who moved, a `queue_updated` change). **Every queue mutation runs in a
  transaction that first locks the barber-day row (`SELECT … FOR UPDATE`)**; auto-assign locks all
  candidate days in id order. Expired offers are released by any locked load.
- `bookings/` — customer flows. Offers (ق13) are real `offered` rows holding their place (ق4 protects
  them) until `offer_expires_at`.
- `staff-day/` — barber endpoints; walk-ins go to the end of the barber's queue, or into a
  walk-in-only window (ق33) when they fit there without delaying anyone.
- `sync/` — device events applied in `deviceSeq` order, one transaction each, once per event id
  (`device_events`); rejected transitions and conflicts go to `sync_conflicts` for the manager.
  `GET /sync` reads the commit-ordered `changes` feed; the WebSocket only pushes new seq numbers.
- `scheduler/` — one in-process loop (1 s tick) with a next-due time per salon (offer expiry, next
  call, heartbeat timeout, shift start, overrun; at most 60 s while a shift runs, 10 min otherwise);
  any committed queue change pokes its salon. Disabled when `NODE_ENV=test` unless
  `SCHEDULER_ENABLED=true` (tests drive `SchedulerService.runSalon`).
- `notifications/` — outbox table `notifications` (every notice is kept with its delivery status),
  dispatched after commit through a `Notifier`: FCM HTTP v1, an in-memory fake in tests, or disabled
  (recorded as `disabled`) when no credentials are set.

| Variable | Purpose |
|---|---|
| `FCM_SERVICE_ACCOUNT_FILE` *or* `FCM_PROJECT_ID` + `FCM_CLIENT_EMAIL` + `FCM_PRIVATE_KEY` | Firebase service account for FCM HTTP v1 (push disabled if absent) |
| `SCHEDULER_ENABLED` | force the background loop on/off (default: on except in tests) |

The server consumes `@saloni/engine` from `packages/engine/dist` at runtime (`npm run build:engine`,
run automatically by `build`, `start:dev` and `test:int`); typecheck and Jest use its TypeScript
sources directly.

### Phase 6 review fixes (summary)

- **Operational day (C1):** `scheduling/day.ts#operationalShift` — the running shift, or after closing
  the latest ended shift that still has active bookings (served late, ق24) until the next day's
  booking window opens. Used by staff today, heartbeat, manager queues and the scheduler; walk-ins and
  new bookings still need the running shift. `scheduling/day-close.ts` closes out stale days
  (waiting/called → cancelled `day_closed` + notice; in service → `needs_review` + conflict) and
  device breaks left open.
- **ق23 on server facts (I1/H1):** `bookings.reference_before_advance` keeps the reference the
  customer had before a call / earlier ق5 notice moved him earlier; the exemption uses it.
  `POST /bookings/{id}/seen` records only values within 5 min of the server projection.
- **Manager breaks/absences (I6):** `schedules/schedule-changes.service.ts` — locked days, queue
  committed with `schedule_changed` / `barber_absent`, `breaks_changed` / `day_state` changes.
- **Lock ordering:** `lockDays()` locks every day of an operation (id order) before any change is
  emitted (quote with offer replacement, auto-assign, transfer).
- **Security:** ق20 links only after approval + unlink / reassign / release phone (H2); uploads for
  active salons only, sharp ≥ 0.35.4 (H3); normalised rate-limit keys + account-wide slow delay (M1);
  strict `TRUST_PROXY` (M2); explicit `NODE_ENV` + real secrets (M3); pending-salon cap + cleanup CLI,
  sync pre-validation, capped conflict rows, per-account sync budget (M4); clamped device times (L1);
  server price as expected payment amount + recorded device amount (L2); https social links (L3);
  generic register response (L4); owner / last-manager protection (L5); WebSocket auth without URL
  tokens, per-account cap, batched revalidation (L6); price/duration bounds (L8). Migration
  `salon/004_review_fixes.sql`.

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
  scheduling/    engine bridge: business day, day loading, queue persistence, idempotency, clock
  bookings/      customer booking endpoints
  staff-day/     barber endpoints (today, walk-ins, impact, payments, heartbeat)
  manager-queues/ manager: all queues today, manual transfer (ق25)
  sync/          device events, change feed, WebSocket stream
  scheduler/     background loop
  notifications/ notifier (FCM / fake / disabled), texts, outbox dispatch, devices
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
