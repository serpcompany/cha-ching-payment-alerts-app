import { describe, expect, it } from "vitest";

import {
  isSimulatorAuthEnabled,
  isSimulatorAuthRequestAllowed,
  missingCoreConfiguration,
  providerCapabilities,
} from "../src/env";
import type { Env } from "../src/env";

describe("provider capabilities", () => {
  it("reports availability only when each provider has all required credentials", () => {
    const env = {
      STRIPE_SECRET_KEY: "sk_live_test",
      STRIPE_APP_INSTALL_URL: "https://marketplace.stripe.com/apps/install/link/test",
      STRIPE_APP_SIGNING_SECRET: "whsec_test",
      PAYPAL_CLIENT_ID: "",
      PAYPAL_CLIENT_SECRET: "",
    } as unknown as Env;

    expect(providerCapabilities(env)).toEqual({ stripe: true, paypal: false });
  });

  it("accepts Stripe's external-test install links before Marketplace publication", () => {
    const env = {
      STRIPE_SECRET_KEY: "sk_live_test",
      STRIPE_APP_INSTALL_URL: "https://dashboard.stripe.com/apps/install/link/chnlink_test?redirect_uri=https%3A%2F%2Fexample.com",
      STRIPE_APP_SIGNING_SECRET: "app_secret",
      PAYPAL_CLIENT_ID: "",
      PAYPAL_CLIENT_SECRET: "",
    } as unknown as Env;

    expect(providerCapabilities(env).stripe).toBe(true);
  });

  it("rejects non-Stripe or insecure install URLs", () => {
    const base = {
      STRIPE_SECRET_KEY: "sk_live_test",
      STRIPE_APP_SIGNING_SECRET: "app_secret",
      PAYPAL_CLIENT_ID: "",
      PAYPAL_CLIENT_SECRET: "",
    };
    expect(providerCapabilities({
      ...base,
      STRIPE_APP_INSTALL_URL: "http://marketplace.stripe.com/apps/install/link/test",
    } as Env).stripe).toBe(false);
    expect(providerCapabilities({
      ...base,
      STRIPE_APP_INSTALL_URL: "https://example.com/apps/install/link/test",
    } as Env).stripe).toBe(false);
    expect(providerCapabilities({
      ...base,
      STRIPE_APP_INSTALL_URL: "https://dashboard.stripe.com/not-an-install-link",
    } as Env).stripe).toBe(false);
  });

  it("does not advertise Stripe when live account validation is unavailable", () => {
    expect(providerCapabilities({
      STRIPE_SECRET_KEY: "",
      STRIPE_APP_INSTALL_URL: "https://marketplace.stripe.com/apps/install/link/test",
      STRIPE_APP_SIGNING_SECRET: "app_secret",
      PAYPAL_CLIENT_ID: "",
      PAYPAL_CLIENT_SECRET: "",
    } as Env).stripe).toBe(false);
  });
});

describe("Simulator authentication boundary", () => {
  it("is available only in development", () => {
    expect(isSimulatorAuthEnabled({
      ENVIRONMENT: "development",
      PUBLIC_BASE_URL: "http://127.0.0.1:8787",
    })).toBe(true);
    expect(isSimulatorAuthEnabled({
      ENVIRONMENT: "staging",
      PUBLIC_BASE_URL: "https://preview.example.com",
    })).toBe(false);
    expect(isSimulatorAuthEnabled({
      ENVIRONMENT: "production",
      PUBLIC_BASE_URL: "https://api.example.com",
    })).toBe(false);
  });

  it("cannot activate on a remotely reachable Worker", () => {
    expect(isSimulatorAuthEnabled({
      ENVIRONMENT: "development",
      PUBLIC_BASE_URL: "https://cha-ching-api.serpcompany.workers.dev",
    })).toBe(false);
  });

  it("also requires the incoming request itself to use loopback", () => {
    const env = {
      ENVIRONMENT: "development" as const,
      PUBLIC_BASE_URL: "http://127.0.0.1:8787",
    };

    expect(isSimulatorAuthRequestAllowed(
      env,
      "http://127.0.0.1:8787/api/auth/sign-in/anonymous",
    )).toBe(true);
    expect(isSimulatorAuthRequestAllowed(
      env,
      "https://preview.example.com/api/auth/sign-in/anonymous",
    )).toBe(false);
  });

  it("does not require Apple credentials locally", () => {
    const env = {
      ENVIRONMENT: "development",
      PUBLIC_BASE_URL: "http://localhost:8787",
      BETTER_AUTH_SECRET: "local-only-secret",
      PROVIDER_TOKEN_ENCRYPTION_KEY: "local-only-key",
    } as unknown as Env;

    expect(missingCoreConfiguration(env)).toEqual([]);
  });

  it("still requires Apple credentials outside local development", () => {
    const env = {
      ENVIRONMENT: "production",
      PUBLIC_BASE_URL: "https://api.example.com",
      BETTER_AUTH_SECRET: "production-secret",
      PROVIDER_TOKEN_ENCRYPTION_KEY: "production-key",
    } as Env;

    expect(missingCoreConfiguration(env)).toEqual([
      "APPLE_TEAM_ID",
      "APPLE_KEY_ID",
      "APPLE_PRIVATE_KEY",
    ]);
  });
});
