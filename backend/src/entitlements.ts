import type { Env, Provider } from "./env";
import { requireProductAccess } from "./subscriptions";

export const featureForProvider = (provider: Provider) => `connect_${provider}` as const;

const defaults = ["connect_custom", "connect_paypal", "connect_stripe"] as const;

export interface EntitlementRow {
  feature_key: (typeof defaults)[number];
  enabled: number;
}

export async function getUserEntitlements(db: D1Database, userId: string) {
  await db.batch(
    defaults.map((feature) =>
      db
        .prepare(
          "INSERT INTO entitlements (user_id, feature_key, enabled) VALUES (?1, ?2, 1) ON CONFLICT(user_id, feature_key) DO NOTHING",
        )
        .bind(userId, feature),
    ),
  );
  const result = await db
    .prepare("SELECT feature_key, enabled FROM entitlements WHERE user_id = ?1 ORDER BY feature_key")
    .bind(userId)
    .all<EntitlementRow>();
  return result.results.map((row) => ({ feature: row.feature_key, enabled: row.enabled === 1 }));
}

export async function requireProviderEntitlement(
  env: Env,
  userId: string,
  provider: Provider,
): Promise<void> {
  await requireProductAccess(env, userId);
  const entitlements = await getUserEntitlements(env.DB, userId);
  if (!entitlements.some((item) => item.feature === featureForProvider(provider) && item.enabled)) {
    throw new Response(JSON.stringify({ error: `${provider} connections are not included in your plan` }), {
      status: 403,
      headers: { "content-type": "application/json" },
    });
  }
}

export async function requireCustomSourceEntitlement(env: Env, userId: string): Promise<void> {
  await requireProductAccess(env, userId);
  const entitlements = await getUserEntitlements(env.DB, userId);
  if (!entitlements.some((item) => item.feature === "connect_custom" && item.enabled)) {
    throw new Response(JSON.stringify({ error: "Custom payment sources are not included in your plan" }), {
      status: 403,
      headers: { "content-type": "application/json" },
    });
  }
}
