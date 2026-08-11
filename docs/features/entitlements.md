# Entitlements

## User outcome

Cha-Ching can grant or withhold provider features per user without requiring an app release.

## MVP model

- `connect_stripe`
- `connect_paypal`
- `connect_custom`

All three are enabled by default when first materialized for an MVP user. D1 is the source of truth. Entitlements are internal access control, not a user-facing subscription plan, so Settings does not display a **Plan access** section.

## Acceptance criteria

- Missing default rows are created idempotently.
- Each user has at most one row per feature.
- Authorization fails server-side when the relevant row is disabled.
- Creating a custom payment source requires an enabled `connect_custom` entitlement.
- Unknown feature keys cannot be inserted through application APIs.
- Removing the Settings presentation does not weaken server-side authorization or feature-availability behavior.

Billing-derived grants, plan catalogs, and an operator UI are future work.
