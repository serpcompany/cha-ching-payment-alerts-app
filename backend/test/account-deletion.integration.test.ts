import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { handleAccountDeletion, handleAppleCredentialRequest } from "../src/account-deletion";
import type { AppleCredentialClient } from "../src/account-deletion";
import type { Auth } from "../src/auth";
import type { Env } from "../src/env";
import { applyMigration } from "./apply-migration";

const encryptionKey = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=";

function authFor(userId: string): Auth {
  return {
    api: {
      getSession: async () => ({
        user: { id: userId, name: "Founder", email: "founder@example.test" },
        session: { id: `session-${userId}` },
      }),
    },
  } as unknown as Auth;
}

describe("authenticated account deletion", () => {
  let miniflare: Miniflare;
  let env: Env;
  let client: AppleCredentialClient;
  const revoke = vi.fn(async () => undefined);

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    const db = await miniflare.getD1Database("DB");
    for (const migration of [
      "0001_initial.sql", "0002_sales_and_notifications.sql",
      "0003_anonymous_simulator_user.sql", "0004_nullable_provider_access_token.sql",
      "0005_custom_payment_sources.sql", "0006_provider_connection_activity.sql",
      "0007_provider_event_disposition.sql", "0008_notification_queue_claims.sql",
      "0009_custom_notification_fields.sql", "0010_reconcile_custom_payment_history_presentation.sql",
      "0011_retain_custom_payment_field_values.sql", "0012_custom_source_health.sql",
      "0013_product_entitlements.sql", "0014_apple_account_deletion_credentials.sql",
      "0015_user_preferences.sql",
      "0016_sales_ingestion_order.sql",
    ]) {
      await applyMigration(db, migration);
    }
    await db.prepare(
      "INSERT INTO user (id, name, email, created_at, updated_at) VALUES ('owner', 'Founder', 'founder@example.test', ?1, ?1)",
    ).bind(Date.now()).run();
    await db.prepare(
      `INSERT INTO account (id, account_id, provider_id, user_id, created_at, updated_at)
       VALUES ('account', 'apple-subject', 'apple', 'owner', ?1, ?1)`,
    ).bind(Date.now()).run();
    env = {
      DB: db,
      APPLE_APP_BUNDLE_ID: "com.serpcompany.chaching",
      PROVIDER_TOKEN_ENCRYPTION_KEY: encryptionKey,
    } as unknown as Env;
    revoke.mockClear();
    client = {
      exchangeAuthorizationCode: vi.fn(async () => ({
        subject: "apple-subject",
        refreshToken: "apple-refresh-token",
      })),
      revokeRefreshToken: revoke,
    };
  });

  afterEach(async () => miniflare.dispose());

  async function seedProductData() {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO session (id, expires_at, token, created_at, updated_at, user_id) VALUES ('session', ?1, 'token', ?2, ?2, 'owner')").bind(Date.now() + 60_000, Date.now()),
      env.DB.prepare("INSERT INTO entitlements (user_id, feature_key) VALUES ('owner', 'connect_stripe')"),
      env.DB.prepare("INSERT INTO provider_connections (id, user_id, provider, provider_account_id) VALUES ('connection', 'owner', 'stripe', 'acct_owner')"),
      env.DB.prepare("INSERT INTO oauth_states (state_hash, user_id, provider, expires_at) VALUES ('state', 'owner', 'stripe', '2099-01-01T00:00:00Z')"),
      env.DB.prepare("INSERT INTO provider_events (id, provider, provider_event_id, user_id, provider_account_id, event_type) VALUES ('event', 'stripe', 'evt_owner', 'owner', 'acct_owner', 'charge.succeeded')"),
      env.DB.prepare("INSERT INTO custom_payment_sources (id, user_id, name, webhook_token_hash, webhook_token_ciphertext) VALUES ('source', 'owner', 'Store', 'hash', 'ciphertext')"),
      env.DB.prepare("INSERT INTO product_entitlements (user_id, app_account_token) VALUES ('owner', '11111111-1111-4111-8111-111111111111')"),
      env.DB.prepare("INSERT INTO user_preferences (user_id, reporting_timezone) VALUES ('owner', 'Asia/Tokyo')"),
      env.DB.prepare("INSERT INTO device_tokens (id, user_id, device_id, token, environment) VALUES ('device', 'owner', 'iphone', 'apns', 'production')"),
      env.DB.prepare(`INSERT INTO sales
        (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
         amount_minor, currency, product_label, occurred_at)
        VALUES ('sale', 'owner', 'stripe', 'acct_owner', 'evt_sale', 'payment', 1499, 'USD', 'Sale', ?1)`).bind(Date.now()),
    ]);
    await env.DB.prepare("INSERT INTO notification_deliveries (id, sale_id, device_token_id) VALUES ('delivery', 'sale', 'device')").run();
  }

  it("revokes Apple access before deleting every user-linked record", async () => {
    await seedProductData();
    const credential = await handleAppleCredentialRequest(
      env, authFor("owner"),
      new Request("https://api.test/v1/account/apple-credential", {
        method: "POST",
        body: JSON.stringify({ authorizationCode: "one-time-code", nonce: "nonce" }),
      }),
      client,
    );
    expect(credential.status).toBe(200);

    const deletion = await handleAccountDeletion(
      env, authFor("owner"), new Request("https://api.test/v1/account", { method: "DELETE" }), client,
    );
    expect(await deletion.json()).toEqual({ deleted: true, appleCredentialRevoked: true });
    expect(revoke).toHaveBeenCalledWith("apple-refresh-token");

    for (const table of [
      "user", "session", "account", "entitlements", "provider_connections", "oauth_states",
      "provider_events", "custom_payment_sources", "product_entitlements", "device_tokens",
      "sales", "notification_deliveries", "apple_account_credentials",
      "user_preferences",
      "sales_ingestion_order",
    ]) {
      const row = await env.DB.prepare(`SELECT COUNT(*) AS count FROM ${table}`).first<{ count: number }>();
      expect(row?.count, table).toBe(0);
    }
  });

  it("keeps the account intact when Apple revocation fails", async () => {
    await seedProductData();
    await handleAppleCredentialRequest(
      env, authFor("owner"),
      new Request("https://api.test/v1/account/apple-credential", {
        method: "POST", body: JSON.stringify({ authorizationCode: "one-time-code", nonce: "nonce" }),
      }),
      client,
    );
    client.revokeRefreshToken = vi.fn(async () => { throw new Error("Apple unavailable"); });

    const response = await handleAccountDeletion(
      env, authFor("owner"), new Request("https://api.test/v1/account", { method: "DELETE" }), client,
    );
    expect(response.status).toBe(502);
    expect(await env.DB.prepare("SELECT id FROM user WHERE id = 'owner'").first()).not.toBeNull();
  });

  it("rejects an Apple credential belonging to a different subject", async () => {
    client.exchangeAuthorizationCode = vi.fn(async () => ({
      subject: "someone-else",
      refreshToken: "wrong-token",
    }));
    const response = await handleAppleCredentialRequest(
      env, authFor("owner"),
      new Request("https://api.test/v1/account/apple-credential", {
        method: "POST", body: JSON.stringify({ authorizationCode: "one-time-code", nonce: "nonce" }),
      }),
      client,
    );
    expect(response.status).toBe(403);
    expect(await env.DB.prepare("SELECT * FROM apple_account_credentials").first()).toBeNull();
  });
});
