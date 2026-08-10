import { describe, expect, it } from "vitest";

import type { Env } from "../src/env";
import { authorizationURL } from "../src/providers";

const env = {
  PUBLIC_BASE_URL: "https://api.salesping.example",
  STRIPE_CONNECT_CLIENT_ID: "ca_test",
  PAYPAL_CLIENT_ID: "paypal_test",
  PAYPAL_ENVIRONMENT: "sandbox",
} as Env;

describe("provider authorization URLs", () => {
  it("builds a state-bound Stripe Connect URL", () => {
    const url = new URL(authorizationURL(env, "stripe", "state-value"));
    expect(url.origin).toBe("https://connect.stripe.com");
    expect(url.searchParams.get("client_id")).toBe("ca_test");
    expect(url.searchParams.get("state")).toBe("state-value");
    expect(url.searchParams.get("redirect_uri")).toBe(
      "https://api.salesping.example/v1/oauth/stripe/callback",
    );
  });

  it("uses PayPal sandbox until explicitly switched live", () => {
    const url = new URL(authorizationURL(env, "paypal", "state-value"));
    expect(url.hostname).toBe("www.sandbox.paypal.com");
    expect(url.pathname).toBe("/signin/authorize");
    expect(url.searchParams.get("scope")).toContain("openid");
    expect(url.searchParams.get("state")).toBe("state-value");
    expect(url.searchParams.get("redirect_uri")).toBe(
      "https://api.salesping.example/v1/oauth/paypal/callback",
    );
  });
});
