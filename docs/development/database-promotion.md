# Database migration and production promotion

Cha-Ching uses Cloudflare D1 as the production source of truth. Production data
contains user identity, subscriptions, provider connections, payment history,
webhook state, APNs device tokens, and notification delivery state. Treat every
remote D1 command as a production mutation unless the command explicitly uses a
staging database binding.

## Current schema authority

The current schema authority is the ordered SQL files in
`backend/migrations/`. The project does not yet use Drizzle as the schema
authority. Do not introduce Drizzle-generated migrations until the current D1
schema has been ported and reviewed as a single TypeScript schema model.
The architectural split is recorded in
[`ADR-0011`](../adr/0011-drizzle-d1-schema-ownership.md).

Wrangler applies migrations locally or remotely:

```bash
cd backend
pnpm db:migrate:local
pnpm db:migrations:local:status
pnpm db:migrations:production:status
CONFIRM_PRODUCTION_MIGRATIONS=cha-ching-prod pnpm db:migrate:production
```

Remote migration status and apply commands require a Cloudflare account/API
token with access to the configured D1 database.

## Local development

Use local D1 for implementation and simulator QA:

```bash
cd backend
pnpm install
pnpm db:migrate:local
pnpm dev
```

Local Wrangler state lives under `backend/.wrangler/state`. It is disposable and
must not be treated as production evidence.

Local seeds are opt-in fixtures. Seed scripts must include `--local` and
`--persist-to .wrangler/state`. Do not add a package script that seeds remote D1.

Migration filenames use a unique, increasing numeric prefix. The existing
four-digit `0001`–`0015` history remains contiguous; the eventual Drizzle
baseline may use a longer generated prefix after its output format is verified.

## Staging and preview

Before a feature needs production-like promotion rehearsal, add a separate D1
database and Wrangler environment for staging. A staging database must have its
own `database_id`, secrets, provider callback URLs, queues, and APNs/testing
policy. Do not point staging code at `cha-ching-prod`.

The staging promotion flow should mirror production:

1. Apply migrations to staging.
2. Deploy the staging Worker.
3. Run authenticated smoke tests against staging.
4. Promote the same commit and migration set to production.

Until staging exists, TestFlight builds that point at production must be treated
as production releases.

## Production promotion checklist

Run this from a clean feature branch after review and before asking anyone to
exercise a production/TestFlight build that depends on new backend schema:

```bash
cd backend
pnpm promote:check
CONFIRM_PRODUCTION_MIGRATIONS=cha-ching-prod pnpm db:migrate:production
pnpm db:migrations:production:status
pnpm deploy
CHA_CHING_SMOKE_BEARER_TOKEN='<redacted>' pnpm smoke:production
```

Then run the product-specific production smoke tests. For authenticated app
features, unauthenticated `401` only proves the route exists; it does not prove
the D1 tables or user-scoped queries work.

## Migration sequencing rules

Prefer backward-compatible migrations:

1. Add nullable columns, new tables, new indexes, or new write-compatible state.
2. Apply the remote migration.
3. Deploy Worker code that reads/writes the new shape.
4. Promote the iOS/TestFlight build that depends on it.

For incompatible changes, use expand/contract:

1. Expand schema.
2. Deploy code that supports old and new shapes.
3. Backfill with an explicit reviewed script if required.
4. Verify production smoke checks.
5. Contract old schema in a later release after no deployed code depends on it.

Never deploy Worker code that requires a new table or column before the remote
migration has been applied, unless the code safely handles both old and new
schemas.

## Dashboard/preferences smoke test

For Home dashboard and reporting-timezone changes, verify all of the following:

1. `pnpm db:migrations:production:status` reports no pending migrations.
2. `GET /health` returns HTTP 200.
3. A signed-in full-access TestFlight account can initialize Settings →
   Reporting timezone.
4. `GET /v1/preferences` returns a non-null `reportingTimezone` for that user.
5. `GET /v1/dashboard?period=4w` returns HTTP 200 and the expected
   `reportingTimezone`.
6. Home shows either real dashboard data or the intended empty state, not
   “Dashboard unavailable.”

Do not use production sample data to satisfy these checks.

`pnpm smoke:production` performs the read-only HTTP portion with a dedicated
full-access smoke account. It reads the bearer token only from
`CHA_CHING_SMOKE_BEARER_TOKEN`, never prints it, and validates `/health`,
identity, subscription, connection, sales, preference, and dashboard response
shapes against the hard-coded production origin. A future staging environment
must add a separately named smoke command rather than overriding this target.
The migration apply wrapper accepts no arguments and requires the exact
`CONFIRM_PRODUCTION_MIGRATIONS=cha-ching-prod` confirmation value.

## Drizzle adoption plan

Issue #76 tracks the Drizzle refactor. The safe path is:

1. Add Drizzle and Drizzle Kit in a branch dedicated to database workflow.
2. Port the existing D1 schema into `backend/src/db/schema.ts`.
3. Generate SQL into a separate temporary output and compare it against the
   existing migrations before accepting Drizzle as the schema authority.
4. Keep existing raw migrations as historical migrations.
5. Configure Drizzle Kit to generate future migrations into the repo's migration
   directory only after the generated SQL shape is reviewed.
6. Keep Wrangler as the D1 apply mechanism unless a Drizzle runner is explicitly
   proven safe for this Worker/D1 deployment model.
7. Forbid `drizzle-kit push` against production; use committed migrations.

Until that work is complete, raw SQL migrations plus this runbook are the
production workflow.
