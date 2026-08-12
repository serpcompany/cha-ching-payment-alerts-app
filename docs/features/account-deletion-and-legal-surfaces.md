# Account deletion and legal surfaces

## User outcome

Every signed-in user can permanently delete a Cha-Ching account from the app, even when subscription access has expired. The app clearly separates account deletion from Apple subscription cancellation and keeps support, privacy, and terms reachable.

## Behavior

- Settings and the Subscription required screen both expose account deletion.
- The deletion sheet enumerates the data removed, warns that deletion does not cancel Apple billing, and links to Apple's Manage Subscription surface before confirmation.
- Confirmation requires a fresh Sign in with Apple authorization. iOS sends its one-time authorization code through the authenticated API.
- The Worker exchanges the code with Apple, verifies that the returned Apple subject matches the linked Better Auth account, encrypts the refresh token at rest, and calls Apple's token-revocation endpoint.
- Apple credential exchange or revocation failure leaves the account and product data intact for retry.
- After successful revocation, deleting the D1 user cascades through sessions, linked accounts, product and feature entitlements, provider connections, OAuth states, custom sources and encrypted setup samples, payments, APNs devices, and notification deliveries. User-linked provider-event audit rows are explicitly removed.
- The app deletes its bearer token, clears in-memory payments/connections/notification details, unregisters from remote notifications, clears the icon badge, and returns to Sign in with Apple.
- The Worker serves dedicated `/support`, `/privacy`, and `/terms` pages, and the app uses those same canonical surfaces.

## Automated evidence

- `backend/test/account-deletion.integration.test.ts` proves successful Apple revocation plus removal of every user-linked table, refusal to delete when revocation fails, and rejection of an authorization code for a different Apple subject.
- `pnpm check` covers the complete Worker suite and type checking.
- `pnpm exec wrangler deploy --dry-run` validates the Worker bundle and migration-aware code path.
- Unsigned Debug and Release Simulator builds prove the fresh-authorization deletion UI compiles in both development and App Store configurations.

## Production promotion

- Merge commit `e2859ca` promoted the implementation to `main` after the backend and unsigned iOS CI jobs passed.
- Remote D1 migration `0014_apple_account_deletion_credentials.sql` is applied to `cha-ching-prod`.
- Production Worker version `73e1c69d-9875-40a4-9811-be7d0bc1f83c` serves the deletion API and the canonical `/support`, `/privacy`, and `/terms` pages; each legal page returned HTTP 200 after deployment.
- App Store Connect build `28` (`939edae1-3975-42df-b5d8-1665c5a7d7bc`) is valid and available to the internal TestFlight group with focused account-deletion test instructions.
- App Store Connect privacy, support, and description URLs match the Cha-Ching-specific Worker pages.

## Launch verification boundary

Cha-Ching v1 does not require a destructive signed-device account-deletion exercise before App Review. The only available production account owns the working custom webhook, and deleting that account would permanently invalidate its stable webhook URL. No successful physical-device deletion or Apple credential revocation is claimed.

The launch accepts the automated integration evidence, completed production migration and deployment, valid internal TestFlight build, and App Review's ability to exercise deletion with its own account. Any later end-to-end deletion test must use a separate Apple Account that owns no production connection or custom webhook.
