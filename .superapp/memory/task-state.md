# Task state

Goal: Sales Ping — provider connections (Stripe, PayPal, Lemon Squeezy, Gumroad,
Dodo Payments, Whop, Polar) with secure backend + Sign in with Apple auth.

Done:
- Home dashboard, tab navigation, theme, sample data (prior phase).
- Supabase connected. Schema: `provider_connections`, `provider_secrets` (service-role
  only, no client policies by design), `sales`, `device_tokens`, all RLS-protected.
- Sign in with Apple: entitlement in project.yml, bundle id registered, Supabase Apple
  provider enabled. App now gates on auth: SignInView vs RootTabView.
- Edge functions `connect-provider` / `disconnect-provider` deployed (verify_jwt=true),
  store secrets server-side via service role, never exposed back to the client.
- Processor model expanded to all 7 providers with per-provider setup hints.
- New Connect tab: real provider list (`ConnectView`) + credential entry sheet
  (`ConnectSheet`) wired to `ConnectStore` → edge functions. Build succeeded, verified
  sign-in screen on simulator (Apple sign-in itself needs a real device to complete).

Next likely steps:
1. Build per-provider webhook receiver edge functions (stripe, paypal, lemonsqueezy,
   gumroad, dodo_payments, whop, polar): verify signature using stored `webhook_secret`/
   `api_key`, normalize payload into `sales` table insert.
2. APNs setup: push key/cert, register device tokens (table already exists), send push
   from webhook function on new sale → this is what actually delivers the "cha-ching".
3. History tab: real list backed by `sales` table (replace SalesStore dummy data).
4. Settings: ping sound picker + notification text template.
5. RevenueCat paywall for subscription.
