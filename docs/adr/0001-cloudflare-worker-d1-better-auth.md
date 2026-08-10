# ADR-0001: Cloudflare Worker, D1, and Better Auth

- Status: Accepted
- Date: 2026-08-11

## Context

Sales Ping needs globally reachable native-app authentication, relational ownership data, feature entitlements, and provider OAuth callbacks. The previous Supabase integration split these concerns across a hosted client SDK and edge functions and encouraged direct client table access.

## Decision

Use one Cloudflare Worker as the API boundary, D1 as the relational source of truth, and Better Auth for Apple identity and sessions. Native clients use Better Auth bearer sessions stored in Keychain. Application tables use prepared D1 statements and tracked Wrangler migrations.

## Consequences

- All authorization decisions are server-side.
- Deployment requires Worker secrets, a D1 binding, and a stable HTTPS origin.
- D1 migration compatibility must be verified locally and remotely.
- The iOS app no longer depends on Supabase.
