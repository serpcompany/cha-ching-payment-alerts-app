# Local StoreKit testing

Use the checked-in `Cha-Ching/StoreKit/ChaChing.storekit` catalog for fast
subscription development. The shared **Cha-Ching** scheme selects it for Debug
runs, so Xcode and Simulator purchases do not require an App Store Connect
upload, an Apple sandbox account, or TestFlight.

The catalog mirrors the launch offer:

- product ID `com.serpcompany.chaching.annual`;
- $14.99 annual renewal;
- one-week free introductory offer;
- no Family Sharing or Billing Grace Period.

The catalog is a Debug resource and is explicitly excluded from Release. A
Release build, archive, sandbox install, and TestFlight build continue to use
App Store Connect's product catalog.

## Feedback ladder

1. Run `SubscriptionStoreTests` for app orchestration and backend-authority
   rules without StoreKit state.
2. Run `LocalStoreKitIntegrationTests` for a real local StoreKit purchase and
   restore against the checked-in catalog. The standard scheme keeps the
   Worker boundary substituted for fast client coverage.
3. Run the dedicated **Cha-Ching Local StoreKit E2E** scheme with the loopback
   Worker running. It creates a real local session, purchases through StoreKit,
   submits the Xcode transaction over HTTP, persists Full access in local D1,
   and restores it through a fresh subscription store.
4. Use a development-signed build and Apple's sandbox when validating an
   Apple-signed JWS against the Worker and D1.
5. Upload to TestFlight only for milestone checks of the distribution-signed
   app, App Store Connect configuration, and end-to-end sandbox reconciliation.

Run all iOS tests on a dedicated Simulator owned by the current agent:

```bash
xcodegen generate
xcodebuild test -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -destination "platform=iOS Simulator,id=<owned-simulator-udid>" \
  CODE_SIGNING_ALLOWED=NO
```

Run the local end-to-end subscription check after starting `pnpm dev` in
`backend/`:

```bash
xcodebuild test -project "Cha-Ching.xcodeproj" \
  -scheme "Cha-Ching Local StoreKit E2E" \
  -destination "platform=iOS Simulator,id=<owned-simulator-udid>" \
  -only-testing:"Cha-ChingTests/LocalStoreKitIntegrationTests"
```

To exercise the UI manually, select the **Cha-Ching** scheme and an owned
Simulator, then Run. Xcode presents local StoreKit purchase sheets and keeps
transactions in that Simulator until they are cleared through Xcode's StoreKit
transaction manager or the Simulator is discarded.

## Authorization boundary

Local StoreKit proves client and loopback Worker behavior; it does not create production access.
`SubscriptionStore` still submits the signed transaction through
`SubscriptionAccessClient`, and only the backend response can change the app to
Full access. Xcode transaction data is decoded only by a loopback development
Worker receiving a loopback request. The remote Worker, staging, production,
and non-loopback requests reject it. The fast integration test replaces the
backend boundary; the dedicated E2E scheme does not.
