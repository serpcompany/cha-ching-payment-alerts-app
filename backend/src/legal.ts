const styles = `
  :root { color-scheme: light dark; font-family: ui-sans-serif, system-ui, sans-serif; }
  body { margin: 0; background: #071522; color: #f2fff8; }
  main { max-width: 760px; margin: 0 auto; padding: 64px 24px 96px; }
  h1 { font-size: clamp(2.25rem, 7vw, 4.5rem); line-height: 1; margin: 0 0 24px; }
  h2 { margin-top: 40px; }
  p, li { color: #c7d5e8; line-height: 1.7; }
  a { color: #39e6a3; }
  .eyebrow { color: #f5b942; font-weight: 800; letter-spacing: .12em; text-transform: uppercase; }
  .card { border: 1px solid #244737; border-radius: 22px; padding: 24px; background: #0d1d2a; }
`;

function page(title: string, body: string): Response {
  return new Response(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} — Cha-Ching</title><style>${styles}</style></head><body><main>${body}</main></body></html>`, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=3600",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
    },
  });
}

export function homePage(): Response {
  return page("Connect your revenue accounts", `
    <p class="eyebrow">Cha-Ching</p>
    <h1>Get paid. Hear the cha-ching.</h1>
    <div class="card">
      <p>Cha-Ching securely links Stripe through provider-hosted, read-only authorization and lets you create private custom webhook sources. Provider tokens stay encrypted in Cloudflare D1 and are never stored on the device.</p>
      <p>Cha-Ching records verified successful Stripe charges and sender-reported custom webhook payments, then sends payment notifications to registered iPhones.</p>
    </div>
    <p><a href="/support">Support</a> · <a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Use</a></p>
  `);
}

export function supportPage(): Response {
  return page("Support", `
    <p class="eyebrow">Cha-Ching</p>
    <h1>Support</h1>
    <div class="card">
      <p>For help with sign-in, subscriptions, Stripe connections, custom webhooks, payments, notifications, or account deletion, email <a href="mailto:devin@serp.co">devin@serp.co</a>.</p>
      <p>Include a short description of what happened and the approximate time. Never send payment-provider credentials, Apple passwords, private webhook URLs, or full webhook payloads.</p>
    </div>
    <p><a href="/">Cha-Ching</a> · <a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Use</a></p>
  `);
}

export function privacyPage(): Response {
  return page("Privacy Policy", `
    <p class="eyebrow">Effective August 12, 2026</p>
    <h1>Privacy Policy</h1>
    <p>Cha-Ching collects the minimum information needed to authenticate you, provide subscription access, connect payment sources, show payments, and deliver notifications.</p>
    <h2>Information we process</h2>
    <ul>
      <li>Your Apple account identifier, name, and email when provided by Sign in with Apple.</li>
      <li>Your Stripe account identifier, account label, granted permissions, and provider token after you consent.</li>
      <li>Your Apple subscription identifiers and verified entitlement dates. Cha-Ching does not receive your App Store payment-card details.</li>
      <li>For supported Stripe alerts: payment and event identifiers, amount, currency, event time, optional billing country, and delivery status. We do not retain the customer's name, email, payment description, or complete webhook payload.</li>
      <li>For a custom webhook source: its name, private webhook URL credential, field and notification-display mapping, and an arbitrary JSON setup sample of up to 64 KiB supplied by the sender. The sample can contain personal information if the sender includes it. For each active custom payment, we retain the enabled notification display labels and normalized values selected by the user. Custom payments are sender-reported, not independently verified with a payment provider.</li>
      <li>An APNs device token and app-generated device identifier when you enable notifications.</li>
      <li>Security and operational data such as session details, request rate limits, and error logs.</li>
    </ul>
    <h2>How we use and protect information</h2>
    <p>We use this information only to authenticate you, verify subscription access, display connection and payment history, deliver notifications, provide support, prevent abuse, and operate the service. Cha-Ching's Stripe App has read-only access to event and charge data and cannot create, refund, or change payments. Provider tokens, private custom-webhook credentials, custom setup samples, and the temporary Sign in with Apple revocation credential are encrypted with AES-256-GCM before storage in Cloudflare D1. Active custom webhook payloads are normalized in memory; Cha-Ching retains the mapped payment fields and enabled notification label/value pairs rather than the complete payload. Enabled values are sent to Apple Push Notification service and may be visible on the device lock screen. We do not sell personal information or use it for third-party advertising.</p>
    <h2>Sharing and retention</h2>
    <p>We use Apple, Stripe, Cloudflare, and Apple Push Notification service to provide the service. A custom setup sample is replaced when a newer sample arrives and deleted after activation; if setup is not completed, the encrypted sample remains until the custom source or account is deleted. Disconnecting Stripe removes its stored connection and encrypted token but does not erase existing payment history. Account, payment, source, connection, subscription-entitlement, session, and device data remain while your Cha-Ching account is active. Authenticated in-app account deletion removes those records immediately. Unmatched provider-event security records that were never linked to a user may remain for webhook deduplication.</p>
    <h2>Your choices</h2>
    <p>You can revoke Stripe access from Cha-Ching or Stripe, pause payment sources, disable payment notifications, and regenerate an exposed custom webhook URL. Delete your account from Settings in the app; deletion also revokes Cha-Ching's Sign in with Apple authorization when Apple provides the required credential. Deleting your Cha-Ching account does not cancel an Apple subscription, so use Apple's Manage Subscription action separately. For access or correction requests, email <a href="mailto:devin@serp.co">devin@serp.co</a>.</p>
    <p><a href="/">Cha-Ching</a> · <a href="/support">Support</a> · <a href="/terms">Terms of Use</a></p>
  `);
}

export function termsPage(): Response {
  return page("Terms of Use", `
    <p class="eyebrow">Effective August 12, 2026</p>
    <h1>Terms of Use</h1>
    <p>By using Cha-Ching, you agree to use the service only with accounts you own or are authorized to manage.</p>
    <h2>Service scope</h2>
    <p>The service connects and identifies a supported Stripe account and accepts sender-supplied payment data through private custom webhook sources. It can display successful payments and attempt payment notifications. Cha-Ching does not independently verify custom webhook data with a payment provider. The service is not an accounting, payout, reconciliation, tax, or financial-advice service.</p>
    <h2>Provider terms</h2>
    <p>Your use of Apple and Stripe remains subject to each provider's agreements. You authorize Cha-Ching to receive the account information and permissions shown on each provider's consent page.</p>
    <h2>Subscription and deletion</h2>
    <p>Full access is sold as an auto-renewing subscription through Apple. Apple controls billing, renewal, cancellation, and refunds. Deleting your Cha-Ching account does not cancel your Apple subscription; manage it separately through Apple before deletion if you do not want it to renew. Account deletion permanently removes your Cha-Ching account and its retained product data and cannot be undone.</p>
    <h2>Custom webhook responsibility</h2>
    <p>A custom webhook URL is a private bearer credential: anyone who has it can submit data to that source. You are responsible for keeping it secret, regenerating it if exposed, connecting only systems you own or are authorized to manage, and ensuring the sender has the right to transmit its JSON data. Review and disable private fields before activation: enabled notification values are retained with the sale, sent through Apple Push Notification service, and may appear on the device lock screen.</p>
    <h2>Availability and responsibility</h2>
    <p>The MVP is provided as available and may change or be interrupted. You are responsible for reviewing provider activity and revoking access you no longer want. Nothing in Cha-Ching changes your obligations to a payment provider or your customers.</p>
    <h2>Contact</h2>
    <p>Questions about these terms can be sent to <a href="mailto:devin@serp.co">devin@serp.co</a>.</p>
    <p><a href="/">Cha-Ching</a> · <a href="/support">Support</a> · <a href="/privacy">Privacy Policy</a></p>
  `);
}
