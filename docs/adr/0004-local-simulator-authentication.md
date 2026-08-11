# ADR-0004: Local Simulator authentication

- Status: Accepted
- Date: 2026-08-11

## Context

Sign in with Apple is a production identity boundary, but Apple does not provide
a local identity-token emulator. Requiring an Apple Account for every Simulator
or fresh local database slows UI and provider-integration development. Storing
Apple credentials or a production bearer session in local configuration would
create a serious credential and authorization risk.

## Decision

Use Better Auth's anonymous plugin as a local development identity. Register it
only when both conditions are true:

1. `ENVIRONMENT` is exactly `development`.
2. `PUBLIC_BASE_URL` has a loopback hostname.

The Worker additionally requires the incoming request URL to use a loopback
hostname. This prevents a tunnel or a misconfigured remote deployment from
making the endpoint reachable.

Expose the matching iOS action only in a `DEBUG` build targeting the iOS
Simulator. Store its bearer token through the existing Keychain path. Run it
against Wrangler's persistent local D1 state, which is separate from the remote
production database.

Do not model this identity as Apple and do not synthesize Apple tokens. Staging,
TestFlight, and Release builds continue to use Apple's real authorization
service. Remote preview deployments also keep the shortcut disabled; they test
real identity unless a future ADR defines a separately authenticated QA system.

## Consequences

- Everyday Simulator work requires no Apple ID or Apple secret.
- Local provider connections and entitlements belong to disposable local users.
- The user table includes Better Auth's `is_anonymous` field, even though the
  plugin is not registered in production.
- Real Apple credential validation still requires a signed device/TestFlight
  acceptance test.
- Resetting `backend/.wrangler/state` or erasing the Simulator discards local
  identity state and requires creating a new local session.
