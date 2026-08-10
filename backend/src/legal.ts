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
      <p>Cha-Ching securely links supported Stripe and PayPal accounts. Stripe grants read-only event and charge permissions; provider tokens, when issued, stay encrypted in Cloudflare D1 and are never stored on the device.</p>
      <p>Cha-Ching can record successful Stripe charges and sender-reported payments from custom webhook sources, then send payment notifications to registered iPhones. PayPal payment notifications are not currently supported.</p>
    </div>
    <p><a href="/privacy">Privacy Policy</a> · <a href="/terms">User Agreement</a></p>
  `);
}

export function privacyPage(): Response {
  return page("Privacy Policy", `
    <p class="eyebrow">Effective August 11, 2026</p>
    <h1>Privacy Policy</h1>
    <p>Cha-Ching collects the minimum information needed to authenticate you and connect payment-provider accounts.</p>
    <h2>Information we process</h2>
    <ul>
      <li>Your Apple account identifier, name, and email when provided by Sign in with Apple.</li>
      <li>Your Stripe or PayPal account identifier, account label, granted permissions, and provider tokens when a provider issues them after you consent.</li>
      <li>For supported Stripe alerts: payment and event identifiers, amount, currency, event time, optional billing country, and delivery status. We do not retain the customer's name, email, payment description, or complete webhook payload.</li>
      <li>For a custom webhook source: its name, private webhook URL credential, field mapping, and an arbitrary JSON setup sample of up to 64 KiB supplied by the sender. The sample can contain personal information if the sender includes it. Custom payments are sender-reported, not independently verified with a payment provider.</li>
      <li>An APNs device token and app-generated device identifier when you enable notifications.</li>
      <li>Security and operational data such as session details, request rate limits, and error logs.</li>
    </ul>
    <h2>How we use and protect information</h2>
    <p>We use this information only to authenticate you, enforce feature access, display connection and sale history, deliver notifications, and operate the service. Cha-Ching's Stripe App has read-only access to event and charge data and cannot create, refund, or change payments. Provider tokens, private custom-webhook credentials, and custom setup samples are encrypted with AES-256-GCM before storage in Cloudflare D1. Active custom webhook payloads are normalized in memory; Cha-Ching retains the mapped sale fields rather than the complete payload. We do not sell personal information.</p>
    <h2>Sharing and retention</h2>
    <p>We use Apple, Stripe, PayPal, Cloudflare, and Apple Push Notification service to provide the service. A custom setup sample is replaced when a newer sample arrives and deleted after activation; if setup is not completed, the encrypted sample remains until the custom source or account is deleted. Disconnecting a provider removes its stored connection and encrypted tokens but does not erase existing sale history. Account, sale, and device data remain while your Cha-Ching account is active or until an authenticated deletion request is processed; minimal unmatched event records may remain for webhook security and deduplication.</p>
    <h2>Your choices</h2>
    <p>You can revoke provider access from Cha-Ching or the provider dashboard. Keep each custom webhook URL private because possession of the URL permits a sender to submit data; regenerate it immediately if it is exposed. To request access, correction, or deletion of your Cha-Ching account data, email <a href="mailto:devin@serp.co">devin@serp.co</a>.</p>
    <p><a href="/">Cha-Ching</a> · <a href="/terms">User Agreement</a></p>
  `);
}

export function termsPage(): Response {
  return page("User Agreement", `
    <p class="eyebrow">Effective August 11, 2026</p>
    <h1>User Agreement</h1>
    <p>By using Cha-Ching, you agree to use the service only with accounts you own or are authorized to manage.</p>
    <h2>Service scope</h2>
    <p>The service connects and identifies supported Stripe and PayPal accounts. For supported Stripe configurations it can display successful charges and attempt payment notifications. Custom webhook sources accept sender-supplied payment data, which Cha-Ching does not independently verify with a payment provider. The service is not an accounting, payout, reconciliation, tax, or financial-advice service, and PayPal payment notifications are not currently supported.</p>
    <h2>Provider terms</h2>
    <p>Your use of Apple, Stripe, and PayPal remains subject to each provider's agreements. You authorize Cha-Ching to receive the account information and permissions shown on each provider's consent page.</p>
    <h2>Custom webhook responsibility</h2>
    <p>A custom webhook URL is a private bearer credential: anyone who has it can submit data to that source. You are responsible for keeping it secret, regenerating it if exposed, connecting only systems you own or are authorized to manage, and ensuring the sender has the right to transmit its JSON data. Send only the fields needed for your notification and avoid unnecessary personal information.</p>
    <h2>Availability and responsibility</h2>
    <p>The MVP is provided as available and may change or be interrupted. You are responsible for reviewing provider activity and revoking access you no longer want. Nothing in Cha-Ching changes your obligations to a payment provider or your customers.</p>
    <h2>Contact</h2>
    <p>Questions about these terms can be sent to <a href="mailto:devin@serp.co">devin@serp.co</a>.</p>
    <p><a href="/">Cha-Ching</a> · <a href="/privacy">Privacy Policy</a></p>
  `);
}
