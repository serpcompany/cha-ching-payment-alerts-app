import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { Auth } from "../src/auth";
import type { Env } from "../src/env";
import { appleSignedDataVerifier, handleAppleSubscriptionNotification, handleSubscriptionRequest, hasProductAccess } from "../src/subscriptions";
import type { AppleSignedDataVerifier } from "../src/subscriptions";

function authFor(userId: string): Auth {
  return {
    api: {
      getSession: async () => ({
        user: { id: userId, name: "Founder", email: "founder@example.test" },
        session: { id: `session-${userId}` },
      }),
    },
  } as unknown as Auth;
}

describe("subscription HTTP interface", () => {
  let miniflare: Miniflare;
  let env: Env;

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
      "0010_reconcile_custom_payment_history_presentation.sql",
      "0011_retain_custom_payment_field_values.sql",
      "0012_custom_source_health.sql",
      "0013_product_entitlements.sql",
    ]) {
      const statements = (await readFile(join(process.cwd(), "migrations", migration), "utf8"))
        .replace(/--.*$/gm, "")
        .split(";")
        .map((statement) => statement.trim())
        .filter((statement) => statement && !statement.startsWith("PRAGMA foreign_keys"));
      for (const statement of statements) await db.prepare(statement).run();
    }
    await db.prepare(
      "INSERT INTO user (id, name, email, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)",
    ).bind("user-one", "Founder", "founder@example.test", Date.now()).run();
    env = {
      DB: db,
      APPLE_APP_BUNDLE_ID: "com.serpcompany.chaching",
      APPLE_APP_ID: "6800029282",
      PRODUCT_ACCESS_ENFORCEMENT: "enabled",
    } as unknown as Env;
  });

  afterEach(async () => {
    await miniflare.dispose();
  });

  it("reports Subscription required with a stable Apple account token before purchase", async () => {
    const first = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/subscription"),
    );
    const firstBody = await first.json<{
      access: string;
      action: string;
      appAccountToken: string;
      productId: string;
    }>();
    const second = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/subscription"),
    );
    const secondBody = await second.json<typeof firstBody>();

    expect(first.status).toBe(200);
    expect(firstBody).toEqual({
      access: "subscription_required",
      action: "start_free_trial",
      appAccountToken: expect.stringMatching(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      ),
      productId: "com.serpcompany.chaching.annual",
    });
    expect(secondBody.appAccountToken).toBe(firstBody.appAccountToken);
  });

  it("rejects unsigned Xcode transaction data instead of bypassing Apple signature verification", async () => {
    const payload = Buffer.from(JSON.stringify({ environment: "Xcode" })).toString("base64url");
    const unsigned = `${Buffer.from("{}").toString("base64url")}.${payload}.unsigned`;

    await expect(appleSignedDataVerifier(env).verifyTransaction(unsigned)).rejects.toThrow(
      "Signed Apple data must come from Apple's Production or Sandbox environment",
    );
  });

  it("reconciles an Xcode transaction only through the loopback development path", async () => {
    env.ENVIRONMENT = "development";
    env.PUBLIC_BASE_URL = "http://127.0.0.1:8787";
    const status = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("http://127.0.0.1:8787/v1/subscription"),
    );
    const required = await status.json<{ appAccountToken: string }>();
    const signedTransaction = unsignedXcodeTransaction(required.appAccountToken);

    const sync = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("http://127.0.0.1:8787/v1/subscription/sync", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ signedTransaction }),
      }),
    );

    expect(sync.status).toBe(200);
    expect(await sync.json()).toMatchObject({
      access: "full_access",
      appAccountToken: required.appAccountToken,
    });
  });

  it.each([
    {
      name: "production environment",
      environment: "production" as const,
      publicBaseURL: "https://api.cha-ching.test",
      requestURL: "https://api.cha-ching.test/v1/subscription/sync",
    },
    {
      name: "non-loopback request",
      environment: "development" as const,
      publicBaseURL: "http://127.0.0.1:8787",
      requestURL: "https://api.cha-ching.test/v1/subscription/sync",
    },
  ])("rejects an Xcode transaction from the $name", async ({
    environment,
    publicBaseURL,
    requestURL,
  }) => {
    env.ENVIRONMENT = environment;
    env.PUBLIC_BASE_URL = publicBaseURL;

    await expect(handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request(requestURL, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ signedTransaction: unsignedXcodeTransaction(crypto.randomUUID()) }),
      }),
    )).rejects.toThrow("Signed Apple data must come from Apple's Production or Sandbox environment");
  });

  it("keeps existing users ungated while staged enforcement is disabled", async () => {
    env.PRODUCT_ACCESS_ENFORCEMENT = "disabled";
    expect(await hasProductAccess(env, "user-one")).toBe(true);
    env.PRODUCT_ACCESS_ENFORCEMENT = "enabled";
    expect(await hasProductAccess(env, "user-one")).toBe(false);
  });

  it("grants Full access only after the backend verifies a current Apple transaction", async () => {
    const status = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/subscription"),
    );
    const required = await status.json<{ appAccountToken: string }>();
    const verifier: AppleSignedDataVerifier = {
      verifyTransaction: async () => ({
        appAccountToken: required.appAccountToken,
        bundleId: "com.serpcompany.chaching",
        environment: "Sandbox",
        expiresDate: Date.now() + 7 * 24 * 60 * 60 * 1_000,
        originalTransactionId: "original-100",
        productId: "com.serpcompany.chaching.annual",
        revocationDate: null,
        signedDate: Date.now(),
        transactionId: "transaction-101",
      }),
      verifyNotification: async () => null,
    };

    const sync = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/subscription/sync", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ signedTransaction: "apple-jws" }),
      }),
      verifier,
    );

    expect(sync.status).toBe(200);
    expect(await sync.json()).toEqual({
      access: "full_access",
      action: null,
      appAccountToken: required.appAccountToken,
      productId: "com.serpcompany.chaching.annual",
    });
  });

  it("removes access when a verified Apple server notification reports revocation", async () => {
    const initial = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/subscription"),
    );
    const required = await initial.json<{ appAccountToken: string }>();
    const current = {
      appAccountToken: required.appAccountToken,
      bundleId: "com.serpcompany.chaching",
      environment: "Sandbox" as const,
      expiresDate: Date.now() + 7 * 24 * 60 * 60 * 1_000,
      originalTransactionId: "original-200",
      productId: "com.serpcompany.chaching.annual",
      revocationDate: null,
      signedDate: Date.now(),
      transactionId: "transaction-201",
    };
    const purchaseVerifier: AppleSignedDataVerifier = {
      verifyTransaction: async () => current,
      verifyNotification: async () => null,
    };
    await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/subscription/sync", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ signedTransaction: "purchase-jws" }),
      }),
      purchaseVerifier,
    );
    const revokedAt = Date.now();
    const notificationVerifier: AppleSignedDataVerifier = {
      verifyTransaction: async () => current,
      verifyNotification: async () => ({
        ...current,
        revocationDate: revokedAt,
        signedDate: current.signedDate + 1,
      }),
    };

    const notification = await handleAppleSubscriptionNotification(
      env,
      new Request("https://api.cha-ching.test/v1/webhooks/apple", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ signedPayload: "notification-jws" }),
      }),
      notificationVerifier,
    );
    const status = await handleSubscriptionRequest(
      env,
      authFor("user-one"),
      new Request("https://api.cha-ching.test/v1/subscription"),
    );

    expect(notification.status).toBe(204);
    expect(await status.json()).toEqual({
      access: "subscription_required",
      action: "subscribe_again",
      appAccountToken: required.appAccountToken,
      productId: "com.serpcompany.chaching.annual",
    });
  });
});

function unsignedXcodeTransaction(appAccountToken: string): string {
  const now = Date.now();
  const payload = Buffer.from(JSON.stringify({
    appAccountToken,
    bundleId: "com.serpcompany.chaching",
    environment: "Xcode",
    expiresDate: now + 7 * 24 * 60 * 60 * 1_000,
    originalTransactionId: "xcode-original-100",
    productId: "com.serpcompany.chaching.annual",
    signedDate: now,
    transactionId: "xcode-transaction-101",
  })).toString("base64url");
  return `${Buffer.from("{}").toString("base64url")}.${payload}.xcode-local-signature`;
}
