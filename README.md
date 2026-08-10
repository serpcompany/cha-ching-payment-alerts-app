# Cha-Ching

[![CI](https://github.com/serpcompany/cha-ching/actions/workflows/ci.yml/badge.svg)](https://github.com/serpcompany/cha-ching/actions/workflows/ci.yml)

Native iOS client plus a Cloudflare Worker API for account identity, feature entitlements, payment-provider connections, verified Stripe sales, and APNs alerts.

Brand rules live in [`docs/brand.md`](docs/brand.md), App Store copy in [`docs/app-store/metadata.md`](docs/app-store/metadata.md), and launch progress in [GitHub Issue #1](https://github.com/serpcompany/cha-ching/issues/1).

## MVP architecture

- Better Auth runs in a Cloudflare Worker and stores users/sessions in D1.
- The iOS app signs in with Apple's native UI, exchanges the Apple ID token with Better Auth, and stores the resulting bearer session in Keychain.
- D1 entitlements (`connect_stripe`, `connect_paypal`) are created with MVP defaults and checked before OAuth begins and again at callback completion.
- Stripe uses Connect OAuth for Standard accounts. PayPal uses Log in with PayPal (OpenID Connect).
- Provider access and refresh tokens are AES-256-GCM encrypted before D1 storage. The encryption key stays in Worker secrets.
- Signed Stripe connected-account events become idempotent D1 sales and are sent through a Cloudflare Queue for APNs delivery.
- The iOS History tab reads verified sales from the Worker; sample revenue and local test pings are not part of production behavior.

PayPal account linking is implemented separately from sale ingestion. Version 1.0 supports Stripe payment alerts once the production Stripe platform and webhook secrets are configured; PayPal alerts are not implemented.

## Local setup

Requirements: Node 22+, pnpm 10+, Xcode 17+, XcodeGen, Wrangler, and a Cloudflare account.

1. Install and configure the Worker:

   ```bash
   cd backend
   pnpm install
   cp .dev.vars.example .dev.vars
   openssl rand -base64 32 # BETTER_AUTH_SECRET
   openssl rand -base64 32 # PROVIDER_TOKEN_ENCRYPTION_KEY
   ```

2. Add Apple, APNs, Stripe, and PayPal values to `.dev.vars`.

   - Apple: App ID `com.serpcompany.chaching`, Services ID `com.serpcompany.chaching.signin`, Team ID, Key ID, and the downloaded `.p8` private key.
   - APNs: use an Apple key with push access and the app topic `com.serpcompany.chaching`.
   - Stripe: enable Connect OAuth, register `<PUBLIC_BASE_URL>/v1/oauth/stripe/callback`, and create a connected-account webhook at `<PUBLIC_BASE_URL>/v1/webhooks/stripe` for `charge.succeeded` and `account.application.deauthorized`.
   - PayPal: enable Log in with PayPal and register `<PUBLIC_BASE_URL>/v1/oauth/paypal/callback` as the return URL. Sandbox requires no review; live access requires PayPal approval.

3. The checked-in production binding uses `cha-ching-prod`. For local development, apply the same migrations to local Wrangler state:

   ```bash
   pnpm db:migrate:local
   pnpm dev
   ```

4. Set `PUBLIC_BASE_URL` in `backend/wrangler.jsonc` and `API_BASE_URL` in `project.yml` to the same reachable API origin. The checked-in Debug value works for an iOS Simulator using a local Worker. A real device needs an HTTPS URL or tunnel.

5. Regenerate and build the app:

   ```bash
   cd ..
   xcodegen generate
   open "Cha-Ching.xcodeproj"
   ```

Sign in with Apple requires Apple configuration and is best exercised on a signed build/device.

## Deploy

Do not commit secrets. Verify Cloudflare authentication, create the production D1 database, update `wrangler.jsonc`, and set each secret:

```bash
cd backend
pnpm exec wrangler whoami
pnpm exec wrangler secret put BETTER_AUTH_SECRET
pnpm exec wrangler secret put APPLE_TEAM_ID
pnpm exec wrangler secret put APPLE_KEY_ID
pnpm exec wrangler secret put APPLE_PRIVATE_KEY
pnpm exec wrangler secret put APNS_KEY_ID
pnpm exec wrangler secret put APNS_PRIVATE_KEY
pnpm exec wrangler secret put PROVIDER_TOKEN_ENCRYPTION_KEY
pnpm exec wrangler secret put STRIPE_CONNECT_CLIENT_ID
pnpm exec wrangler secret put STRIPE_SECRET_KEY
pnpm exec wrangler secret put STRIPE_WEBHOOK_SECRET
pnpm exec wrangler secret put PAYPAL_CLIENT_ID
pnpm exec wrangler secret put PAYPAL_CLIENT_SECRET
pnpm exec wrangler queues create cha-ching-notifications
pnpm exec wrangler queues create cha-ching-notifications-dlq
pnpm db:migrate:remote
pnpm run deploy
```

Production infrastructure is deployed at `https://cha-ching-api.serpcompany.workers.dev` with D1 database `cha-ching-prod`, queue `cha-ching-notifications`, and dead-letter queue `cha-ching-notifications-dlq`. Public provider-review pages are available at `/privacy` and `/terms`. `/health` reports each externally configured capability without exposing secrets. Change `PAYPAL_ENVIRONMENT` to `live` only after PayPal approves Log in with PayPal.

## Entitlements

Both connection features default to enabled. D1 remains the source of truth and every connection attempt is enforced server-side. An operator can change access directly until billing/admin tooling exists:

```sql
UPDATE entitlements
SET enabled = 0, updated_at = CURRENT_TIMESTAMP
WHERE user_id = '<better-auth-user-id>' AND feature_key = 'connect_paypal';
```

## Verification

```bash
cd backend
pnpm check
pnpm exec wrangler types --check
pnpm exec wrangler deploy --dry-run

cd ..
xcodegen generate
xcodebuild -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The signed Stripe event → D1 sale → Queue path should also be exercised in local Wrangler before changing webhook behavior. Production notification acceptance requires a signed TestFlight device because Simulator APNs behavior does not prove the distribution token path.
