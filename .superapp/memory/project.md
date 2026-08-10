# Sales Ping

iPhone-only (iOS 17+) app for indie founders/SaaS makers: connect payment processors
(Stripe, PayPal, Gumroad first) and get a "cha-ching" push notification on every sale.
Planned monetization: subscription ($x/mo or /yr), prices to be tested later.

## Structure
- `Sales Ping/App/SalesPingApp.swift` — entry point, injects `SalesStore`.
- `Sales Ping/Design/Theme.swift` — money-green + gold adaptive palette, `cardStyle()`.
- `Sales Ping/Models/Sale.swift` — `Sale`, `Processor`, `ProcessorConnection`.
- `Sales Ping/Models/SalesStore.swift` — in-memory sample data + derived stats.
- `Sales Ping/Views/RootTabView.swift` — 4 tabs (Today, History, Connect, Settings);
  History/Connect/Settings are `PlaceholderView` stubs.
- `Sales Ping/Views/Home/` — HomeView, HomeComponents (hero, stat tiles, Swift Charts
  weekly bar chart, connections strip, empty state), SaleRow + SaleDetailView.

## Notes
- Sale/chart data is still local/dummy (SalesStore); real sales ingestion is next phase.
- Launch screen (storyboard) matches home theme: green wordmark + gold tagline.

## Backend (Supabase) — provider connections
- Auth: Sign in with Apple only (gate in `SalesPingApp`: SignInView vs RootTabView based on
  `AuthManager.isSignedIn`). Entitlement added via project.yml; bundle id registered with
  `configure_sign_in_with_apple`; Supabase Apple provider enabled.
- Tables: `provider_connections` (status per user+provider, RLS: owner only),
  `provider_secrets` (api_key/webhook_secret, RLS enabled with NO policies — only the
  service role inside edge functions can read/write; this is intentional, not a bug),
  `sales` (normalized feed, owner-select RLS), `device_tokens` (for future APNs, owner RLS).
- Edge functions: `connect-provider` (auth verifies caller, upserts connection + secret via
  service role) and `disconnect-provider`. Both deployed with verify_jwt=true.
- Processor enum (`Sale.swift`) now covers 7 providers: stripe, paypal, lemonsqueezy,
  gumroad, dodoPayments(dodo_payments), whop, polar — each with color/symbol/setupHint/
  needsWebhookSecret. All use an API-key + optional webhook-secret paste-in flow (no OAuth
  app registered with any provider yet, so no "Connect with X" OAuth buttons).
- App-side: `Services/SupabaseManager.swift` (client), `Services/AuthManager.swift` (Apple
  sign-in w/ nonce), `Services/ConnectStore.swift` (fetch connection state, call edge fns),
  `Views/Auth/SignInView.swift`, `Views/Connect/ConnectView.swift` + `ConnectSheet.swift`
  (replaces the old Connect tab placeholder).
- NOT built yet: actual webhook receiver endpoints per provider (signature verification +
  normalize-to-`sales` + push), and APNs push sending. That's the next phase.
