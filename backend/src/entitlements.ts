import type { Provider } from "./env";

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
  db: D1Database,
  userId: string,
  provider: Provider,
): Promise<void> {
  const entitlements = await getUserEntitlements(db, userId);
  if (!entitlements.some((item) => item.feature === featureForProvider(provider) && item.enabled)) {
    throw new Response(JSON.stringify({ error: `${provider} connections are not included in your plan` }), {
      status: 403,
      headers: { "content-type": "application/json" },
    });
  }
}

export async function requireCustomSourceEntitlement(db: D1Database, userId: string): Promise<void> {
  const entitlements = await getUserEntitlements(db, userId);
  if (!entitlements.some((item) => item.feature === "connect_custom" && item.enabled)) {
    throw new Response(JSON.stringify({ error: "Custom payment sources are not included in your plan" }), {
      status: 403,
      headers: { "content-type": "application/json" },
    });
  }
}
