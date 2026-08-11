import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { generateKeyPairSync } from "node:crypto";

import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { Auth } from "../src/auth";
import { sha256 } from "../src/crypto";
import { handleCustomSourceRequest } from "../src/custom-webhooks";
import type { Env } from "../src/env";
import { processNotificationBatch } from "../src/notifications";
import { listSales } from "../src/sales";

const encryptionKey = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=";

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

describe("custom payment source HTTP API", () => {
  let miniflare: Miniflare;
  let env: Env;
  const sent: Array<{ saleId: string }> = [];
  const queueSends: Array<{ message: unknown; options: QueueSendOptions | undefined }> = [];

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    const db = await miniflare.getD1Database("DB");
    for (const migration of ["0001_initial.sql", "0002_sales_and_notifications.sql", "0003_anonymous_simulator_user.sql", "0004_nullable_provider_access_token.sql", "0005_custom_payment_sources.sql", "0006_provider_connection_activity.sql", "0007_provider_event_disposition.sql", "0008_notification_queue_claims.sql", "0009_custom_notification_fields.sql", "0010_reconcile_custom_payment_history_presentation.sql"]) {
      const statements = (await readFile(join(process.cwd(), "migrations", migration), "utf8"))
        .replace(/--.*$/gm, "")
        .split(";")
        .map((statement) => statement.trim())
        .filter((statement) => statement && !statement.startsWith("PRAGMA foreign_keys"));
      for (const statement of statements) await db.prepare(statement).run();
    }
    await db.prepare(
      "INSERT INTO user (id, name, email, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)",
    ).bind("user-one", "User One", "one@example.test", Date.now()).run();
    await db.prepare(
      "INSERT INTO user (id, name, email, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)",
    ).bind("user-two", "User Two", "two@example.test", Date.now()).run();
    sent.length = 0;
    queueSends.length = 0;
    env = {
      DB: db,
      NOTIFICATION_QUEUE: {
        send: vi.fn(async (message, options) => {
          queueSends.push({ message, options });
          if ((message as { saleId?: unknown }).saleId) sent.push(message as { saleId: string });
        }),
      },
      PUBLIC_BASE_URL: "https://api.cha-ching.test",
      PROVIDER_TOKEN_ENCRYPTION_KEY: encryptionKey,
    } as unknown as Env;
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    await miniflare.dispose();
  });

  it("creates a named source with a private URL that stays stable", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "SERP Store" }),
      }),
    );
    expect(create.status).toBe(201);
    const created = await create.json<{
      source: { id: string; name: string; webhookUrl: string; connectionState: string };
    }>();
    expect(created.source.name).toBe("SERP Store");
    expect(created.source.webhookUrl).toMatch(/^https:\/\/api\.cha-ching\.test\/v1\/webhooks\/custom\/[A-Za-z0-9_-]{40,}$/);
    expect(created.source.connectionState).toBe("waiting");

    const list = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources"),
    );
    const listed = await list.json<{
      sources: Array<{ id: string; webhookUrl: string; connectionState: string }>;
    }>();
    expect(listed.sources).toEqual([
      expect.objectContaining({
        id: created.source.id,
        webhookUrl: created.source.webhookUrl,
        connectionState: "waiting",
      }),
    ]);
  });

  it("captures an unfamiliar JSON sample for field selection without creating revenue", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "My checkout" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const sample = {
      event: { id: "order_123", occurred_at: "2026-08-11T06:20:00Z" },
      payment: { total: "27.00", currency: "usd" },
      item: { product: "Download Pro" },
    };

    const capture = await handleCustomSourceRequest(
      env,
      authFor("user-two"),
      new Request(created.source.webhookUrl, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(sample),
      }),
    );
    expect(capture.status).toBe(202);

    const check = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}`),
    );
    expect(await check.json()).toEqual({
      source: expect.objectContaining({
        id: created.source.id,
        status: "setup",
        connectionState: "event_received",
      }),
      sample: {
        receivedAt: expect.any(String),
        fields: expect.arrayContaining([
          { path: "/event/id", value: "order_123", valueType: "string" },
          { path: "/payment/total", value: "27.00", valueType: "string" },
          { path: "/payment/currency", value: "usd", valueType: "string" },
        ]),
        suggestions: expect.objectContaining({
          paymentIdPath: "/event/id",
          amountPath: "/payment/total",
          currencyPath: "/payment/currency",
        }),
      },
    });

    const history = await listSales(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/sales"),
    );
    expect(await history.json()).toEqual({ sales: [] });
    expect(sent).toEqual([]);
  });

  it("applies active notification presentation edits to payment history and future payments", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "My checkout" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/amount_minor",
      amountUnit: "minor",
      currencyPath: "/payment/currency",
      notificationFields: [
        { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: true },
        { id: "buyer", path: "/buyer/email", label: "Buyer", enabled: true },
        { id: "utm", path: "/attribution/utm_source", label: "UTM Source", enabled: true },
      ],
    };
    await env.DB.prepare(
      "UPDATE custom_payment_sources SET status = 'active', mapping_json = ?1 WHERE id = ?2",
    ).bind(JSON.stringify(mapping), created.source.id).run();

    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify({
        payment: { id: "historical-payment", amount_minor: 800, currency: "USD" },
        buyer: { email: "historical@example.com" },
      }),
    }));

    const updatedFields = [
      { id: "buyer", path: "/buyer/email", label: "Customer email", enabled: true },
      { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: false },
      { id: "utm", path: "/attribution/utm_source", label: "UTM Source", enabled: true },
    ];
    const update = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/notification-fields`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ notificationFields: updatedFields }),
      }),
    );

    expect(update.status).toBe(200);
    expect(await update.json()).toEqual({ mapping: { ...mapping, notificationFields: updatedFields } });

    const detail = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}`),
    );
    expect(await detail.json()).toEqual(expect.objectContaining({
      mapping: { ...mapping, notificationFields: updatedFields },
    }));

    const updatedHistory = await listSales(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/sales"),
    );
    expect(await updatedHistory.json()).toEqual({
      sales: [expect.objectContaining({
        notificationFields: [{ label: "Customer email", value: "historical@example.com" }],
      })],
    });

    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify({
        payment: { id: "future-payment", amount_minor: 900, currency: "USD" },
        buyer: { email: "future@example.com" },
      }),
    }));
    const history = await listSales(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/sales"),
    );
    expect(await history.json()).toEqual({
      sales: expect.arrayContaining([
        expect.objectContaining({
          notificationFields: [{ label: "Customer email", value: "future@example.com" }],
        }),
        expect.objectContaining({
          notificationFields: [{ label: "Customer email", value: "historical@example.com" }],
        }),
      ]),
    });
  });

  it("previews a user's field mapping and activates the source without retaining the sample", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "My checkout" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(created.source.webhookUrl, {
        method: "POST",
        body: JSON.stringify({
          payment: { id: "txn_42", total: "27.00", currency: "usd", paid_at: "2026-08-11T06:20:00Z" },
          item: { name: "Download Pro", plan: "Annual" },
          kind: "new_subscription",
        }),
      }),
    );
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/total",
      amountUnit: "major",
      currencyPath: "/payment/currency",
      occurredAtPath: "/payment/paid_at",
      productPath: "/item/name",
      planPath: "/item/plan",
      saleTypePath: "/kind",
    };

    const preview = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );
    expect(await preview.json()).toEqual({
      preview: {
        paymentId: "txn_42",
        amountMinor: 2700,
        currency: "USD",
        occurredAt: "2026-08-11T06:20:00.000Z",
        productLabel: "Download Pro",
        plan: "Annual",
        saleType: "new_subscription",
        isSubscription: true,
      },
    });

    const staleActivate = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ...mapping, amountUnit: "minor" }),
      }),
    );
    expect(staleActivate.status).toBe(409);

    const activate = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );
    expect((await activate.json<{ source: { status: string; connectionState: string } }>()).source).toEqual(
      expect.objectContaining({ status: "active", connectionState: "active" }),
    );
    const check = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}`),
    );
    expect((await check.json<{ sample: unknown }>()).sample).toBeNull();
  });

  it("sends the exact setup preview to the owner's registered iPhone without creating a payment", async () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    Object.assign(env, {
      APNS_KEY_ID: "TESTKEY",
      APPLE_TEAM_ID: "TESTTEAM",
      APNS_BUNDLE_ID: "com.example.chaching",
      APNS_PRIVATE_KEY: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
    });
    await env.DB.prepare(
      `INSERT INTO device_tokens (id, user_id, device_id, token, environment, status)
       VALUES ('device-preview', 'user-one', 'iphone-preview', 'preview-token', 'production', 'active')`,
    ).run();
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "My checkout" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify({
        payment: { id: "txn_test", total: "27.00", currency: "USD" },
        item: { name: "Download Pro" },
      }),
    }));
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/total",
      amountUnit: "major",
      currencyPath: "/payment/currency",
      productPath: "/item/name",
      notificationFields: [
        { id: "product", path: "/item/name", label: "Product", enabled: true },
        { id: "amount", path: "/payment/total", label: "Amount", enabled: true },
      ],
    };
    await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );
    const requests: Array<{ url: string; body: unknown }> = [];
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({ url: String(input), body: JSON.parse(String(init?.body)) });
      return new Response(null, { status: 200 });
    }));

    const response = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/test-notification`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ sent: 1 });
    expect(requests).toEqual([{
      url: "https://api.push.apple.com/3/device/preview-token",
      body: {
        aps: {
          alert: { title: "Cha-ching!", body: "Product: Download Pro\nAmount: $27.00" },
          sound: "cash-register.caf",
        },
        testNotification: true,
      },
    }]);
    const history = await listSales(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/sales"),
    );
    expect(await history.json()).toEqual({ sales: [] });
    expect(sent).toEqual([]);
  });

  it("tests an active source with its draft presentation and latest payment values", async () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    Object.assign(env, {
      APNS_KEY_ID: "TESTKEY",
      APPLE_TEAM_ID: "TESTTEAM",
      APNS_BUNDLE_ID: "com.example.chaching",
      APNS_PRIVATE_KEY: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
    });
    await env.DB.prepare(
      `INSERT INTO device_tokens (id, user_id, device_id, token, environment, status)
       VALUES ('device-active-preview', 'user-one', 'iphone-active-preview', 'active-preview-token', 'production', 'active')`,
    ).run();
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "My checkout" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/amount_minor",
      amountUnit: "minor",
      currencyPath: "/payment/currency",
      notificationFields: [
        { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: true },
        { id: "buyer", path: "/buyer/email", label: "Buyer", enabled: true },
      ],
    };
    await env.DB.prepare(
      "UPDATE custom_payment_sources SET status = 'active', mapping_json = ?1 WHERE id = ?2",
    ).bind(JSON.stringify(mapping), created.source.id).run();
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify({
        payment: { id: "latest-payment", amount_minor: 1200, currency: "USD" },
        buyer: { email: "buyer@example.com" },
      }),
    }));
    const draft = {
      ...mapping,
      notificationFields: [
        { id: "buyer", path: "/buyer/email", label: "Customer email", enabled: true },
        { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: false },
      ],
    };
    const requests: Array<{ url: string; body: unknown }> = [];
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      requests.push({ url: String(input), body: JSON.parse(String(init?.body)) });
      return new Response(null, { status: 200 });
    }));

    const response = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/test-notification`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(draft),
      }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ sent: 1 });
    expect(requests).toEqual([{
      url: "https://api.push.apple.com/3/device/active-preview-token",
      body: {
        aps: {
          alert: { title: "Cha-ching!", body: "Customer email: buyer@example.com" },
          sound: "cash-register.caf",
        },
        testNotification: true,
      },
    }]);
  });

  it("queues the exact setup preview for a delayed lock-screen test without creating a payment", async () => {
    await env.DB.prepare(
      `INSERT INTO device_tokens (id, user_id, device_id, token, environment, status)
       VALUES ('device-lock', 'user-one', 'iphone-lock', 'lock-token', 'production', 'active')`,
    ).run();
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "My checkout" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify({
        payment: { id: "txn_lock", total: "27.00", currency: "USD" },
        item: { name: "Download Pro" },
      }),
    }));
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/total",
      amountUnit: "major",
      currencyPath: "/payment/currency",
      notificationFields: [
        { id: "product", path: "/item/name", label: "Product", enabled: true },
        { id: "amount", path: "/payment/total", label: "Amount", enabled: true },
      ],
    };
    await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );
    const response = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/test-notification`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ mapping, delaySeconds: 8 }),
      }),
    );

    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ scheduled: true, delaySeconds: 8, registered: 1 });
    expect(queueSends).toEqual([{
      message: {
        testNotification: {
          userId: "user-one",
          body: "Product: Download Pro\nAmount: $27.00",
        },
      },
      options: { delaySeconds: 8 },
    }]);
    const history = await listSales(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/sales"),
    );
    expect(await history.json()).toEqual({ sales: [] });
  });

  it("previews the ordered SERP Store business fields as one structured line each", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "SERP Store" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify({
        payment: {
          id: "cs_live_123",
          amount_minor: 900,
          currency: "USD",
          occurred_at: "2026-08-11T08:27:14Z",
        },
        buyer: { email: "buyer@example.com", checkout_country_ip: "JP" },
        purchase: {
          product: "Circle Video Downloader",
          entitlement: "circle-video-downloader",
          purchase_type: "subscription",
          sale_event: "new_sale",
        },
        attribution: {
          dub_affiliate_id: "pn_hasanul",
          utm_source: "dub",
          utm_medium: "affiliate",
          utm_campaign: "summer-launch",
          utm_term: "video downloader",
          utm_content: "pricing-page",
        },
        source: { store: "serp.store" },
      }),
    }));
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/amount_minor",
      amountUnit: "minor",
      currencyPath: "/payment/currency",
      occurredAtPath: "/payment/occurred_at",
      productPath: "/purchase/product",
      saleTypePath: "/purchase/sale_event",
      notificationFields: [
        { id: "buyer-email", path: "/buyer/email", label: "Buyer Email", enabled: true },
        { id: "country", path: "/buyer/checkout_country_ip", label: "Checkout Country (IP)", enabled: true },
        { id: "product", path: "/purchase/product", label: "Product", enabled: true },
        { id: "entitlement", path: "/purchase/entitlement", label: "Entitlement", enabled: true },
        { id: "purchase-type", path: "/purchase/purchase_type", label: "Purchase Type", enabled: true },
        { id: "sale-event", path: "/purchase/sale_event", label: "Sale Event", enabled: true },
        { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: true },
        { id: "dub", path: "/attribution/dub_affiliate_id", label: "Dub Affiliate ID", enabled: true },
        { id: "utm-source", path: "/attribution/utm_source", label: "UTM Source", enabled: true },
        { id: "utm-medium", path: "/attribution/utm_medium", label: "UTM Medium", enabled: true },
        { id: "utm-campaign", path: "/attribution/utm_campaign", label: "UTM Campaign", enabled: true },
        { id: "utm-term", path: "/attribution/utm_term", label: "UTM Term", enabled: true },
        { id: "utm-content", path: "/attribution/utm_content", label: "UTM Content", enabled: true },
        { id: "paid-at", path: "/payment/occurred_at", label: "Paid At", enabled: true },
        { id: "store", path: "/source/store", label: "Source Store", enabled: true },
      ],
    };

    const preview = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );

    expect(preview.status).toBe(200);
    expect((await preview.json<{ preview: unknown }>()).preview).toEqual(expect.objectContaining({
      notificationFields: [
        { id: "buyer-email", path: "/buyer/email", label: "Buyer Email", enabled: true, value: "buyer@example.com" },
        { id: "country", path: "/buyer/checkout_country_ip", label: "Checkout Country (IP)", enabled: true, value: "JP" },
        { id: "product", path: "/purchase/product", label: "Product", enabled: true, value: "Circle Video Downloader" },
        { id: "entitlement", path: "/purchase/entitlement", label: "Entitlement", enabled: true, value: "circle-video-downloader" },
        { id: "purchase-type", path: "/purchase/purchase_type", label: "Purchase Type", enabled: true, value: "Subscription" },
        { id: "sale-event", path: "/purchase/sale_event", label: "Sale Event", enabled: true, value: "New sale" },
        { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: true, value: "$9.00" },
        { id: "dub", path: "/attribution/dub_affiliate_id", label: "Dub Affiliate ID", enabled: true, value: "pn_hasanul" },
        { id: "utm-source", path: "/attribution/utm_source", label: "UTM Source", enabled: true, value: "dub" },
        { id: "utm-medium", path: "/attribution/utm_medium", label: "UTM Medium", enabled: true, value: "affiliate" },
        { id: "utm-campaign", path: "/attribution/utm_campaign", label: "UTM Campaign", enabled: true, value: "summer-launch" },
        { id: "utm-term", path: "/attribution/utm_term", label: "UTM Term", enabled: true, value: "video downloader" },
        { id: "utm-content", path: "/attribution/utm_content", label: "UTM Content", enabled: true, value: "pricing-page" },
        { id: "paid-at", path: "/payment/occurred_at", label: "Paid At", enabled: true, value: "2026-08-11T08:27:14.000Z" },
        { id: "store", path: "/source/store", label: "Source Store", enabled: true, value: "serp.store" },
      ],
      notificationBody: [
        "Buyer Email: buyer@example.com",
        "Checkout Country (IP): JP",
        "Product: Circle Video Downloader",
        "Entitlement: circle-video-downloader",
        "Purchase Type: Subscription",
        "Sale Event: New sale",
        "Amount: $9.00",
        "Dub Affiliate ID: pn_hasanul",
        "UTM Source: dub",
        "UTM Medium: affiliate",
        "UTM Campaign: summer-launch",
        "UTM Term: video downloader",
        "UTM Content: pricing-page",
        "Paid At: 2026-08-11T08:27:14.000Z",
        "Source Store: serp.store",
      ].join("\n"),
    }));
  });

  it("delivers the activated SERP Store business fields to APNs as separate ordered lines", async () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    Object.assign(env, {
      APNS_KEY_ID: "TESTKEY",
      APPLE_TEAM_ID: "TESTTEAM",
      APNS_BUNDLE_ID: "com.example.chaching",
      APNS_PRIVATE_KEY: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
    });
    await env.DB.prepare(
      `INSERT INTO device_tokens (id, user_id, device_id, token, environment, status)
       VALUES ('device-custom-fields', 'user-one', 'iphone-custom-fields', 'apns-token', 'production', 'active')`,
    ).run();
    const create = await handleCustomSourceRequest(env, authFor("user-one"), new Request(
      "https://api.cha-ching.test/v1/custom-sources",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "SERP Store" }),
      },
    ));
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const payment = {
      payment: {
        id: "serp-order-123",
        amount_minor: 900,
        currency: "USD",
        occurred_at: "2026-08-11T08:27:14Z",
      },
      buyer: { email: "buyer@example.com", checkout_country_ip: "JP" },
      purchase: {
        product: "Circle Video Downloader",
        entitlement: "circle-video-downloader",
        purchase_type: "subscription",
        sale_event: "new_sale",
      },
      attribution: {
        dub_affiliate_id: "pn_hasanul",
        utm_source: "dub",
        utm_medium: "affiliate",
        utm_campaign: "summer-launch",
        utm_term: "video downloader",
        utm_content: "pricing-page",
      },
      source: { store: "serp.store" },
    };
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/amount_minor",
      amountUnit: "minor",
      currencyPath: "/payment/currency",
      occurredAtPath: "/payment/occurred_at",
      productPath: "/purchase/product",
      saleTypePath: "/purchase/sale_event",
      notificationFields: [
        { id: "buyer-email", path: "/buyer/email", label: "Buyer Email", enabled: true },
        { id: "country", path: "/buyer/checkout_country_ip", label: "Checkout Country (IP)", enabled: true },
        { id: "product", path: "/purchase/product", label: "Product", enabled: true },
        { id: "entitlement", path: "/purchase/entitlement", label: "Entitlement", enabled: true },
        { id: "purchase-type", path: "/purchase/purchase_type", label: "Purchase Type", enabled: true },
        { id: "sale-event", path: "/purchase/sale_event", label: "Sale Event", enabled: true },
        { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: true },
        { id: "dub", path: "/attribution/dub_affiliate_id", label: "Dub Affiliate ID", enabled: true },
        { id: "utm-source", path: "/attribution/utm_source", label: "UTM Source", enabled: true },
        { id: "utm-medium", path: "/attribution/utm_medium", label: "UTM Medium", enabled: true },
        { id: "utm-campaign", path: "/attribution/utm_campaign", label: "UTM Campaign", enabled: true },
        { id: "utm-term", path: "/attribution/utm_term", label: "UTM Term", enabled: true },
        { id: "utm-content", path: "/attribution/utm_content", label: "UTM Content", enabled: true },
        { id: "paid-at", path: "/payment/occurred_at", label: "Paid At", enabled: true },
        { id: "store", path: "/source/store", label: "Source Store", enabled: true },
      ],
    };
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify(payment),
    }));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(
      `https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`,
      { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(mapping) },
    ));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(
      `https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`,
      { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(mapping) },
    ));

    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify(payment),
    }));
    expect(sent).toHaveLength(1);
    const apnsBodies: unknown[] = [];
    vi.stubGlobal("fetch", vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      apnsBodies.push(JSON.parse(String(init?.body)));
      return new Response(null, { status: 200 });
    }));
    const ack = vi.fn();
    await processNotificationBatch(env, {
      messages: [{ body: sent[0], ack, retry: vi.fn() }],
    } as unknown as MessageBatch<{ saleId: string }>);

    expect(apnsBodies).toEqual([
      expect.objectContaining({
        aps: expect.objectContaining({
          alert: {
            title: "Cha-ching!",
            body: [
              "Buyer Email: buyer@example.com",
              "Checkout Country (IP): JP",
              "Product: Circle Video Downloader",
              "Entitlement: circle-video-downloader",
              "Purchase Type: Subscription",
              "Sale Event: New sale",
              "Amount: $9.00",
              "Dub Affiliate ID: pn_hasanul",
              "UTM Source: dub",
              "UTM Medium: affiliate",
              "UTM Campaign: summer-launch",
              "UTM Term: video downloader",
              "UTM Content: pricing-page",
              "Paid At: 2026-08-11T08:27:14.000Z",
              "Source Store: serp.store",
            ].join("\n"),
          },
          sound: "cash-register.caf",
        }),
      }),
    ]);
    expect(ack).toHaveBeenCalledOnce();

    const history = await listSales(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/sales"),
    );
    expect(await history.json()).toEqual({
      sales: [expect.objectContaining({
        notificationFields: [
          { label: "Buyer Email", value: "buyer@example.com" },
          { label: "Checkout Country (IP)", value: "JP" },
          { label: "Product", value: "Circle Video Downloader" },
          { label: "Entitlement", value: "circle-video-downloader" },
          { label: "Purchase Type", value: "Subscription" },
          { label: "Sale Event", value: "New sale" },
          { label: "Amount", value: "$9.00" },
          { label: "Dub Affiliate ID", value: "pn_hasanul" },
          { label: "UTM Source", value: "dub" },
          { label: "UTM Medium", value: "affiliate" },
          { label: "UTM Campaign", value: "summer-launch" },
          { label: "UTM Term", value: "video downloader" },
          { label: "UTM Content", value: "pricing-page" },
          { label: "Paid At", value: "2026-08-11T08:27:14.000Z" },
          { label: "Source Store", value: "serp.store" },
        ],
      })],
    });
  });

  it("accepts a real payment when optional notification fields from the setup sample are absent", async () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    Object.assign(env, {
      APNS_KEY_ID: "TESTKEY",
      APPLE_TEAM_ID: "TESTTEAM",
      APNS_BUNDLE_ID: "com.example.chaching",
      APNS_PRIVATE_KEY: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
    });
    await env.DB.prepare(
      `INSERT INTO device_tokens (id, user_id, device_id, token, environment, status)
       VALUES ('device-optional-fields', 'user-one', 'iphone-optional-fields', 'optional-fields-token', 'production', 'active')`,
    ).run();
    const create = await handleCustomSourceRequest(env, authFor("user-one"), new Request(
      "https://api.cha-ching.test/v1/custom-sources",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "SERP Store" }),
      },
    ));
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const setupSample = {
      payment: { id: "setup-payment", amount_minor: 2700, currency: "USD" },
      buyer: { email: "setup@example.com" },
      attribution: { utm_source: "newsletter", utm_campaign: "launch" },
    };
    const mapping = {
      paymentIdPath: "/payment/id",
      amountPath: "/payment/amount_minor",
      amountUnit: "minor",
      currencyPath: "/payment/currency",
      notificationFields: [
        { id: "buyer-email", path: "/buyer/email", label: "Buyer Email", enabled: true },
        { id: "amount", path: "/payment/amount_minor", label: "Amount", enabled: true },
        { id: "utm-source", path: "/attribution/utm_source", label: "UTM Source", enabled: true },
        { id: "utm-campaign", path: "/attribution/utm_campaign", label: "UTM Campaign", enabled: true },
      ],
    };
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify(setupSample),
    }));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(
      `https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`,
      { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(mapping) },
    ));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(
      `https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`,
      { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(mapping) },
    ));

    const livePayment = {
      payment: { id: "real-payment-without-attribution", amount_minor: 2700, currency: "USD" },
      buyer: { email: "buyer@example.com" },
    };
    const response = await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify(livePayment),
    }));

    expect(response.status).toBe(202);
    expect(sent).toHaveLength(1);
    if (sent.length !== 1) return;
    const apnsBodies: unknown[] = [];
    vi.stubGlobal("fetch", vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      apnsBodies.push(JSON.parse(String(init?.body)));
      return new Response(null, { status: 200 });
    }));
    await processNotificationBatch(env, {
      messages: [{ body: sent[0], ack: vi.fn(), retry: vi.fn() }],
    } as unknown as MessageBatch<{ saleId: string }>);

    expect(apnsBodies).toEqual([
      expect.objectContaining({
        aps: expect.objectContaining({
          alert: {
            title: "Cha-ching!",
            body: [
              "Buyer Email: buyer@example.com",
              "Amount: $27.00",
            ].join("\n"),
          },
        }),
      }),
    ]);
    const history = await listSales(env, authFor("user-one"), new Request("https://api.cha-ching.test/v1/sales"));
    expect((await history.json<{ sales: unknown[] }>()).sales).toHaveLength(1);
  });

  it("rejects unsafe numeric payment IDs with guidance to map a lossless string field", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "Numeric IDs" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const mapping = {
      paymentIdPath: "/id",
      amountPath: "/amount",
      amountUnit: "minor",
      currencyPath: "/currency",
    };

    for (const rawId of ["9007199254740992", "9007199254740993"]) {
      await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
        method: "POST",
        body: `{"id":${rawId},"amount":100,"currency":"USD"}`,
      }));
      const preview = await handleCustomSourceRequest(
        env,
        authFor("user-one"),
        new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(mapping),
        }),
      );
      expect(preview.status).toBe(422);
      expect(await preview.json()).toEqual({
        error: "Mapped payment ID is too large to preserve exactly. Send it as a JSON string or map a string field.",
      });
    }

    for (const [rawId, expectedId] of [["42", "42"], ['"9007199254740993"', "9007199254740993"]]) {
      await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
        method: "POST",
        body: `{"id":${rawId},"amount":100,"currency":"USD"}`,
      }));
      const preview = await handleCustomSourceRequest(
        env,
        authFor("user-one"),
        new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(mapping),
        }),
      );
      expect(preview.status).toBe(200);
      expect((await preview.json<{ preview: { paymentId: string } }>()).preview.paymentId).toBe(expectedId);
    }
  });

  it("turns an active mapped payment into one history item and one notification across retries", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "SERP Store" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const payment = {
      order: { id: "order_123" },
      payment: { amount: 2700, currency: "USD" },
      product: "Download Pro",
    };
    const mapping = {
      paymentIdPath: "/order/id",
      amountPath: "/payment/amount",
      amountUnit: "minor",
      currencyPath: "/payment/currency",
      productPath: "/product",
    };
    await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(created.source.webhookUrl, { method: "POST", body: JSON.stringify(payment) }),
    );
    await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );
    await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );

    for (let attempt = 0; attempt < 2; attempt += 1) {
      const response = await handleCustomSourceRequest(
        env,
        authFor("user-two"),
        new Request(created.source.webhookUrl, { method: "POST", body: JSON.stringify(payment) }),
      );
      expect(response.status).toBe(202);
    }

    const history = await listSales(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/sales"),
    );
    expect(await history.json()).toEqual({
      sales: [expect.objectContaining({
        provider: "custom",
        amountMinor: 2700,
        currency: "USD",
        productLabel: "Download Pro",
      })],
    });
    expect(sent).toHaveLength(1);
  });

  it("reclaims a stale pre-send queue claim when the custom sender retries the payment", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "Crash recovery" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const payment = { id: "custom-claim-retry", amount: 3400, currency: "USD" };
    const mapping = {
      paymentIdPath: "/id",
      amountPath: "/amount",
      amountUnit: "minor",
      currencyPath: "/currency",
    };
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify(payment),
    }));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(mapping),
    }));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(mapping),
    }));
    const paymentFingerprint = await sha256(`${created.source.id}\u0000${payment.id}`);
    const scopedPaymentId = `${created.source.id}:${paymentFingerprint}`;
    const saleId = `custom:${scopedPaymentId}`;
    await env.DB.prepare(
      `INSERT INTO sales (
        id, user_id, provider, provider_account_id, provider_event_id,
        provider_payment_id, amount_minor, currency, product_label,
        is_subscription, occurred_at, notification_queued_at,
        notification_queue_state, notification_queue_claimed_at
      ) VALUES (?1, 'user-one', 'custom', ?2, ?3, ?3, 3400, 'USD',
        'Crash recovery', 0, 7, datetime('now', '-10 minutes'), 'claimed',
        datetime('now', '-10 minutes'))`,
    ).bind(saleId, created.source.id, scopedPaymentId).run();

    const retry = await handleCustomSourceRequest(env, authFor("user-two"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify(payment),
    }));

    expect(retry.status).toBe(202);
    expect(sent).toEqual([{ saleId }]);
    const sale = await env.DB.prepare(
      "SELECT notification_queue_state, notification_queue_claimed_at FROM sales WHERE id = ?1",
    ).bind(saleId).first<{ notification_queue_state: string; notification_queue_claimed_at: string | null }>();
    expect(sale).toEqual({ notification_queue_state: "accepted", notification_queue_claimed_at: null });
  });

  it("keeps distinct long payment IDs distinct when their first 200 characters match", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "Long IDs" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const sharedPrefix = "x".repeat(250);
    const first = { id: `${sharedPrefix}-first`, amount: 100, currency: "USD" };
    const second = { id: `${sharedPrefix}-second`, amount: 200, currency: "USD" };
    const mapping = {
      paymentIdPath: "/id",
      amountPath: "/amount",
      amountUnit: "minor",
      currencyPath: "/currency",
    };
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
      method: "POST",
      body: JSON.stringify(first),
    }));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(mapping),
    }));
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(mapping),
    }));

    for (const payment of [first, second]) {
      const response = await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, {
        method: "POST",
        body: JSON.stringify(payment),
      }));
      expect(response.status).toBe(202);
    }

    const history = await listSales(env, authFor("user-one"), new Request("https://api.cha-ching.test/v1/sales"));
    expect((await history.json<{ sales: unknown[] }>()).sales).toHaveLength(2);
    expect(sent).toHaveLength(2);
  });

  it("pauses new payments without losing the source, then resumes it", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "My store" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const sample = { id: "setup", total: 10, currency: "USD" };
    const mapping = {
      paymentIdPath: "/id",
      amountPath: "/total",
      amountUnit: "minor",
      currencyPath: "/currency",
    };
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(created.source.webhookUrl, { method: "POST", body: JSON.stringify(sample) }));
    await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/mapping`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(mapping),
      }),
    );
    await handleCustomSourceRequest(env, authFor("user-one"), new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/activate`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(mapping),
    }));

    const pause = await handleCustomSourceRequest(env, authFor("user-one"), new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/pause`, { method: "POST" }));
    expect((await pause.json<{ source: { status: string; webhookUrl: string } }>()).source).toEqual(expect.objectContaining({ status: "paused", webhookUrl: created.source.webhookUrl }));
    const ignored = await handleCustomSourceRequest(env, authFor("user-two"), new Request(created.source.webhookUrl, { method: "POST", body: JSON.stringify({ ...sample, id: "while-paused" }) }));
    expect(await ignored.json()).toEqual({ received: true, ignored: "paused" });

    const resume = await handleCustomSourceRequest(env, authFor("user-one"), new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/resume`, { method: "POST" }));
    expect((await resume.json<{ source: { status: string; webhookUrl: string } }>()).source).toEqual(expect.objectContaining({ status: "active", webhookUrl: created.source.webhookUrl }));
    await handleCustomSourceRequest(env, authFor("user-two"), new Request(created.source.webhookUrl, { method: "POST", body: JSON.stringify({ ...sample, id: "after-resume" }) }));

    const history = await listSales(env, authFor("user-one"), new Request("https://api.cha-ching.test/v1/sales"));
    const body = await history.json<{ sales: Array<{ id: string }> }>();
    expect(body.sales).toHaveLength(1);
    expect(sent).toHaveLength(1);
  });

  it("regenerates a URL only for its owner and immediately invalidates the old URL", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "Private store" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();

    const forbidden = await handleCustomSourceRequest(
      env,
      authFor("user-two"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/regenerate`, { method: "POST" }),
    );
    expect(forbidden.status).toBe(404);

    const regenerated = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}/regenerate`, { method: "POST" }),
    );
    const replacement = await regenerated.json<{ source: { webhookUrl: string } }>();
    expect(replacement.source.webhookUrl).not.toBe(created.source.webhookUrl);
    const oldURL = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(created.source.webhookUrl, { method: "POST", body: JSON.stringify({ id: "old", total: 1 }) }),
    );
    expect(oldURL.status).toBe(404);
    const newURL = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(replacement.source.webhookUrl, { method: "POST", body: JSON.stringify({ id: "new", total: 1 }) }),
    );
    expect(newURL.status).toBe(202);
  });

  it("records a safe setup error when a sender posts malformed JSON", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "Broken sender" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const malformed = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(created.source.webhookUrl, { method: "POST", body: "{not-json" }),
    );
    expect(malformed.status).toBe(400);
    const check = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}`),
    );
    expect((await check.json<{ sample: unknown }>()).sample).toEqual({ error: "Invalid JSON" });
  });

  it("rejects an oversized setup payload without creating a sample", async () => {
    const create = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/custom-sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name: "Large sender" }),
      }),
    );
    const created = await create.json<{ source: { id: string; webhookUrl: string } }>();
    const oversized = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(created.source.webhookUrl, {
        method: "POST",
        headers: { "content-length": "70000" },
        body: "{}",
      }),
    );
    expect(oversized.status).toBe(413);
    const check = await handleCustomSourceRequest(
      env,
      authFor("user-one"),
      new Request(`https://api.cha-ching.test/v1/custom-sources/${created.source.id}`),
    );
    expect((await check.json<{ sample: unknown }>()).sample).toBeNull();
  });
});
