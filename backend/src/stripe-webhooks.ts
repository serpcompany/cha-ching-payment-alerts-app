import { timingSafeEqual } from "node:crypto";

import type { Env } from "./env";

const encoder = new TextEncoder();
const SIGNATURE_TOLERANCE_SECONDS = 5 * 60;
const MAX_WEBHOOK_BYTES = 512 * 1024;

interface StripeCharge {
  id: string;
  amount: number;
  currency: string;
  created: number;
  description?: string | null;
  invoice?: string | { id?: string } | null;
  billing_details?: { address?: { country?: string | null } | null } | null;
}

interface StripeEvent {
  id: string;
  type: string;
  account?: string;
  livemode: boolean;
  data: { object: unknown };
}

export interface NormalizedStripeSale {
  providerEventId: string;
  providerPaymentId: string;
  providerAccountId: string;
  amountMinor: number;
  currency: string;
  productLabel: string;
  countryCode: string | null;
  isSubscription: boolean;
  occurredAt: number;
  livemode: boolean;
}

function bytesToHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function fixedLengthEqual(left: string, right: string): Promise<boolean> {
  const [leftHash, rightHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  return timingSafeEqual(new Uint8Array(leftHash), new Uint8Array(rightHash));
}

export async function stripeSignature(
  payload: string,
  timestamp: number,
  secret: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return bytesToHex(await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}.${payload}`)));
}

export async function verifyStripeSignature(
  payload: string,
  header: string,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1_000),
): Promise<boolean> {
  const values = header.split(",").reduce<Record<string, string[]>>((result, part) => {
    const separator = part.indexOf("=");
    if (separator < 1) return result;
    const key = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    result[key] = [...(result[key] ?? []), value];
    return result;
  }, {});
  const timestamp = Number(values.t?.[0]);
  if (!Number.isSafeInteger(timestamp)) return false;
  if (Math.abs(nowSeconds - timestamp) > SIGNATURE_TOLERANCE_SECONDS) return false;
  const expected = await stripeSignature(payload, timestamp, secret);
  const matches = await Promise.all((values.v1 ?? []).map((value) => fixedLengthEqual(value, expected)));
  return matches.some(Boolean);
}

function isStripeEvent(value: unknown): value is StripeEvent {
  if (!value || typeof value !== "object") return false;
  const event = value as Record<string, unknown>;
  return (
    typeof event.id === "string" &&
    typeof event.type === "string" &&
    typeof event.livemode === "boolean" &&
    Boolean(event.data) &&
    typeof event.data === "object" &&
    "object" in (event.data as Record<string, unknown>)
  );
}

function isStripeCharge(value: unknown): value is StripeCharge {
  if (!value || typeof value !== "object") return false;
  const charge = value as Record<string, unknown>;
  return (
    typeof charge.id === "string" &&
    Number.isSafeInteger(charge.amount) &&
    Number(charge.amount) >= 0 &&
    typeof charge.currency === "string" &&
    Number.isSafeInteger(charge.created)
  );
}

export function normalizeStripeSale(event: StripeEvent): NormalizedStripeSale | null {
  if (event.type !== "charge.succeeded" || !event.account || !isStripeCharge(event.data.object)) {
    return null;
  }
  const charge = event.data.object;
  const country = charge.billing_details?.address?.country;
  return {
    providerEventId: event.id,
    providerPaymentId: charge.id,
    providerAccountId: event.account,
    amountMinor: charge.amount,
    currency: charge.currency.toUpperCase(),
    productLabel: "Stripe payment",
    countryCode: typeof country === "string" ? country.toUpperCase() : null,
    isSubscription: charge.invoice != null,
    occurredAt: charge.created,
    livemode: event.livemode,
  };
}

async function recordEvent(
  env: Env,
  event: StripeEvent,
  userId: string | null,
): Promise<void> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO provider_events (
      id, provider, provider_event_id, user_id, provider_account_id, event_type, livemode
    ) VALUES (?1, 'stripe', ?2, ?3, ?4, ?5, ?6)`,
  )
    .bind(
      `stripe:${event.id}`,
      event.id,
      userId,
      event.account ?? null,
      event.type,
      event.livemode ? 1 : 0,
    )
    .run();
}

async function ingestSale(env: Env, event: StripeEvent, sale: NormalizedStripeSale): Promise<void> {
  const connection = await env.DB.prepare(
    `SELECT user_id FROM provider_connections
     WHERE provider = 'stripe' AND provider_account_id = ?1 AND status = 'connected'`,
  )
    .bind(sale.providerAccountId)
    .first<{ user_id: string }>();

  await recordEvent(env, event, connection?.user_id ?? null);
  if (!connection) {
    console.log(JSON.stringify({ message: "stripe.event.ignored", eventId: event.id, reason: "unknown_account" }));
    return;
  }

  const saleId = `stripe:${sale.providerPaymentId}`;
  await env.DB.prepare(
    `INSERT OR IGNORE INTO sales (
      id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
      amount_minor, currency, product_label, country_code, is_subscription, occurred_at
    ) VALUES (?1, ?2, 'stripe', ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`,
  )
    .bind(
      saleId,
      connection.user_id,
      sale.providerAccountId,
      sale.providerEventId,
      sale.providerPaymentId,
      sale.amountMinor,
      sale.currency,
      sale.productLabel,
      sale.countryCode,
      sale.isSubscription ? 1 : 0,
      sale.occurredAt,
    )
    .run();

  const pending = await env.DB.prepare(
    "SELECT notification_queued_at FROM sales WHERE id = ?1",
  )
    .bind(saleId)
    .first<{ notification_queued_at: string | null }>();
  if (pending && !pending.notification_queued_at) {
    await env.NOTIFICATION_QUEUE.send({ saleId });
    await env.DB.prepare(
      "UPDATE sales SET notification_queued_at = CURRENT_TIMESTAMP WHERE id = ?1 AND notification_queued_at IS NULL",
    )
      .bind(saleId)
      .run();
  }
}

async function handleDeauthorization(env: Env, event: StripeEvent): Promise<void> {
  await recordEvent(env, event, null);
  if (!event.account) return;
  await env.DB.prepare(
    `UPDATE provider_connections SET status = 'revoked', updated_at = CURRENT_TIMESTAMP
     WHERE provider = 'stripe' AND provider_account_id = ?1`,
  )
    .bind(event.account)
    .run();
}

export async function handleStripeWebhook(env: Env, request: Request): Promise<Response> {
  if (!env.STRIPE_WEBHOOK_SECRET) {
    return Response.json({ error: "Stripe webhooks are unavailable" }, { status: 503 });
  }
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_WEBHOOK_BYTES) {
    return Response.json({ error: "Payload too large" }, { status: 413 });
  }
  const signatureHeader = request.headers.get("stripe-signature");
  if (!signatureHeader) return Response.json({ error: "Missing signature" }, { status: 400 });
  const rawBody = await request.text();
  if (encoder.encode(rawBody).byteLength > MAX_WEBHOOK_BYTES) {
    return Response.json({ error: "Payload too large" }, { status: 413 });
  }
  if (!(await verifyStripeSignature(rawBody, signatureHeader, env.STRIPE_WEBHOOK_SECRET))) {
    return Response.json({ error: "Invalid signature" }, { status: 400 });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  if (!isStripeEvent(parsed)) return Response.json({ error: "Invalid event" }, { status: 400 });

  if (parsed.type === "account.application.deauthorized") {
    await handleDeauthorization(env, parsed);
  } else {
    const sale = normalizeStripeSale(parsed);
    if (sale) await ingestSale(env, parsed, sale);
    else await recordEvent(env, parsed, null);
  }
  return Response.json({ received: true });
}
