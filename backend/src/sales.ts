import type { Auth } from "./auth";
import { requireUser } from "./auth";
import type { Env, SaleSource } from "./env";

interface SaleRow {
  id: string;
  provider: SaleSource;
  amount_minor: number;
  currency: string;
  product_label: string;
  plan_label: string | null;
  sale_type_label: string | null;
  country_code: string | null;
  is_subscription: number;
  occurred_at: number;
  notification_fields_json: string | null;
}

interface SaleDetailField {
  label: string;
  value: string;
}

function notificationFields(value: string | null): SaleDetailField[] | undefined {
  if (!value) return undefined;
  try {
    const fields = JSON.parse(value) as unknown;
    if (!Array.isArray(fields)) return undefined;
    const valid = fields.filter((field): field is SaleDetailField => Boolean(
      field && typeof field === "object"
      && typeof (field as Record<string, unknown>).label === "string"
      && typeof (field as Record<string, unknown>).value === "string"
    ));
    return valid.length === fields.length ? valid : undefined;
  } catch {
    return undefined;
  }
}

function saleResponse(sale: SaleRow) {
  const details = notificationFields(sale.notification_fields_json);
  return {
    id: sale.id,
    provider: sale.provider,
    amountMinor: sale.amount_minor,
    currency: sale.currency,
    productLabel: sale.product_label,
    plan: sale.plan_label,
    saleType: sale.sale_type_label,
    countryCode: sale.country_code,
    isSubscription: sale.is_subscription === 1,
    occurredAt: new Date(sale.occurred_at * 1_000).toISOString(),
    ...(details ? { notificationFields: details } : {}),
  };
}

export async function listSales(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  const result = await env.DB.prepare(
    `SELECT id, provider, amount_minor, currency, product_label, plan_label,
            sale_type_label, country_code, notification_fields_json,
            is_subscription, occurred_at
     FROM sales WHERE user_id = ?1 AND status = 'succeeded'
     ORDER BY occurred_at DESC LIMIT 100`,
  )
    .bind(user.id)
    .all<SaleRow>();
  return Response.json({
    sales: result.results.map(saleResponse),
  });
}

export async function getSale(
  env: Env,
  auth: Auth,
  request: Request,
  saleID: string,
): Promise<Response> {
  const user = await requireUser(auth, request);
  const sale = await env.DB.prepare(
    `SELECT id, provider, amount_minor, currency, product_label, plan_label,
            sale_type_label, country_code, notification_fields_json,
            is_subscription, occurred_at
     FROM sales
     WHERE id = ?1 AND user_id = ?2 AND status = 'succeeded'`,
  ).bind(saleID, user.id).first<SaleRow>();
  if (!sale) return Response.json({ error: "Payment not found" }, { status: 404 });
  return Response.json({ sale: saleResponse(sale) });
}
