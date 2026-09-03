import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Auth } from "../src/auth";
import type { Env } from "../src/env";
import { getSale, listSales, saleIDFromPath } from "../src/sales";
import { applyMigration } from "./apply-migration";

function authFor(userID: string): Auth {
  return {
    api: {
      getSession: async () => ({
        user: { id: userID, name: "Founder", email: `${userID}@example.test` },
        session: { id: `session-${userID}` },
      }),
    },
  } as unknown as Auth;
}

describe("payment history API", () => {
  let miniflare: Miniflare;
  let env: Env;

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    const db = await miniflare.getD1Database("DB");
    const migrations = [
      "0001_initial.sql", "0002_sales_and_notifications.sql", "0003_anonymous_simulator_user.sql",
      "0004_nullable_provider_access_token.sql", "0005_custom_payment_sources.sql",
      "0006_provider_connection_activity.sql", "0007_provider_event_disposition.sql",
      "0008_notification_queue_claims.sql", "0009_custom_notification_fields.sql",
      "0010_reconcile_custom_payment_history_presentation.sql", "0011_retain_custom_payment_field_values.sql",
      "0012_custom_source_health.sql", "0013_product_entitlements.sql",
      "0014_apple_account_deletion_credentials.sql", "0015_user_preferences.sql",
      "0016_sales_ingestion_order.sql",
    ];
    for (const migration of migrations) {
      await applyMigration(db, migration);
    }
    await db.batch(["owner", "other"].map((id) => db.prepare(
      "INSERT INTO user (id, name, email, created_at, updated_at) VALUES (?1, 'Founder', ?2, ?3, ?3)",
    ).bind(id, `${id}@example.test`, Date.now())));
    env = { DB: db } as unknown as Env;
  });

  afterEach(async () => miniflare.dispose());

  it("routes real provider and custom IDs with exactly one decode", () => {
    expect(saleIDFromPath("/v1/sales/stripe%3Ach_3Pabc123")).toBe("stripe:ch_3Pabc123");
    expect(saleIDFromPath("/v1/sales/custom%3Aorder_42")).toBe("custom:order_42");
    expect(saleIDFromPath("/v1/sales/stripe:ch_literal")).toBe("stripe:ch_literal");
    expect(saleIDFromPath("/v1/sales/bad%2Fsegment")).toBe("bad/segment");
    expect(saleIDFromPath("/v1/sales/bad%ZZ")).toBeNull();
    expect(saleIDFromPath("/v1/sales/one/more")).toBeNull();
  });

  it("fetches an exact owned payment even when it is outside the latest 100", async () => {
    const statements = [];
    for (let index = 0; index < 101; index += 1) {
      statements.push(env.DB.prepare(
        `INSERT INTO sales
         (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
          amount_minor, currency, product_label, occurred_at)
         VALUES (?1, 'owner', 'stripe', 'acct', ?2, ?3, 100, 'USD', ?4, ?5)`,
      ).bind(`sale-${index}`, `event-${index}`, `payment-${index}`, `Product ${index}`, index));
    }
    for (let index = 0; index < statements.length; index += 75) {
      await env.DB.batch(statements.slice(index, index + 75));
    }

    const list = await listSales(env, authFor("owner"), new Request("https://api.test/v1/sales"));
    const listed = await list.json<{ sales: Array<{ id: string }> }>();
    expect(listed.sales).toHaveLength(100);
    expect(listed.sales.some((sale) => sale.id === "sale-0")).toBe(false);

    const exact = await getSale(
      env,
      authFor("owner"),
      new Request("https://api.test/v1/sales/sale-0"),
      "sale-0",
    );
    expect(exact.status).toBe(200);
    expect(await exact.json()).toEqual({ sale: expect.objectContaining({ id: "sale-0", productLabel: "Product 0" }) });
  }, 15_000);

  it("does not reveal another user's, refunded, or missing payment", async () => {
    await env.DB.prepare(
      `INSERT INTO sales
       (id, user_id, provider, provider_account_id, provider_event_id, provider_payment_id,
        amount_minor, currency, status, product_label, occurred_at)
       VALUES ('private', 'owner', 'stripe', 'acct', 'private-event', 'private-payment',
               100, 'USD', 'succeeded', 'Private', 1),
              ('refunded', 'owner', 'stripe', 'acct', 'refund-event', 'refund-payment',
               100, 'USD', 'refunded', 'Refunded', 2)`,
    ).run();

    for (const id of ["private", "refunded", "missing"]) {
      const response = await getSale(
        env,
        authFor(id === "private" ? "other" : "owner"),
        new Request(`https://api.test/v1/sales/${id}`),
        id,
      );
      expect(response.status, id).toBe(404);
      expect(await response.json(), id).toEqual({ error: "Payment not found" });
    }

    const unauthenticated = {
      api: { getSession: async () => null },
    } as unknown as Auth;
    await expect(getSale(
      env,
      unauthenticated,
      new Request("https://api.test/v1/sales/private"),
      "private",
    )).rejects.toMatchObject({ status: 401 });
  });
});
