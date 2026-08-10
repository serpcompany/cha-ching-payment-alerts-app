import { importPKCS8, SignJWT } from "jose";

import type { Env } from "./env";
import type { SaleSource } from "./env";

export interface NotificationMessage {
  saleId: string;
}

interface NotificationSale {
  amount_minor: number;
  currency: string;
  provider: SaleSource;
  product_label: string;
  plan_label: string | null;
  sale_type_label: string | null;
}

interface SaleNotificationRow extends NotificationSale {
  id: string;
  user_id: string;
}

interface DeviceRow {
  id: string;
  token: string;
  environment: "development" | "production";
}

interface DeliveryStatusRow {
  id: string;
  status: "pending" | "sending" | "retry" | "sent" | "failed";
}

export function shouldRetryUnclaimedDelivery(status: DeliveryStatusRow["status"] | undefined): boolean {
  return status === "sending";
}

const ZERO_DECIMAL_CURRENCIES = new Set([
  "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF",
]);
const THREE_DECIMAL_CURRENCIES = new Set(["BHD", "JOD", "KWD", "OMR", "TND"]);

export function currencyExponent(currency: string): number {
  const normalized = currency.toUpperCase();
  if (ZERO_DECIMAL_CURRENCIES.has(normalized)) return 0;
  if (THREE_DECIMAL_CURRENCIES.has(normalized)) return 3;
  return 2;
}

export function formatMinorAmount(amountMinor: number, currency: string): string {
  const normalized = currency.toUpperCase();
  const amount = amountMinor / 10 ** currencyExponent(normalized);
  return new Intl.NumberFormat("en-US", { style: "currency", currency: normalized }).format(amount);
}

export function notificationBody(sale: NotificationSale): string {
  const amount = formatMinorAmount(sale.amount_minor, sale.currency);
  if (sale.provider !== "custom") {
    return `You received ${amount} through ${sale.provider === "stripe" ? "Stripe" : "PayPal"}.`;
  }
  const details = [sale.plan_label, sale.sale_type_label].filter(Boolean).join(" · ");
  return `You received ${amount} for ${sale.product_label}.${details ? ` ${details}` : ""}`;
}

async function apnsProviderToken(env: Env): Promise<string> {
  const key = await importPKCS8(env.APNS_PRIVATE_KEY.replace(/\\n/g, "\n"), "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env.APNS_KEY_ID })
    .setIssuer(env.APPLE_TEAM_ID)
    .setIssuedAt(Math.floor(Date.now() / 1_000))
    .sign(key);
}

function retryable(status: number, reason: string | null): boolean {
  return status === 429 || status >= 500 || reason === "TooManyRequests";
}

function invalidToken(status: number, reason: string | null): boolean {
  return (
    status === 410 ||
    reason === "BadDeviceToken" ||
    reason === "DeviceTokenNotForTopic" ||
    reason === "Unregistered"
  );
}

async function sendToDevice(
  env: Env,
  providerToken: string,
  sale: SaleNotificationRow,
  device: DeviceRow,
  deliveryId: string,
): Promise<"sent" | "invalid" | "retry" | "failed"> {
  const host = device.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${providerToken}`,
      "apns-topic": env.APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-id": deliveryId,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: {
          title: "Cha-ching!",
          body: notificationBody(sale),
        },
        sound: "default",
        badge: 1,
      },
      saleId: sale.id,
    }),
  });
  if (response.ok) return "sent";
  const payload = (await response.json().catch(() => null)) as { reason?: string } | null;
  const reason = payload?.reason ?? null;
  if (invalidToken(response.status, reason)) return "invalid";
  if (retryable(response.status, reason)) return "retry";
  return "failed";
}

async function deliverSale(env: Env, message: NotificationMessage): Promise<boolean> {
  const sale = await env.DB.prepare(
    `SELECT id, user_id, amount_minor, currency, provider, product_label,
            plan_label, sale_type_label
     FROM sales WHERE id = ?1 AND status = 'succeeded'`,
  )
    .bind(message.saleId)
    .first<SaleNotificationRow>();
  if (!sale) return true;
  const devices = await env.DB.prepare(
    "SELECT id, token, environment FROM device_tokens WHERE user_id = ?1 AND status = 'active'",
  )
    .bind(sale.user_id)
    .all<DeviceRow>();
  if (devices.results.length === 0) return true;
  if (!env.APNS_KEY_ID || !env.APNS_PRIVATE_KEY) {
    throw new Error("APNs is not configured");
  }

  const providerToken = await apnsProviderToken(env);
  let shouldRetry = false;
  for (const device of devices.results) {
    const proposedDeliveryId = crypto.randomUUID();
    await env.DB.prepare(
      `INSERT OR IGNORE INTO notification_deliveries (id, sale_id, device_token_id)
       VALUES (?1, ?2, ?3)`,
    )
      .bind(proposedDeliveryId, sale.id, device.id)
      .run();
    const delivery = await env.DB.prepare(
      "SELECT id, status FROM notification_deliveries WHERE sale_id = ?1 AND device_token_id = ?2",
    )
      .bind(sale.id, device.id)
      .first<DeliveryStatusRow>();
    if (!delivery) throw new Error("Notification delivery could not be persisted");
    const claimed = await env.DB.prepare(
      `UPDATE notification_deliveries
       SET status = 'sending', attempt_count = attempt_count + 1,
           last_attempt_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
       WHERE sale_id = ?1 AND device_token_id = ?2
         AND (
           status IN ('pending', 'retry')
           OR (status = 'sending' AND last_attempt_at <= datetime('now', '-5 minutes'))
         )`,
    )
      .bind(sale.id, device.id)
      .run();
    if (Number(claimed.meta.changes ?? 0) !== 1) {
      const existing = await env.DB.prepare(
        "SELECT id, status FROM notification_deliveries WHERE sale_id = ?1 AND device_token_id = ?2",
      )
        .bind(sale.id, device.id)
        .first<DeliveryStatusRow>();
      if (shouldRetryUnclaimedDelivery(existing?.status)) shouldRetry = true;
      continue;
    }

    const outcome = await sendToDevice(env, providerToken, sale, device, delivery.id);
    if (outcome === "sent") {
      await env.DB.prepare(
        `UPDATE notification_deliveries SET status = 'sent', apns_id = ?3,
         sent_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE sale_id = ?1 AND device_token_id = ?2`,
      )
        .bind(sale.id, device.id, delivery.id)
        .run();
    } else if (outcome === "invalid") {
      await env.DB.batch([
        env.DB.prepare(
          "UPDATE device_tokens SET status = 'invalid', updated_at = CURRENT_TIMESTAMP WHERE id = ?1",
        ).bind(device.id),
        env.DB.prepare(
          `UPDATE notification_deliveries SET status = 'failed', error_code = 'invalid_token',
           updated_at = CURRENT_TIMESTAMP WHERE sale_id = ?1 AND device_token_id = ?2`,
        ).bind(sale.id, device.id),
      ]);
    } else if (outcome === "retry") {
      shouldRetry = true;
      await env.DB.prepare(
        `UPDATE notification_deliveries SET status = 'retry', error_code = 'transient_apns',
         updated_at = CURRENT_TIMESTAMP WHERE sale_id = ?1 AND device_token_id = ?2`,
      )
        .bind(sale.id, device.id)
        .run();
    } else {
      await env.DB.prepare(
        `UPDATE notification_deliveries SET status = 'failed', error_code = 'permanent_apns',
         updated_at = CURRENT_TIMESTAMP WHERE sale_id = ?1 AND device_token_id = ?2`,
      )
        .bind(sale.id, device.id)
        .run();
    }
  }
  return !shouldRetry;
}

function validMessage(value: unknown): value is NotificationMessage {
  return Boolean(value && typeof value === "object" && typeof (value as Record<string, unknown>).saleId === "string");
}

export async function processNotificationBatch(
  env: Env,
  batch: MessageBatch<NotificationMessage>,
): Promise<void> {
  for (const message of batch.messages) {
    if (!validMessage(message.body)) {
      message.ack();
      continue;
    }
    try {
      if (await deliverSale(env, message.body)) message.ack();
      else message.retry({ delaySeconds: 60 });
    } catch (error) {
      console.error(JSON.stringify({
        message: "notification.delivery.failed",
        saleId: message.body.saleId,
        error: error instanceof Error ? error.message : "Unknown error",
      }));
      message.retry({ delaySeconds: 60 });
    }
  }
}
