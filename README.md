# Cha-Ching

Native iOS client plus a Cloudflare Worker API for account identity, feature entitlements, and payment-provider connections.

Brand rules live in [`docs/brand.md`](docs/brand.md), App Store copy in [`docs/app-store/metadata.md`](docs/app-store/metadata.md), and launch progress in [GitHub Issue #1](https://github.com/serpcompany/cha-ching/issues/1).

## MVP architecture

- Better Auth runs in a Cloudflare Worker and stores users/sessions in D1.
- The iOS app signs in with Apple's native UI, exchanges the Apple ID token with Better Auth, and stores the resulting bearer session in Keychain.
- D1 entitlements (`connect_stripe`, `connect_paypal`) are created with MVP defaults and checked before OAuth begins and again at callback completion.
- Stripe uses Connect OAuth for Standard accounts. PayPal uses Log in with PayPal (OpenID Connect).
- Provider access and refresh tokens are AES-256-GCM encrypted before D1 storage. The encryption key stays in Worker secrets.

This milestone connects and identifies Stripe/PayPal accounts. Sale ingestion, provider webhooks, APNs delivery, and real revenue history are deliberately outside this MVP; production currently starts with an empty sale feed.

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

2. Add Apple, Stripe, and PayPal values to `.dev.vars`.

   - Apple: App ID `com.serpcompany.chaching`, Services ID `com.serpcompany.chaching.signin`, Team ID, Key ID, and the downloaded `.p8` private key.
   - Stripe: enable Connect OAuth and register `<PUBLIC_BASE_URL>/v1/oauth/stripe/callback` as a redirect URI.
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
pnpm exec wrangler secret put PROVIDER_TOKEN_ENCRYPTION_KEY
pnpm exec wrangler secret put STRIPE_CONNECT_CLIENT_ID
pnpm exec wrangler secret put STRIPE_SECRET_KEY
pnpm exec wrangler secret put PAYPAL_CLIENT_ID
pnpm exec wrangler secret put PAYPAL_CLIENT_SECRET
pnpm db:migrate:remote
pnpm deploy
```

Production infrastructure is deployed at `https://cha-ching-api.serpcompany.workers.dev` with D1 database `cha-ching-prod`. Public provider-review pages are available at `/privacy` and `/terms`. Change `PAYPAL_ENVIRONMENT` to `live` only after PayPal approves Log in with PayPal.

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
pnpm exec wrangler deploy --dry-run

cd ..
xcodegen generate
xcodebuild -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```
