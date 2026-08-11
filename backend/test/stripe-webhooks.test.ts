import { describe, expect, it } from "vitest";

import {
  normalizeStripeSale,
  stripeSignature,
  verifyStripeSignature,
} from "../src/stripe-webhooks";

describe("Stripe webhook verification", () => {
  it("accepts a current valid v1 signature", async () => {
    const payload = JSON.stringify({ id: "evt_123" });
    const timestamp = 1_700_000_000;
    const signature = await stripeSignature(payload, timestamp, "whsec_test");
    await expect(
      verifyStripeSignature(payload, `t=${timestamp},v1=${signature}`, "whsec_test", timestamp),
    ).resolves.toBe(true);
  });

  it("rejects changed payloads and stale timestamps", async () => {
    const payload = JSON.stringify({ id: "evt_123" });
    const timestamp = 1_700_000_000;
    const signature = await stripeSignature(payload, timestamp, "whsec_test");
    await expect(
      verifyStripeSignature(`${payload} `, `t=${timestamp},v1=${signature}`, "whsec_test", timestamp),
    ).resolves.toBe(false);
    await expect(
      verifyStripeSignature(payload, `t=${timestamp},v1=${signature}`, "whsec_test", timestamp + 301),
    ).resolves.toBe(false);
  });
});

describe("Stripe sale normalization", () => {
  it("normalizes a connected-account successful charge without customer PII", () => {
    expect(
      normalizeStripeSale({
        id: "evt_sale",
        type: "charge.succeeded",
        account: "acct_connected",
        livemode: false,
        data: {
          object: {
            id: "ch_sale",
            amount: 1999,
            currency: "usd",
            created: 1_700_000_000,
            description: "private customer note",
            invoice: "in_subscription",
            billing_details: {
              email: "private@example.com",
              address: { country: "jp" },
            },
          },
        },
      }),
    ).toEqual({
      providerEventId: "evt_sale",
      providerPaymentId: "ch_sale",
      providerAccountId: "acct_connected",
      amountMinor: 1999,
      currency: "USD",
      productLabel: "Stripe payment",
      countryCode: "JP",
      isSubscription: true,
      occurredAt: 1_700_000_000,
      livemode: false,
    });
  });

  it("ignores non-charge events and events without a connected account", () => {
    expect(
      normalizeStripeSale({ id: "evt_1", type: "payment_intent.succeeded", livemode: false, data: { object: {} } }),
    ).toBeNull();
    expect(
      normalizeStripeSale({
        id: "evt_2",
        type: "charge.succeeded",
        livemode: false,
        data: { object: { id: "ch_1", amount: 100, currency: "usd", created: 1 } },
      }),
    ).toBeNull();
  });
});
