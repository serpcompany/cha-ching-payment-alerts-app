import { Miniflare } from "miniflare";
import { describe, expect, it, vi } from "vitest";

import { classifyCustomSourceHealth, monitorCustomSourceHealth } from "../src/custom-source-health";
import type { Env } from "../src/env";

describe("custom source health", () => {
  const now = new Date("2026-08-12T12:00:00Z");

  it("warns immediately when the latest webhook request was rejected", () => {
    expect(classifyCustomSourceHealth({
      status: "active",
      lastEventReceivedAt: "2026-08-12 11:59:00",
      lastEventStatus: "rejected",
      lastEventError: "Mapped amount is missing",
      lastPaymentReceivedAt: "2026-08-12 10:00:00",
      recentPaymentTimes: [],
      now,
    })).toEqual({
      status: "needs_attention",
      reason: "rejected",
      lastEventReceivedAt: "2026-08-12 11:59:00",
      lastPaymentReceivedAt: "2026-08-12 10:00:00",
      expectedEventBy: null,
      detail: "Mapped amount is missing",
    });
  });

  it("reports receiving after later accepted webhook evidence", () => {
    const result = classifyCustomSourceHealth({
      status: "active",
      lastEventReceivedAt: "2026-08-12 12:00:00",
      lastEventStatus: "accepted",
      lastEventError: null,
      lastPaymentReceivedAt: "2026-08-12 12:00:00",
      recentPaymentTimes: ["2026-08-12 12:00:00"],
      now,
    });

    expect(result).toEqual({
      status: "receiving",
      reason: null,
      lastEventReceivedAt: "2026-08-12 12:00:00",
      lastPaymentReceivedAt: "2026-08-12 12:00:00",
      expectedEventBy: null,
      detail: "Cha-Ching received a webhook event.",
    });
  });

  it("flags an established source after its adaptive activity window passes", () => {
    const result = classifyCustomSourceHealth({
      status: "active",
      lastEventReceivedAt: "2026-08-12 05:00:00",
      lastEventStatus: "accepted",
      lastEventError: null,
      lastPaymentReceivedAt: "2026-08-12 05:00:00",
      recentPaymentTimes: [
        "2026-08-12 05:00:00",
        "2026-08-12 04:30:00",
        "2026-08-12 04:00:00",
      ],
      now,
    });

    expect(result).toEqual({
      status: "needs_attention",
      reason: "quiet",
      lastEventReceivedAt: "2026-08-12 05:00:00",
      lastPaymentReceivedAt: "2026-08-12 05:00:00",
      expectedEventBy: "2026-08-12T11:00:00.000Z",
      detail: "No webhook requests arrived within this source's expected activity window. This does not prove the sender is disconnected; check it if you expected payments.",
    });
  });

  it("does not infer a broken connection before it has enough payment history", () => {
    expect(classifyCustomSourceHealth({
      status: "active",
      lastEventReceivedAt: "2026-08-01 05:00:00",
      lastEventStatus: "accepted",
      lastEventError: null,
      lastPaymentReceivedAt: "2026-08-01 05:00:00",
      recentPaymentTimes: ["2026-08-01 05:00:00"],
      now,
    }).status).toBe("receiving");
  });

  it("queues one connection warning for a quiet established source", async () => {
    const miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      d1Databases: ["DB"],
    });
    try {
      const db = await miniflare.getD1Database("DB");
      await db.prepare(
        `CREATE TABLE custom_payment_sources (
          id TEXT PRIMARY KEY, user_id TEXT, name TEXT, status TEXT,
          last_event_received_at TEXT, last_event_status TEXT, last_event_error TEXT,
          last_payment_received_at TEXT, health_alerted_at TEXT
        )`,
      ).run();
      await db.prepare(
        `CREATE TABLE sales (
          id TEXT PRIMARY KEY, provider TEXT, provider_account_id TEXT, created_at TEXT
        )`,
      ).run();
      await db.prepare(
        `INSERT INTO custom_payment_sources VALUES (
          'source-quiet', 'owner', 'SERP Store', 'active', '2026-08-12 05:00:00',
          'accepted', NULL, '2026-08-12 05:00:00', NULL
        )`,
      ).run();
      for (const [id, createdAt] of [
        ["sale-1", "2026-08-12 05:00:00"],
        ["sale-2", "2026-08-12 04:30:00"],
        ["sale-3", "2026-08-12 04:00:00"],
      ]) {
        await db.prepare("INSERT INTO sales VALUES (?1, 'custom', 'source-quiet', ?2)")
          .bind(id, createdAt).run();
      }
      const send = vi.fn(async () => undefined);
      const env = { DB: db, NOTIFICATION_QUEUE: { send } } as unknown as Env;

      await monitorCustomSourceHealth(env, now);
      await monitorCustomSourceHealth(env, now);

      expect(send).toHaveBeenCalledOnce();
      expect(send).toHaveBeenCalledWith({
        connectionHealth: {
          userId: "owner",
          sourceId: "source-quiet",
          sourceName: "SERP Store",
          body: "No webhook requests arrived within this source's expected activity window. Open Cha-Ching to review the connection.",
        },
      });
    } finally {
      await miniflare.dispose();
    }
  });
});
