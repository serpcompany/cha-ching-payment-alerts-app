# Entitlements

## User outcome

Cha-Ching can grant or withhold provider features per user without requiring an app release.

## MVP model

- `connect_stripe`
- `connect_paypal`

Both are enabled by default when first materialized for an MVP user. D1 is the source of truth. The iOS Settings UI reports state but cannot mutate it.

## Acceptance criteria

- Missing default rows are created idempotently.
- Each user has at most one row per feature.
- Authorization fails server-side when the relevant row is disabled.
- Unknown feature keys cannot be inserted through application APIs.

Billing-derived grants, plan catalogs, and an operator UI are future work.
