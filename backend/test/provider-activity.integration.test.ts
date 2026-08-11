import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Auth } from "../src/auth";
import { clearProviderPayments, listConnections, setConnectionActivity } from "../src/connections";
import type { Env } from "../src/env";
import { listSales } from "../src/sales";
import { handleStripeWebhook, stripeSignature } from "../src/stripe-webhooks";

function authFor(userId: string): Auth {
  return {
    api: {
      getSession: async () => ({
        user: { id: userId, name: userId, email: `${userId}@example.test` },
        session: { id: `session-${userId}` },
      }),
    },
  } as unknown as Auth;
}

describe("connected provider activity", () => {
  let miniflare: Miniflare;
  let env: Env;
  const queued: Array<{ saleId: string }> = [];

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    const db = await miniflare.getD1Database("DB");
    for (const migration of [
      "0001_initial.sql",
      "0002_sales_and_notifications.sql",
      "0003_anonymous_simulator_user.sql",
      "0004_nullable_provider_access_token.sql",
      "0005_custom_payment_sources.sql",
      "0006_provider_connection_activity.sql",
      "0007_provider_event_disposition.sql",
      "0008_notification_queue_claims.sql",
      "0009_custom_notification_fields.sql",
    ]) {
      const statements = (await readFile(join(process.cwd(), "migrations", migration), "utf8"))
        .replace(/--.*$/gm, "")
        .split(";")
        .map((statement) => statement.trim())
        .filter((statement) => statement && !statement.startsWith("PRAGMA foreign_keys"));
      for (const statement of statements) await db.prepare(statement).run();
    }
    await db.prepare(
      "INSERT INTO user (id, name, email, created_at, updated_at) VALUES ('owner', 'Owner', 'owner@example.test', 1, 1)",
    ).run();
    await db.prepare(
      `INSERT INTO provider_connections (
        id, user_id, provider, status, provider_account_id, account_label
      ) VALUES ('connection', 'owner', 'stripe', 'connected', 'acct_owner', 'Owner Stripe')`,
    ).run();
    await db.prepare(
      `INSERT INTO sales (
        id, user_id, provider, provider_account_id, provider_event_id,
        provider_payment_id, amount_minor, currency, product_label, is_subscription, occurred_at
      ) VALUES ('existing', 'owner', 'stripe', 'acct_owner', 'evt_existing',
        'ch_existing', 500, 'USD', 'Existing sale', 0, 1)`,
    ).run();
    queued.length = 0;
    env = {
      DB: db,
      NOTIFICATION_QUEUE: { send: vi.fn(async (message) => queued.push(message as { saleId: string })) },
      STRIPE_WEBHOOK_SECRET: "whsec_provider_activity",
    } as unknown as Env;
  });

  afterEach(async () => {
    await miniflare.dispose();
  });

  it("pauses Stripe payments without disconnecting or erasing history, then resumes", async () => {
    const notOwner = await setConnectionActivity(
      env,
      authFor("someone-else"),
      new Request("https://api.cha-ching.test/v1/connections/stripe/pause", { method: "POST" }),
      "stripe",
      false,
    );
    expect(notOwner.status).toBe(404);

    const pause = await setConnectionActivity(
      env,
      authFor("owner"),
      new Request("https://api.cha-ching.test/v1/connections/stripe/pause", { method: "POST" }),
      "stripe",
      false,
    );
    expect(pause.status).toBe(200);

    const connections = await listConnections(
      env,
      authFor("owner"),
      new Request("https://api.cha-ching.test/v1/connections"),
    );
    expect(await connections.json()).toEqual({
      connections: [expect.objectContaining({
        provider: "stripe",
        status: "connected",
        providerAccountId: "acct_owner",
        accountLabel: "Owner Stripe",
        isActive: false,
      })],
    });

    const event = JSON.stringify({
      id: "evt_while_paused",
      type: "charge.succeeded",
      account: "acct_owner",
      livemode: true,
      data: { object: { id: "ch_while_paused", amount: 2700, currency: "usd", created: 2 } },
    });
    const timestamp = Math.floor(Date.now() / 1_000);
    const signature = await stripeSignature(event, timestamp, env.STRIPE_WEBHOOK_SECRET);
    const webhook = await handleStripeWebhook(env, new Request("https://api.cha-ching.test/v1/webhooks/stripe", {
      method: "POST",
      headers: { "stripe-signature": `t=${timestamp},v1=${signature}` },
      body: event,
    }));
    expect(webhook.status).toBe(200);

    const history = await listSales(env, authFor("owner"), new Request("https://api.cha-ching.test/v1/sales"));
    expect((await history.json<{ sales: unknown[] }>()).sales).toHaveLength(1);
    expect(queued).toEqual([]);

    const resume = await setConnectionActivity(
      env,
      authFor("owner"),
      new Request("https://api.cha-ching.test/v1/connections/stripe/resume", { method: "POST" }),
      "stripe",
      true,
    );
    expect(resume.status).toBe(200);
    const resumed = await listConnections(env, authFor("owner"), new Request("https://api.cha-ching.test/v1/connections"));
    expect((await resumed.json<{ connections: Array<{ isActive: boolean }> }>()).connections[0].isActive).toBe(true);

    const replaySignature = await stripeSignature(event, timestamp, env.STRIPE_WEBHOOK_SECRET);
    const replay = await handleStripeWebhook(env, new Request("https://api.cha-ching.test/v1/webhooks/stripe", {
      method: "POST",
      headers: { "stripe-signature": `t=${timestamp},v1=${replaySignature}` },
      body: event,
    }));
    expect(replay.status).toBe(200);
    const replayedHistory = await listSales(env, authFor("owner"), new Request("https://api.cha-ching.test/v1/sales"));
    expect((await replayedHistory.json<{ sales: unknown[] }>()).sales).toHaveLength(1);
    expect(queued).toEqual([]);
    const audit = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM provider_events WHERE provider = 'stripe' AND provider_event_id = ?1",
    ).bind("evt_while_paused").first<{ count: number }>();
    expect(audit?.count).toBe(1);

    const resumedEvent = JSON.stringify({
      id: "evt_after_resume",
      type: "charge.succeeded",
      account: "acct_owner",
      livemode: true,
      data: { object: { id: "ch_after_resume", amount: 2800, currency: "usd", created: 3 } },
    });
    const resumedSignature = await stripeSignature(resumedEvent, timestamp, env.STRIPE_WEBHOOK_SECRET);
    await handleStripeWebhook(env, new Request("https://api.cha-ching.test/v1/webhooks/stripe", {
      method: "POST",
      headers: { "stripe-signature": `t=${timestamp},v1=${resumedSignature}` },
      body: resumedEvent,
    }));
    const resumedHistory = await listSales(env, authFor("owner"), new Request("https://api.cha-ching.test/v1/sales"));
    expect((await resumedHistory.json<{ sales: unknown[] }>()).sales).toHaveLength(2);
    expect(queued).toHaveLength(1);
  });

  it("clears only the owner's Stripe payments while preserving the paused connection", async () => {
    await setConnectionActivity(
      env,
      authFor("owner"),
      new Request("https://api.cha-ching.test/v1/connections/stripe/pause", { method: "POST" }),
      "stripe",
      false,
    );
    await env.DB.prepare(
      `INSERT INTO sales (
        id, user_id, provider, provider_account_id, provider_event_id,
        provider_payment_id, amount_minor, currency, product_label, is_subscription, occurred_at
      ) VALUES ('custom-existing', 'owner', 'custom', 'custom-source', 'custom:event',
        'custom:payment', 900, 'USD', 'Custom sale', 0, 2)`,
    ).run();
    await env.DB.prepare(
      `INSERT INTO device_tokens (id, user_id, device_id, token, environment)
       VALUES ('device', 'owner', 'device', 'token', 'production')`,
    ).run();
    await env.DB.prepare(
      `INSERT INTO notification_deliveries (id, sale_id, device_token_id, status)
       VALUES ('delivery', 'existing', 'device', 'sent')`,
    ).run();
    await env.DB.prepare(
      `INSERT INTO provider_events (
        id, provider, provider_event_id, user_id, provider_account_id,
        event_type, livemode, disposition
      ) VALUES ('event-audit', 'stripe', 'evt_existing', 'owner', 'acct_owner',
        'charge.succeeded', 1, 'processed')`,
    ).run();

    const notOwner = await clearProviderPayments(
      env,
      authFor("someone-else"),
      new Request("https://api.cha-ching.test/v1/connections/stripe/payments", { method: "DELETE" }),
      "stripe",
    );
    expect(notOwner.status).toBe(404);

    const clear = await clearProviderPayments(
      env,
      authFor("owner"),
      new Request("https://api.cha-ching.test/v1/connections/stripe/payments", { method: "DELETE" }),
      "stripe",
    );
    expect(clear.status).toBe(200);
    expect(await clear.json()).toEqual({ clearedPayments: 1 });

    const history = await listSales(env, authFor("owner"), new Request("https://api.cha-ching.test/v1/sales"));
    expect(await history.json()).toEqual({
      sales: [expect.objectContaining({ id: "custom-existing", provider: "custom" })],
    });
    const connections = await listConnections(
      env,
      authFor("owner"),
      new Request("https://api.cha-ching.test/v1/connections"),
    );
    expect(await connections.json()).toEqual({
      connections: [expect.objectContaining({ provider: "stripe", isActive: false })],
    });
    const deliveries = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM notification_deliveries WHERE sale_id = 'existing'",
    ).first<{ count: number }>();
    expect(deliveries?.count).toBe(0);
    const eventAudit = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM provider_events WHERE id = 'event-audit'",
    ).first<{ count: number }>();
    expect(eventAudit?.count).toBe(1);

    const clearAgain = await clearProviderPayments(
      env,
      authFor("owner"),
      new Request("https://api.cha-ching.test/v1/connections/stripe/payments", { method: "DELETE" }),
      "stripe",
    );
    expect(await clearAgain.json()).toEqual({ clearedPayments: 0 });
  });

  it("recovers one notification when the first queue send fails and Stripe retries the exact event", async () => {
    await env.DB.prepare("DELETE FROM sales").run();
    let attempts = 0;
    const successful: Array<{ saleId: string }> = [];
    env.NOTIFICATION_QUEUE = {
      send: vi.fn(async (message) => {
        attempts += 1;
        if (attempts === 1) throw new Error("temporary queue failure");
        successful.push(message as { saleId: string });
      }),
    } as unknown as Queue;
    const event = JSON.stringify({
      id: "evt_queue_retry",
      type: "charge.succeeded",
      account: "acct_owner",
      livemode: true,
      data: { object: { id: "ch_queue_retry", amount: 3100, currency: "usd", created: 4 } },
    });
    const timestamp = Math.floor(Date.now() / 1_000);
    const signature = await stripeSignature(event, timestamp, env.STRIPE_WEBHOOK_SECRET);
    const post = () => handleStripeWebhook(env, new Request("https://api.cha-ching.test/v1/webhooks/stripe", {
      method: "POST",
      headers: { "stripe-signature": `t=${timestamp},v1=${signature}` },
      body: event,
    }));

    await expect(post()).rejects.toThrow("temporary queue failure");
    expect((await post()).status).toBe(200);

    const history = await listSales(env, authFor("owner"), new Request("https://api.cha-ching.test/v1/sales"));
    expect((await history.json<{ sales: unknown[] }>()).sales).toHaveLength(1);
    expect(attempts).toBe(2);
    expect(successful).toEqual([{ saleId: "stripe:ch_queue_retry" }]);
  });

  it("recovers when sale persistence fails before Stripe retries the exact event", async () => {
    await env.DB.prepare("DELETE FROM sales").run();
    await env.DB.prepare(
      `CREATE TRIGGER fail_transient_sale BEFORE INSERT ON sales
       WHEN NEW.provider_event_id = 'evt_sale_retry'
       BEGIN SELECT RAISE(ABORT, 'temporary sale failure'); END`,
    ).run();
    const event = JSON.stringify({
      id: "evt_sale_retry",
      type: "charge.succeeded",
      account: "acct_owner",
      livemode: true,
      data: { object: { id: "ch_sale_retry", amount: 3200, currency: "usd", created: 5 } },
    });
    const timestamp = Math.floor(Date.now() / 1_000);
    const signature = await stripeSignature(event, timestamp, env.STRIPE_WEBHOOK_SECRET);
    const post = () => handleStripeWebhook(env, new Request("https://api.cha-ching.test/v1/webhooks/stripe", {
      method: "POST",
      headers: { "stripe-signature": `t=${timestamp},v1=${signature}` },
      body: event,
    }));

    await expect(post()).rejects.toThrow();
    await env.DB.prepare("DROP TRIGGER fail_transient_sale").run();
    expect((await post()).status).toBe(200);

    const history = await listSales(env, authFor("owner"), new Request("https://api.cha-ching.test/v1/sales"));
    expect((await history.json<{ sales: unknown[] }>()).sales).toHaveLength(1);
    expect(queued).toEqual([{ saleId: "stripe:ch_sale_retry" }]);
  });

  it("reclaims a stale pre-send queue claim when Stripe retries the exact event", async () => {
    await env.DB.prepare("DELETE FROM sales").run();
    await env.DB.prepare("DELETE FROM provider_events").run();
    await env.DB.prepare(
      `INSERT INTO provider_events (
        id, provider, provider_event_id, user_id, provider_account_id,
        event_type, livemode, disposition
      ) VALUES ('stripe:evt_claim_retry', 'stripe', 'evt_claim_retry', 'owner',
        'acct_owner', 'charge.succeeded', 1, 'received')`,
    ).run();
    await env.DB.prepare(
      `INSERT INTO sales (
        id, user_id, provider, provider_account_id, provider_event_id,
        provider_payment_id, amount_minor, currency, product_label,
        is_subscription, occurred_at, notification_queued_at,
        notification_queue_state, notification_queue_claimed_at
      ) VALUES ('stripe:ch_claim_retry', 'owner', 'stripe', 'acct_owner',
        'evt_claim_retry', 'ch_claim_retry', 3300, 'USD', 'Stripe payment',
        0, 6, datetime('now', '-10 minutes'), 'claimed', datetime('now', '-10 minutes'))`,
    ).run();
    const event = JSON.stringify({
      id: "evt_claim_retry",
      type: "charge.succeeded",
      account: "acct_owner",
      livemode: true,
      data: { object: { id: "ch_claim_retry", amount: 3300, currency: "usd", created: 6 } },
    });
    const timestamp = Math.floor(Date.now() / 1_000);
    const signature = await stripeSignature(event, timestamp, env.STRIPE_WEBHOOK_SECRET);

    const response = await handleStripeWebhook(env, new Request("https://api.cha-ching.test/v1/webhooks/stripe", {
      method: "POST",
      headers: { "stripe-signature": `t=${timestamp},v1=${signature}` },
      body: event,
    }));

    expect(response.status).toBe(200);
    expect(queued).toEqual([{ saleId: "stripe:ch_claim_retry" }]);
    const sale = await env.DB.prepare(
      `SELECT notification_queue_state, notification_queue_claimed_at
       FROM sales WHERE id = 'stripe:ch_claim_retry'`,
    ).first<{ notification_queue_state: string; notification_queue_claimed_at: string | null }>();
    expect(sale).toEqual({ notification_queue_state: "accepted", notification_queue_claimed_at: null });
  });
});
