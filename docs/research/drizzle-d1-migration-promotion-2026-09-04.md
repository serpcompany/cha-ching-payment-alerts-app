# Drizzle and D1 migration promotion research

Date: 2026-09-04

## Question

What database migration and promotion workflow should Cha-Ching use before it
depends on new Cloudflare D1 schema from production iOS/TestFlight builds?

## Findings

### Current repository state

Cha-Ching currently uses raw SQL migrations in `backend/migrations/` and applies
them with Wrangler. There is no Drizzle schema authority, no staging D1 binding,
and no production promotion runbook that forces remote migration verification
before Worker or iOS promotion.

This is enough for local development, but it allowed a valid TestFlight build to
reach production before the dashboard/preference schema and Worker deployment
had been proven together.

### Drizzle and D1

Drizzle supports Cloudflare D1 through the `drizzle-orm/d1` driver and expects a
Worker D1 binding to be passed into `drizzle(env.DB)`. Drizzle's D1 guide also
uses `drizzle-kit generate` to generate SQL migration files from a TypeScript
schema and Wrangler to apply those migrations to D1.

Source: [Drizzle ORM: Get started with Cloudflare D1](https://orm.drizzle.team/docs/get-started/d1-new)

Drizzle Kit separates migration generation from execution. `generate` produces
SQL migration files from schema changes, while `migrate` is Drizzle Kit's
migration runner for supported connection configs. Drizzle also documents
`push` as a direct schema-push workflow for rapid iteration. For Cha-Ching,
`push` should not be used against production because production needs reviewed,
committed, ordered migration files.

Sources:

- [Drizzle Kit generate](https://orm.drizzle.team/docs/drizzle-kit-generate)
- [Drizzle Kit migrate](https://orm.drizzle.team/docs/drizzle-kit-migrate)
- [Drizzle Kit push](https://orm.drizzle.team/docs/drizzle-kit-push)

### Cloudflare D1 migrations

Cloudflare D1's Wrangler workflow creates, lists, and applies migrations with
`wrangler d1 migrations create`, `wrangler d1 migrations list`, and
`wrangler d1 migrations apply`. Cloudflare distinguishes local and remote D1
execution with `--local` and `--remote`. Local state can be persisted with
`--persist-to`; remote commands mutate the configured Cloudflare database.

Source: [Cloudflare D1 Wrangler commands](https://developers.cloudflare.com/d1/wrangler-commands/)

Cloudflare documents D1 import/export separately from migrations. Import/export
is useful for backup, restore, and explicit data transfer. It should not be used
as a normal production data promotion path for Cha-Ching because production rows
contain user, provider, payment, webhook, device, and notification state.

Sources:

- [Cloudflare D1 import and export data](https://developers.cloudflare.com/d1/best-practices/import-export-data/)
- [Cloudflare D1 backups and Time Travel](https://developers.cloudflare.com/d1/best-practices/backups/)

### Matt Pocock / Total TypeScript

I did not find a primary Matt Pocock or Total TypeScript source that defines a
Cloudflare D1 production migration-promotion workflow for Drizzle. Issue #76
should therefore treat Drizzle and Cloudflare documentation as the source of
truth, and use Matt Pocock's label conventions only where the repository already
does so through `docs/agents/triage-labels.md`.

## Recommendation for Cha-Ching

Use Drizzle for typed schema/query ergonomics only after the existing raw SQL
schema has been ported into one TypeScript schema authority. Until then, keep
Wrangler SQL migrations as the source of truth. Do not run Drizzle `push` or any
schema diff tool against production.

The safe production workflow is:

1. Write backward-compatible migrations first.
2. Run backend tests against a fresh local D1 assembled from all migrations.
3. Run `wrangler deploy --dry-run`.
4. Check remote migration status.
5. Apply remote migrations.
6. Deploy the Worker that depends on those migrations.
7. Run production smoke checks.
8. Only then promote or ask users to exercise a TestFlight build that depends on
   the new API/schema.

Backward-incompatible migrations need an expand/contract sequence:

1. Expand schema in a migration.
2. Deploy Worker code that writes both old and new forms or tolerates both.
3. Backfill if needed with an explicitly reviewed script.
4. Verify smoke tests.
5. Contract old schema in a later release only after deployed code no longer
   reads it.

## Data movement boundary

Local seeds are allowed only against local D1. Production data should never be
copied into local development by default. If a future incident requires a data
extract, it must be a separate, named, reviewed operation with a minimization
plan, redaction plan, and deletion plan.

For ordinary UI QA, create synthetic local seeds. For staging, use synthetic or
manually created test accounts. For production, use only real user/provider data
created by the app and provider webhooks.

## First implementation step

Before full Drizzle adoption, add a production promotion runbook and scripts for:

- local migration status;
- remote migration status;
- pre-promotion checks;
- explicit remote migration apply;
- explicit Worker deploy;
- documented production smoke tests.

This gives agents and humans a safe path immediately while preserving a clean
future Drizzle migration rather than mixing two schema authorities.
