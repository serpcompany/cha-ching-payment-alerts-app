# Local Simulator authentication

Use this loop for ordinary UI, entitlement, and API development. It avoids Apple
credentials while preserving the real production authentication boundary.

## One-time setup

From `backend/`:

```bash
pnpm install
cp .dev.vars.example .dev.vars
openssl rand -base64 32
openssl rand -base64 32
```

Put the first generated value in `BETTER_AUTH_SECRET`. Put the second in
`PROVIDER_TOKEN_ENCRYPTION_KEY`. `.dev.vars` is ignored by git. Do not add an
Apple ID, Apple password, production bearer token, or production provider key.

Apply migrations and start the loopback Worker:

```bash
pnpm db:migrate:local
pnpm dev
```

`pnpm dev` explicitly overrides the checked-in production values with
`ENVIRONMENT=development` and `PUBLIC_BASE_URL=http://127.0.0.1:8787`. Wrangler
persists the local D1 database under `.wrangler/state`; it does not touch remote
D1 unless a command includes `--remote`.

In another terminal:

```bash
xcodegen generate
xcodebuild -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Launch the Debug app on a Simulator and choose **Use local Simulator account**.
The session persists in that Simulator's Keychain. Sign in again only after
signing out, erasing that Simulator, clearing its app data, or deleting the local
Wrangler state that contains the matching session.

The native API client uses Better Auth's bearer token and deliberately does not
persist auth cookies. This prevents an old local Worker cookie from blocking a
fresh Simulator session after local state changes.

## What this does and does not test

| Check | Local account | Real device/TestFlight |
| --- | --- | --- |
| Signed-in UI and session restoration | Yes | Yes |
| Better Auth bearer sessions in D1 | Yes, local D1 | Yes, production D1 |
| Entitlement and user-scoped API behavior | Yes | Yes |
| Apple's authorization UI and identity-token validation | No | Yes |
| Production APNs delivery | No | Yes |

Provider OAuth requires provider-specific sandbox credentials and callback URLs.
Keep those in `.dev.vars` and use provider sandbox accounts. Never point the
Debug Simulator at the production Worker merely to use the local auth shortcut:
the remote Worker does not register that endpoint.

## Safety checks

Before merging authentication changes:

```bash
cd backend
pnpm check
pnpm exec wrangler deploy --dry-run

cd ..
xcodegen generate
xcodebuild -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -sdk iphonesimulator -configuration Release CODE_SIGNING_ALLOWED=NO build
```

The backend tests must prove that the shortcut is false for staging,
production, and any remotely reachable `PUBLIC_BASE_URL`. A Release build must
not contain the Simulator sign-in action or its client method.
