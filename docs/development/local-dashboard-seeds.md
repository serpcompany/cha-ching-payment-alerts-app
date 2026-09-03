# Local dashboard seeds

Use local seeds when a feature needs realistic data for visual QA in the iOS
Simulator. Seeds are opt-in development fixtures, not schema history.

## Current workflow

The repository does not use Drizzle. D1 schema changes live in
`backend/migrations/` and are applied with Wrangler. Keep that boundary unless
the project needs a broader typed query/migration layer; adding an ORM only for
local fixtures would create a second schema authority.

From `backend/`, after local migrations and the local Worker are running:

```bash
pnpm db:migrate:local
pnpm dev
pnpm db:seed:dashboard:local
```

`db:seed:dashboard:local` executes `backend/seeds/dashboard-v1.sql` with
Wrangler's `--local` flag and `--persist-to .wrangler/state`. Do not add a
remote seed script. Do not put sample data in migrations.

The dashboard seed targets the most recent anonymous Simulator user in local D1.
Create that user from the app's debug-only **Use local Simulator account** flow
before seeding. The seed is idempotent for rows whose IDs start with
`seed-dashboard-v1-`; rerunning it refreshes those rows relative to the current
clock without deleting unrelated local payments.

## Fixture shape

Dashboard fixtures should cover the states that can break visual or reporting
logic:

- empty account, by using a fresh local Simulator user before seeding;
- same-day Today totals in the saved reporting timezone;
- current and previous 4-week comparison windows;
- multiple products and source types: Stripe, PayPal, named custom webhook;
- multiple currencies, because dashboard money totals must stay separated;
- a custom-source fallback payment whose source row no longer exists;
- enough historical payments to exercise charts and period switching.

Future seeds should add separate files when they exercise meaningfully different
behavior. Prefer names like `backend/seeds/dashboard-dst.sql` or
`backend/seeds/payments-over-100.sql`, with corresponding local-only package
scripts.

## Local auth and access

Simulator QA should use the debug-only anonymous sign-in route documented in
`simulator-auth.md`; do not use a real Apple account just to inspect local
dashboard data. The local seed grants the anonymous user the three connection
entitlements so the app can pass the full-access API gate without a StoreKit
purchase prompt.

For unsigned Debug Simulator builds, the app may fall back to `UserDefaults` for
the local bearer token. That fallback is compiled only for `DEBUG` Simulator
targets; production and device builds remain Keychain-only.

## Issue and PR checklist

When a feature depends on seeded local data, the issue or PR should record:

- the seed script name and command;
- the selected Simulator UDID;
- whether the account was empty or seeded;
- the reporting timezone used for the screenshot or walkthrough;
- the visible states checked, including light/dark mode and large Dynamic Type
  when layout is in scope.
