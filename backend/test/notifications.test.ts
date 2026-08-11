import { generateKeyPairSync } from "node:crypto";

import { Miniflare } from "miniflare";
import { vi } from "vitest";
import { describe, expect, it } from "vitest";

import type { Env } from "../src/env";
import {
  currencyExponent,
  formatMinorAmount,
  notificationBody,
  processNotificationBatch,
  shouldRetryUnclaimedDelivery,
} from "../src/notifications";

describe("notification amount formatting", () => {
  it("formats two-decimal, zero-decimal, and three-decimal currencies", () => {
    expect(currencyExponent("USD")).toBe(2);
    expect(formatMinorAmount(1999, "USD")).toBe("$19.99");
    expect(currencyExponent("JPY")).toBe(0);
    expect(formatMinorAmount(1999, "JPY")).toContain("1,999");
    expect(currencyExponent("KWD")).toBe(3);
    expect(formatMinorAmount(1999, "KWD")).toContain("1.999");
  });
});

describe("custom payment notification", () => {
  it("includes the optional fields the user mapped", () => {
    expect(notificationBody({
      amount_minor: 2700,
      currency: "USD",
      provider: "custom",
      product_label: "Download Pro",
      plan_label: "Annual",
      sale_type_label: "New subscription",
    })).toBe("You received $27.00 for Download Pro. Annual · New subscription");
  });
});

describe("delivery recovery", () => {
  it("keeps an unclaimed in-progress delivery on the queue until it can be reclaimed", () => {
    expect(shouldRetryUnclaimedDelivery("sending")).toBe(true);
    expect(shouldRetryUnclaimedDelivery("sent")).toBe(false);
    expect(shouldRetryUnclaimedDelivery("failed")).toBe(false);
  });

  it("delivers a delayed lock-screen test through APNs without a sale", async () => {
    const miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    try {
      const db = await miniflare.getD1Database("DB");
      await db.prepare(
        `CREATE TABLE device_tokens (
          id TEXT PRIMARY KEY, user_id TEXT, token TEXT, environment TEXT, status TEXT,
          updated_at TEXT
        )`,
      ).run();
      await db.prepare(
        "INSERT INTO device_tokens VALUES ('device-lock', 'owner', 'apns-token', 'production', 'active', CURRENT_TIMESTAMP)",
      ).run();
      const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
      const requests: Array<{ url: string; body: unknown }> = [];
      vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        requests.push({ url: String(input), body: JSON.parse(String(init?.body)) });
        return new Response(null, { status: 200 });
      }));
      const env = {
        DB: db,
        APNS_KEY_ID: "TESTKEY",
        APPLE_TEAM_ID: "TESTTEAM",
        APNS_BUNDLE_ID: "com.example.chaching",
        APNS_PRIVATE_KEY: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
      } as unknown as Env;
      const ack = vi.fn();
      const retry = vi.fn();
      const message = {
        body: {
          testNotification: {
            userId: "owner",
            body: "Product: Download Pro\nAmount: $27.00",
          },
        },
        ack,
        retry,
      };

      await processNotificationBatch(env, { messages: [message] } as unknown as MessageBatch<never>);

      expect(requests).toEqual([{
        url: "https://api.push.apple.com/3/device/apns-token",
        body: {
          aps: {
            alert: { title: "Cha-ching!", body: "Product: Download Pro\nAmount: $27.00" },
            sound: "cash-register.caf",
          },
          testNotification: true,
        },
      }]);
      expect(ack).toHaveBeenCalledOnce();
      expect(retry).not.toHaveBeenCalled();
    } finally {
      vi.unstubAllGlobals();
      await miniflare.dispose();
    }
  });

  it("reuses the persisted delivery ID and makes duplicate Queue messages one visible delivery", async () => {
    const miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    try {
      const db = await miniflare.getD1Database("DB");
      await db.prepare(
        `CREATE TABLE sales (
          id TEXT PRIMARY KEY, user_id TEXT, amount_minor INTEGER, currency TEXT,
          provider TEXT, product_label TEXT, plan_label TEXT, sale_type_label TEXT,
          status TEXT, notification_fields_json TEXT
        )`,
      ).run();
      await db.prepare(
        `CREATE TABLE device_tokens (
          id TEXT PRIMARY KEY, user_id TEXT, token TEXT, environment TEXT, status TEXT,
          updated_at TEXT
        )`,
      ).run();
      await db.prepare(
        `CREATE TABLE notification_deliveries (
          id TEXT PRIMARY KEY, sale_id TEXT, device_token_id TEXT, status TEXT,
          attempt_count INTEGER DEFAULT 0, apns_id TEXT, error_code TEXT,
          last_attempt_at TEXT, sent_at TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(sale_id, device_token_id)
        )`,
      ).run();
      await db.prepare(
        "INSERT INTO sales VALUES ('sale-stable', 'owner', 2700, 'USD', 'stripe', 'Stripe payment', NULL, NULL, 'succeeded', NULL)",
      ).run();
      await db.prepare(
        "INSERT INTO device_tokens VALUES ('device-stable', 'owner', 'apns-token', 'production', 'active', CURRENT_TIMESTAMP)",
      ).run();
      await db.prepare(
        `INSERT INTO notification_deliveries (
          id, sale_id, device_token_id, status, attempt_count
        ) VALUES ('delivery-stable', 'sale-stable', 'device-stable', 'retry', 1)`,
      ).run();
      const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
      const apnsIds: Array<string | null> = [];
      vi.stubGlobal("fetch", vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
        apnsIds.push(new Headers(init?.headers).get("apns-id"));
        return new Response(null, { status: 200 });
      }));
      const env = {
        DB: db,
        APNS_KEY_ID: "TESTKEY",
        APPLE_TEAM_ID: "TESTTEAM",
        APNS_BUNDLE_ID: "com.example.chaching",
        APNS_PRIVATE_KEY: privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
      } as unknown as Env;
      const ack = vi.fn();
      const retry = vi.fn();
      const message = { body: { saleId: "sale-stable" }, ack, retry };

      await processNotificationBatch(env, { messages: [message] } as unknown as MessageBatch<{ saleId: string }>);
      await processNotificationBatch(env, { messages: [message] } as unknown as MessageBatch<{ saleId: string }>);

      expect(apnsIds).toEqual(["delivery-stable"]);
      expect(ack).toHaveBeenCalledTimes(2);
      expect(retry).not.toHaveBeenCalled();
    } finally {
      vi.unstubAllGlobals();
      await miniflare.dispose();
    }
  });
});
