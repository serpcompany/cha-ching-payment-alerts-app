# Local Simulator authentication

Use this loop for ordinary UI, entitlement, and API development. It avoids Apple
credentials while preserving the real production authentication boundary.

## Dedicated Simulator ownership

Every agent must use a dedicated Simulator and retain its exact UDID for the
entire debugging session. Treat every Simulator that was already booted when the
session began as owned by somebody else.

1. List devices with `xcrun simctl list devices available`.
2. Select a shut-down device, record its UDID, and boot only that device. If no
   suitable shut-down device exists, create a new Simulator instead of taking
   over a running one.
3. Pass the recorded UDID explicitly to every `simctl`, build destination,
   install, launch, log, screenshot, and mirroring command. Do not use `booted`
   as a selector when multiple sessions may be active.
4. Never install onto, launch, control, erase, reset, shut down, or delete a
   Simulator that this session did not boot or create. Never use an unscoped
   command that affects all Simulators.
5. At handoff, report the owned device name and UDID. Shut it down only when the
   current session no longer needs its state; do not clean up any other device.

Simulator ownership prevents one agent from changing another agent's Keychain,
app data, login state, StoreKit test state, logs, or currently displayed UI.

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

The shared Debug scheme also selects the local StoreKit catalog. Follow
[`storekit-testing.md`](storekit-testing.md) to test subscription purchase and
restore without a TestFlight upload.

The native API client uses Better Auth's bearer token and deliberately does not
persist auth cookies. This prevents an old local Worker cookie from blocking a
fresh Simulator session after local state changes.

## What this does and does not test

| Check | Local account | Real device/TestFlight |
| --- | --- | --- |
| Signed-in UI and session restoration | Yes | Yes |
| Better Auth bearer sessions in D1 | Yes, local D1 | Yes, production D1 |
| Entitlement and user-scoped API behavior | Yes | Yes |
| Local StoreKit purchase and restore UI | Yes | No; uses Apple's sandbox catalog instead |
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
