import { describe, expect, it } from "vitest";

import {
  authorizationURL,
  verifyStripeAppInstall,
} from "../src/providers";
import { stripeSignature } from "../src/stripe-webhooks";
import type { Env } from "../src/env";
import type { ProviderAuthorizationEnv } from "../src/providers";

const env = {
  PUBLIC_BASE_URL: "https://api.chaching.example",
  STRIPE_APP_INSTALL_URL: "https://marketplace.stripe.com/apps/install/link/chaching-test",
  PAYPAL_CLIENT_ID: "paypal_test",
  PAYPAL_ENVIRONMENT: "sandbox",
} satisfies ProviderAuthorizationEnv;

describe("provider authorization URLs", () => {
  it("builds a state-bound Stripe App install URL without write scope", () => {
    const url = new URL(authorizationURL(env, "stripe", "state-value"));
    expect(url.origin).toBe("https://marketplace.stripe.com");
    expect(url.pathname).toBe("/apps/install/link/chaching-test");
    expect(url.searchParams.get("state")).toBe("state-value");
    expect(url.searchParams.get("redirect_uri")).toBe(
      "https://api.chaching.example/v1/oauth/stripe/callback",
    );
    expect(url.searchParams.has("scope")).toBe(false);
  });

  it("uses PayPal sandbox until explicitly switched live", () => {
    const url = new URL(authorizationURL(env, "paypal", "state-value"));
    expect(url.hostname).toBe("www.sandbox.paypal.com");
    expect(url.pathname).toBe("/signin/authorize");
    expect(url.searchParams.get("scope")).toContain("openid");
    expect(url.searchParams.get("state")).toBe("state-value");
    expect(url.searchParams.get("redirect_uri")).toBe(
      "https://api.chaching.example/v1/oauth/paypal/callback",
    );
  });
});

describe("Stripe App install verification", () => {
  it("accepts a signed installation and stores only read permissions", async () => {
    const timestamp = 1_700_000_000;
    const install = {
      state: "state-value",
      stripeUserId: "usr_installer",
      accountId: "acct_connected",
      signature: "",
    };
    const payload = JSON.stringify({
      state: install.state,
      user_id: install.stripeUserId,
      account_id: install.accountId,
    });
    const signature = await stripeSignature(payload, timestamp, "app_secret_test");
    install.signature = `t=${timestamp},v1=${signature}`;

    const tokens = await verifyStripeAppInstall(
      { STRIPE_APP_SIGNING_SECRET: "app_secret_test" } as Env,
      install,
      timestamp,
    );

    expect(tokens).toEqual({
      providerAccountId: "acct_connected",
      accountLabel: "acct_connected",
      accessToken: null,
      refreshToken: null,
      expiresAt: null,
      scope: "event_read charge_read",
    });
  });

  it("rejects a forged installation callback", async () => {
    await expect(
      verifyStripeAppInstall(
        { STRIPE_APP_SIGNING_SECRET: "app_secret_test" } as Env,
        {
          state: "state-value",
          stripeUserId: "usr_installer",
          accountId: "acct_connected",
          signature: "t=1700000000,v1=forged",
        },
        1_700_000_000,
      ),
    ).rejects.toThrow("invalid app installation signature");
  });

  it("rejects an installation callback without a Stripe account ID", async () => {
    await expect(
      verifyStripeAppInstall(
        { STRIPE_APP_SIGNING_SECRET: "app_secret_test" } as Env,
        {
          state: "state-value",
          stripeUserId: "usr_installer",
          accountId: "not-an-account",
          signature: "t=1700000000,v1=irrelevant",
        },
        1_700_000_000,
      ),
    ).rejects.toThrow("invalid app installation callback");
  });

});
