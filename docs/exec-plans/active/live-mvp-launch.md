# Live MVP Launch

- Status: In progress
- Issue: https://github.com/serpcompany/make-that-money-mobile-app/issues/1
- Owner: repository maintainers

## Goal

Run the Sales Ping account-connection MVP against production Cloudflare infrastructure and verify Apple authentication plus Stripe and PayPal account linking end to end.

## Completed in repository

- Cloudflare Worker API and Better Auth integration.
- D1 schema for auth, entitlements, OAuth state, and encrypted provider connections.
- Native bearer session storage and provider-hosted OAuth browser flow.
- Supabase removal and SERP identifier migration.
- Worker tests, D1 migration validation, Wrangler dry run, and Simulator build.
- Agent harness, domain context, ADRs, and feature specifications.

## Launch checklist

- [x] Create production D1 database and bind its real ID.
- [x] Select a production Worker hostname and update Worker/iOS URLs.
- [x] Generate and upload Better Auth and provider-token encryption secrets.
- [x] Register `com.serpcompany.salesping` for Sign in with Apple.
- [ ] Register `com.serpcompany.salesping.signin` and Apple callback configuration.
- [ ] Upload Apple Team ID, Key ID, and private key as Worker secrets.
- [ ] Configure Stripe Connect and its production callback URL.
- [ ] Configure PayPal sandbox callback and complete sandbox linking verification.
- [ ] Submit/obtain PayPal live Log in approval before enabling live mode.
- [x] Publish privacy-policy and user-agreement URLs for provider review.
- [x] Apply D1 migrations remotely and deploy the Worker.
- [x] Verify `/health` on the live origin.
- [ ] Verify unauthorized API behavior after Apple configuration completes.
- [ ] Verify signed-device Apple login and session restore.
- [ ] Verify Stripe connect, refresh, disconnect, and callback replay rejection.
- [ ] Verify PayPal sandbox connect, refresh, and disconnect.
- [ ] Record production evidence and remaining limitations.

## Validation commands

```bash
cd backend
pnpm check
pnpm exec wrangler deploy --dry-run
pnpm db:migrate:remote
pnpm deploy

cd ..
xcodegen generate
xcodebuild -project "Sales Ping.xcodeproj" -scheme "Sales Ping" \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Known scope boundary

The launch proves identity, entitlements, and provider-account linking. Sale webhooks, normalized history, and APNs pings remain planned and must not be marketed as live behavior.

## Production resources

- Worker: `https://sales-ping-api.serpcompany.workers.dev`
- D1: `sales-ping-prod` (`0a4f0c3e-2248-4a72-936e-e28aa6e21a72`, APAC)
- Apple App ID: `com.serpcompany.salesping` (`8M2X78UD9K`)
- Privacy: `https://sales-ping-api.serpcompany.workers.dev/privacy`
- Terms: `https://sales-ping-api.serpcompany.workers.dev/terms`
