# Signed iPhone QA

Use a signed iPhone build for real Sign in with Apple and APNs registration. A
Simulator can exercise the UI and Worker APIs, but notification permission in a
Simulator does not prove that Apple issued a usable remote-notification token.

## Signing assets

The Apple bundle ID is `com.serpcompany.chaching`. Its capabilities must include
`APPLE_ID_AUTH` and `PUSH_NOTIFICATIONS`.

Two provisioning profiles are used:

- `Cha-Ching Development` for a registered QA iPhone. It contains a development
  APNs entitlement and is suitable for direct installation from Xcode.
- `Cha-Ching App Store Push` for archive/TestFlight builds. It contains the
  production APNs entitlement and `beta-reports-active`.

Inspect the remote configuration without relying on Xcode's cached login:

```bash
asc bundle-ids capabilities list --bundle "com.serpcompany.chaching" --output table
asc profiles list --paginate --output table
asc certificates list --paginate --output table
asc devices list --paginate --output table
```

If a registered device needs a new development profile, create and install one
with the current certificate and device IDs returned by those commands:

```bash
asc profiles create \
  --name "Cha-Ching Development" \
  --profile-type IOS_APP_DEVELOPMENT \
  --bundle "com.serpcompany.chaching" \
  --certificate "<development-certificate-id>" \
  --device "<registered-device-id>"

asc profiles download --id "<profile-id>" --output "/tmp/Cha-Ching.mobileprovision"
asc profiles inspect --path "/tmp/Cha-Ching.mobileprovision" --entitlements --output table
asc profiles local install --path "/tmp/Cha-Ching.mobileprovision"
```

Do not commit provisioning profiles, certificates, private keys, or App Store
Connect credentials.

## Direct production-API QA build

A direct development build uses Apple's sandbox APNs endpoint. Build it with the
production Worker URL so the real Stripe installation and signed-in account are
exercised without uploading another TestFlight build:

```bash
xcodebuild -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -configuration Debug -destination "generic/platform=iOS" \
  -derivedDataPath "$HOME/Library/Developer/XcodeBuildMCP/DerivedData/ChaChingPhysicalDebug" \
  CODE_SIGN_STYLE=Manual \
  "PROVISIONING_PROFILE_SPECIFIER=Cha-Ching Development" \
  DEVELOPMENT_TEAM=847HR8U8D9 \
  API_BASE_URL="https://cha-ching-api.serpcompany.workers.dev" \
  build
```

Keep the iPhone unlocked with Developer Mode enabled while installing. After
launching, sign in with Apple and allow notifications. The Settings screen must
say `Payment pings: On`; permission alone appears as `Waiting for device`.

Confirm production registration without exposing the token:

```sql
SELECT environment, status, last_seen_at
FROM device_tokens
WHERE user_id = '<better-auth-user-id>'
ORDER BY last_seen_at DESC;
```

For this direct build, `environment` must be `development`. TestFlight builds
register `production` tokens instead.

## Acceptance

1. The signed-in iPhone appears as an active D1 device.
2. A successful Stripe charge from the installed provider account reaches the
   production event destination.
3. D1 contains one idempotent sale and one delivery for that device.
4. APNs reports the delivery as sent, the phone shows the Cha-ching alert, and
   the same sale appears in History.

