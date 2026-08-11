# Cha-Ching

[![CI](https://github.com/serpcompany/cha-ching/actions/workflows/ci.yml/badge.svg)](https://github.com/serpcompany/cha-ching/actions/workflows/ci.yml)

Native iOS client plus a Cloudflare Worker API for account identity, feature entitlements, payment-provider connections, verified Stripe sales, sender-reported custom webhook sales, and APNs alerts.

Brand rules live in [`docs/brand.md`](docs/brand.md), App Store copy in [`docs/app-store/metadata.md`](docs/app-store/metadata.md), and launch progress in [GitHub Issue #1](https://github.com/serpcompany/cha-ching/issues/1).

## MVP architecture

- Better Auth runs in a Cloudflare Worker and stores users/sessions in D1.
- The iOS app signs in with Apple's native UI, exchanges the Apple ID token with Better Auth, and stores the resulting bearer session in Keychain.
- D1 entitlements (`connect_stripe`, `connect_paypal`, `connect_custom`) are created with MVP defaults and enforced server-side.
- Stripe uses a backend-only Stripe App with explicit `event_read` and `charge_read` permissions. PayPal uses Log in with PayPal (OpenID Connect).
- PayPal access and refresh tokens are AES-256-GCM encrypted before D1 storage. Stripe stores only the installed account ID and no Stripe access token.
- Signed Stripe connected-account events become idempotent D1 sales and are sent through a Cloudflare Queue for APNs delivery.
- Custom sources issue a stable private webhook URL, provide a copyable AI-agent/developer setup prompt, learn a user-selected mapping from one encrypted setup sample, and let the user search, filter, show, hide, rename, remap, or reorder every observed notification field before activation.
- Custom pushes use a fixed `Cha-ching!` title and one ordered `{label}: {value}` line per enabled field. “Observed” means present in the test sample; it does not claim to be every field the sender could theoretically provide.
- Custom notifications retain only the enabled, normalized label/value pairs with the sale; the complete live webhook payload is not stored.
- The iOS History tab reads Stripe-verified and custom sender-reported sales from the Worker; sample revenue and local test pings are not part of production behavior.

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

2. For everyday Debug Simulator work, those two local secrets are enough. Start
   the Worker and choose **Use local Simulator account** in the app. Apple
   credentials are deliberately not used by this path; see
   [`docs/development/simulator-auth.md`](docs/development/simulator-auth.md).
   Use [`docs/development/signed-iphone.md`](docs/development/signed-iphone.md)
   for real Sign in with Apple and APNs acceptance.

3. Add Apple, APNs, Stripe, and PayPal sandbox values to `.dev.vars` only when
   exercising those integrations locally.

   - Apple: App ID `com.serpcompany.chaching`, Services ID `com.serpcompany.chaching.signin`, Team ID, Key ID, and the downloaded `.p8` private key.
   - APNs: use an Apple key with push access and the app topic `com.serpcompany.chaching`.
   - Stripe: upload the checked-in `stripe-app.json`, allow `<PUBLIC_BASE_URL>/v1/oauth/stripe/callback`, request only `event_read` and `charge_read`, configure `STRIPE_SECRET_KEY` for the production live-account probe, and create an installed-account webhook at `<PUBLIC_BASE_URL>/v1/webhooks/stripe` for `charge.succeeded` and `account.application.deauthorized`.
   - PayPal: enable Log in with PayPal and register `<PUBLIC_BASE_URL>/v1/oauth/paypal/callback` as the return URL. Sandbox requires no review; live access requires PayPal approval.

4. The checked-in production binding uses `cha-ching-prod`. For local development, apply the same migrations to local Wrangler state:

   ```bash
   pnpm db:migrate:local
   pnpm dev
   ```

5. `pnpm dev` sets the local Worker origin to `http://127.0.0.1:8787`, which
   matches the checked-in Debug `API_BASE_URL`. A real device needs an HTTPS URL
   or tunnel and must use real Sign in with Apple.

6. Regenerate and build the app:

   ```bash
   cd ..
   xcodegen generate
   open "Cha-Ching.xcodeproj"
   ```

Real Sign in with Apple requires Apple configuration and is best exercised on a
signed build/device. Apple IDs and passwords must never be placed in environment
files.

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
pnpm exec wrangler secret put STRIPE_APP_INSTALL_URL
pnpm exec wrangler secret put STRIPE_APP_SIGNING_SECRET
pnpm exec wrangler secret put STRIPE_WEBHOOK_SECRET
pnpm exec wrangler secret put STRIPE_SECRET_KEY
pnpm exec wrangler secret put PAYPAL_CLIENT_ID
pnpm exec wrangler secret put PAYPAL_CLIENT_SECRET
pnpm exec wrangler queues create cha-ching-notifications
pnpm exec wrangler queues create cha-ching-notifications-dlq
pnpm db:migrate:remote
pnpm run deploy
```

Production infrastructure is deployed at `https://cha-ching-api.serpcompany.workers.dev` with D1 database `cha-ching-prod`, queue `cha-ching-notifications`, and dead-letter queue `cha-ching-notifications-dlq`. Public provider-review pages are available at `/privacy` and `/terms`. `/health` reports each externally configured capability without exposing secrets. Change `PAYPAL_ENVIRONMENT` to `live` only after PayPal approves Log in with PayPal.

## Entitlements

All three connection features default to enabled. D1 remains the source of truth and every connection attempt is enforced server-side. An operator can change access directly until billing/admin tooling exists:

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

The actual `$27.00` live Stripe Charge event from the installed SERP! payment account passed the production webhook → D1 sale → Queue → APNs path, and the tester confirmed the notification appeared on the signed iPhone. Replaying that exact event still produces one sale and one delivery. A regression test prevents production callbacks from storing a Stripe sandbox as the connected account.
