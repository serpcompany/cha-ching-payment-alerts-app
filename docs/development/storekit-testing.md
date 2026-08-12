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
   restore against the checked-in catalog.
3. Use a development-signed build and Apple's sandbox when validating an
   Apple-signed JWS against the Worker and D1.
4. Upload to TestFlight only for milestone checks of the distribution-signed
   app, App Store Connect configuration, and end-to-end sandbox reconciliation.

Run all iOS tests on a dedicated Simulator owned by the current agent:

```bash
xcodegen generate
xcodebuild test -project "Cha-Ching.xcodeproj" -scheme "Cha-Ching" \
  -destination "platform=iOS Simulator,id=<owned-simulator-udid>" \
  CODE_SIGNING_ALLOWED=NO
```

To exercise the UI manually, select the **Cha-Ching** scheme and an owned
Simulator, then Run. Xcode presents local StoreKit purchase sheets and keeps
transactions in that Simulator until they are cleared through Xcode's StoreKit
transaction manager or the Simulator is discarded.

## Authorization boundary

Local StoreKit proves client behavior; it does not create production access.
`SubscriptionStore` still submits the signed transaction through
`SubscriptionAccessClient`, and only the backend response can change the app to
Full access. Xcode-signed transaction data is not accepted by the remote Worker.
The automated integration test replaces only the backend boundary so it can
assert that purchase and restore both attempt reconciliation.
