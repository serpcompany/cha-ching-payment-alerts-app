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

## Signed-device acceptance

Use the next TestFlight candidate and a disposable Apple sandbox tester/account:

1. Start or restore the annual sandbox subscription, connect a disposable Stripe test account or custom source, register notifications, and create one payment.
2. Open Delete Account from Settings and verify the data-removal and billing warning, Manage Subscription link, Support, Privacy Policy, and Terms of Use.
3. Cancel the Apple sheet once and confirm no data changes. Retry, authenticate with the linked Apple Account, and complete deletion.
4. Confirm the app returns to sign-in and no prior payment, connection, source, notification detail, or bearer session reappears after relaunch.
5. Confirm D1 has no rows for the user in `user`, `session`, `account`, `entitlements`, `product_entitlements`, `provider_connections`, `oauth_states`, `provider_events`, `custom_payment_sources`, `sales`, `device_tokens`, `notification_deliveries`, or `apple_account_credentials`.
6. Confirm Apple subscription management still shows the sandbox subscription independently, then verify that signing in again creates a new empty Cha-Ching account and presents Apple's initial authorization choices after revocation.

Repository implementation is not public-launch evidence by itself. Production migration/deployment and the signed-device sequence above are required before App Review submission.
