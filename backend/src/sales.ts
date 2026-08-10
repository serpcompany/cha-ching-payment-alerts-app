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
}

export async function listSales(env: Env, auth: Auth, request: Request): Promise<Response> {
  const user = await requireUser(auth, request);
  const result = await env.DB.prepare(
    `SELECT id, provider, amount_minor, currency, product_label, plan_label,
            sale_type_label, country_code,
            is_subscription, occurred_at
     FROM sales WHERE user_id = ?1 AND status = 'succeeded'
     ORDER BY occurred_at DESC LIMIT 100`,
  )
    .bind(user.id)
    .all<SaleRow>();
  return Response.json({
    sales: result.results.map((sale) => ({
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
    })),
  });
}
