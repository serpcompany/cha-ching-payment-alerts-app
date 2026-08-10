import { describe, expect, it } from "vitest";

import {
  flattenWebhookPayload,
  normalizeCustomPayment,
  type WebhookFieldMapping,
} from "../src/custom-webhooks";

describe("custom webhook field discovery", () => {
  it("turns an unfamiliar nested JSON payload into selectable scalar fields", () => {
    expect(
      flattenWebhookPayload({
        event: { id: "order_123", occurred_at: "2026-08-11T06:20:00Z" },
        payment: { total: "27.00", currency: "usd" },
        item: { product: "JustForFans Downloader", plan: "SERP App Pro" },
        ignored: { object: { too: "deep" } },
      }),
    ).toEqual([
      { path: "/event/id", value: "order_123", valueType: "string" },
      { path: "/event/occurred_at", value: "2026-08-11T06:20:00Z", valueType: "string" },
      { path: "/ignored/object/too", value: "deep", valueType: "string" },
      { path: "/item/plan", value: "SERP App Pro", valueType: "string" },
      { path: "/item/product", value: "JustForFans Downloader", valueType: "string" },
      { path: "/payment/currency", value: "usd", valueType: "string" },
      { path: "/payment/total", value: "27.00", valueType: "string" },
    ]);
  });

  it("returns every scalar field in a valid deeply nested sample", () => {
    const many = Object.fromEntries(
      Array.from({ length: 150 }, (_, index) => [`field_${index}`, index]),
    );
    let deep: Record<string, unknown> = { value: "found" };
    for (let level = 0; level < 20; level += 1) deep = { next: deep };

    const fields = flattenWebhookPayload({ many, deep });

    expect(fields).toHaveLength(151);
    expect(fields).toContainEqual({ path: "/many/field_149", value: 149, valueType: "number" });
    expect(fields).toContainEqual({
      path: `/deep${"/next".repeat(20)}/value`,
      value: "found",
      valueType: "string",
    });
  });
});

describe("custom webhook mapping", () => {
  const mapping: WebhookFieldMapping = {
    paymentIdPath: "/event/id",
    amountPath: "/payment/total",
    amountUnit: "major",
    currencyPath: "/payment/currency",
    occurredAtPath: "/event/occurred_at",
    productPath: "/item/product",
    planPath: "/item/plan",
    saleTypePath: "/event/type",
  };

  it("normalizes a provider-specific payload using the user's saved mapping", () => {
    expect(
      normalizeCustomPayment(
        {
          event: {
            id: "order_123",
            type: "new_subscription",
            occurred_at: "2026-08-11T06:20:00Z",
          },
          payment: { total: "27.00", currency: "usd" },
          item: { product: "JustForFans Downloader", plan: "SERP App Pro" },
        },
        mapping,
        "SERP Store",
      ),
    ).toEqual({
      paymentId: "order_123",
      amountMinor: 2700,
      currency: "USD",
      occurredAt: 1_786_429_200,
      productLabel: "JustForFans Downloader",
      isSubscription: true,
      details: {
        plan: "SERP App Pro",
        saleType: "new_subscription",
      },
    });
  });

  it("rejects a payment when a required mapped value is missing", () => {
    expect(() =>
      normalizeCustomPayment(
        { event: { id: "order_123" }, payment: { currency: "usd" } },
        mapping,
        "My store",
      ),
    ).toThrow("amount");
  });
});
