# ADR-0010: Timezone-aware payment reporting

- Status: Accepted
- Date: 2026-09-03

## Context

The Payments endpoint intentionally returns only the latest 100 normalized payments, so the iPhone cannot calculate authoritative historical totals. “Today” and calendar-to-date reports are also ambiguous without a durable timezone, and combining currencies would invent a monetary value.

## Decision

Store one user-owned IANA reporting timezone in D1. Initialize it atomically from the first authenticated full-access device and change it only through an explicit Settings action. Keep payment timestamps in UTC and apply the saved timezone to reporting boundaries.

Expose a product-gated dashboard endpoint that aggregates every matching succeeded sale. Each response fixes a maximum D1 `rowid`, reads that snapshot with `(occurred_at, id)` keyset pagination, and folds pages into bounded report aggregates. Concurrent backfills beyond the snapshot cutoff appear on the next refresh rather than shifting the active read. The response returns Today, approved current/previous windows, comparison states, zero-filled chart buckets, and product/source breakdowns. Payment counts may span currencies, but monetary totals and averages remain separated by currency. The 100-row Payments endpoint remains independent.

When an IANA zone advances its clock at local midnight, a calendar boundary resolves to the first valid instant on that requested civil date. It must not fall backward into the preceding date.

## Consequences

- Travel does not silently change report history.
- Existing users establish a preference on their next full-access launch.
- Home can report more than 100 payments without transferring complete history to the phone.
- Refunds are excluded until adjustment ingestion is complete; no net-revenue claim is made.
- Customer, subscription-lifecycle, balance, fee, and cross-currency metrics require future normalized data.
