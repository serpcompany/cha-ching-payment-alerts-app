import { afterEach, describe, expect, it, vi } from "vitest";

import { completeConnection } from "../src/connections";
import { stripeSignature } from "../src/stripe-webhooks";
import type { Env } from "../src/env";

class ConnectionCallbackDatabase {
  connectedAccountId: string | null = null;

  prepare(sql: string) {
    const database = this;
    let values: unknown[] = [];
    return {
      bind(...bound: unknown[]) {
        values = bound;
        return this;
      },
      async first() {
        if (sql.includes("DELETE FROM oauth_states")) return { user_id: "user_live" };
        return null;
      },
      async all() {
        if (sql.includes("SELECT feature_key, enabled FROM entitlements")) {
          return {
            results: [
              { feature_key: "connect_paypal", enabled: 1 },
              { feature_key: "connect_stripe", enabled: 1 },
            ],
          };
        }
        return { results: [] };
      },
      async run() {
        if (sql.includes("INSERT INTO provider_connections")) {
          database.connectedAccountId = String(values[3]);
        }
        return { meta: { changes: 1 } };
      },
    };
  }

  async batch(statements: unknown[]) {
    return statements.map(() => ({ success: true }));
  }
}

function callbackEnv(database: ConnectionCallbackDatabase): Env {
  return {
    DB: database,
    NOTIFICATION_QUEUE: { send: vi.fn() },
    ENVIRONMENT: "production",
    PUBLIC_BASE_URL: "https://cha-ching.example",
    BETTER_AUTH_SECRET: "better-auth-test-secret",
    PROVIDER_TOKEN_ENCRYPTION_KEY: "provider-token-test-key",
    APPLE_TEAM_ID: "APPLE_TEAM",
    APPLE_KEY_ID: "APPLE_KEY",
    APPLE_PRIVATE_KEY: "not-used-by-this-route",
    APPLE_SERVICE_ID: "com.example.chaching.signin",
    APPLE_APP_BUNDLE_ID: "com.example.chaching",
    APNS_KEY_ID: "",
    APNS_PRIVATE_KEY: "",
    APNS_BUNDLE_ID: "com.example.chaching",
    STRIPE_APP_INSTALL_URL: "https://dashboard.stripe.com/apps/install/link/test",
    STRIPE_APP_SIGNING_SECRET: "whsec_app_signing",
    STRIPE_WEBHOOK_SECRET: "whsec_webhook",
    STRIPE_SECRET_KEY: "sk_live_platform",
    PAYPAL_CLIENT_ID: "",
    PAYPAL_CLIENT_SECRET: "",
    PAYPAL_ENVIRONMENT: "sandbox",
  } as unknown as Env;
}

async function signedCallback(accountId: string): Promise<Request> {
  const state = "state-from-the-ios-connection-flow";
  const timestamp = Math.floor(Date.now() / 1_000);
  const payload = JSON.stringify({
    state,
    user_id: "usr_stripe",
    account_id: accountId,
  });
  const signature = await stripeSignature(payload, timestamp, "whsec_app_signing");
  const url = new URL("https://cha-ching.example/v1/oauth/stripe/callback");
  url.searchParams.set("state", state);
  url.searchParams.set("user_id", "usr_stripe");
  url.searchParams.set("account_id", accountId);
  url.searchParams.set("install_signature", `t=${timestamp},v1=${signature}`);
  return new Request(url);
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("Stripe connection callback", () => {
  it("rejects a sandbox Stripe account in production", async () => {
    const database = new ConnectionCallbackDatabase();
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({
      error: {
        code: "account_invalid",
        message: "This account can only be used with test mode keys.",
      },
    }, { status: 403 })));

    const response = await completeConnection(
      callbackEnv(database),
      await signedCallback("acct_sandbox"),
      "stripe",
    );

    expect(response.headers.get("location")).toBe(
      "chaching://oauth-callback?provider=stripe&status=error&message=Couldn%27t+connect+stripe",
    );
  });
});
