import { Buffer } from "node:buffer";

import type {
  Environment,
  JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";

import type { Auth } from "./auth";
import { requireUser } from "./auth";
import type { Env } from "./env";

export const ANNUAL_SUBSCRIPTION_PRODUCT_ID = "com.serpcompany.chaching.annual";

const APPLE_ROOT_CA_G3_DER_BASE64 = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

type SubscriptionAction = "start_free_trial" | "update_billing" | "subscribe_again";

interface ProductEntitlementRow {
  app_account_token: string;
  provider_product_id: string | null;
  access_expires_at: number | null;
  revoked_at: number | null;
  provider_event_signed_at?: number | null;
}

export interface VerifiedAppleTransaction {
  appAccountToken: string | null;
  bundleId: string;
  environment: "Production" | "Sandbox" | "Xcode";
  expiresDate: number | null;
  originalTransactionId: string;
  productId: string;
  revocationDate: number | null;
  signedDate: number;
  transactionId: string;
}

export interface AppleSignedDataVerifier {
  verifyTransaction(signedTransaction: string): Promise<VerifiedAppleTransaction>;
  verifyNotification(signedPayload: string): Promise<VerifiedAppleTransaction | null>;
}

type AppleEnvironment = "Production" | "Sandbox";

function decodedEnvironment(signedData: string): AppleEnvironment {
  const payload = signedData.split(".")[1];
  if (!payload) throw new Error("Signed Apple data is malformed");
  const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as {
    environment?: unknown;
    data?: { environment?: unknown };
  };
  const environment = decoded.environment ?? decoded.data?.environment;
  if (environment === "Production" || environment === "Sandbox") {
    return environment;
  }
  throw new Error("Signed Apple data must come from Apple's Production or Sandbox environment");
}

function verifiedTransaction(decoded: JWSTransactionDecodedPayload): VerifiedAppleTransaction {
  if (
    typeof decoded.bundleId !== "string"
    || typeof decoded.originalTransactionId !== "string"
    || typeof decoded.productId !== "string"
    || typeof decoded.signedDate !== "number"
    || typeof decoded.transactionId !== "string"
  ) {
    throw new Error("Verified Apple transaction is incomplete");
  }
  if (
    decoded.environment !== "Production"
    && decoded.environment !== "Sandbox"
    && decoded.environment !== "Xcode"
  ) {
    throw new Error("Verified Apple transaction has an unsupported environment");
  }
  return {
    appAccountToken: decoded.appAccountToken ?? null,
    bundleId: decoded.bundleId,
    environment: decoded.environment,
    expiresDate: decoded.expiresDate ?? null,
    originalTransactionId: decoded.originalTransactionId,
    productId: decoded.productId,
    revocationDate: decoded.revocationDate ?? null,
    signedDate: decoded.signedDate,
    transactionId: decoded.transactionId,
  };
}

export function appleSignedDataVerifier(env: Env): AppleSignedDataVerifier {
  const verifierFor = async (signedData: string) => {
    const environment = decodedEnvironment(signedData);
    const { SignedDataVerifier } = await import("@apple/app-store-server-library");
    return new SignedDataVerifier(
      [Buffer.from(APPLE_ROOT_CA_G3_DER_BASE64, "base64")],
      false,
      environment as Environment,
      env.APPLE_APP_BUNDLE_ID,
      environment === "Production" ? Number(env.APPLE_APP_ID) : undefined,
    );
  };
  const verifyTransaction = async (signedTransaction: string) => {
    const verifier = await verifierFor(signedTransaction);
    const decoded = await verifier
      .verifyAndDecodeTransaction(signedTransaction);
    return verifiedTransaction(decoded);
  };
  return {
    verifyTransaction,
    verifyNotification: async (signedPayload: string) => {
      const verifier = await verifierFor(signedPayload);
      const notification = await verifier
        .verifyAndDecodeNotification(signedPayload);
      const signedTransaction = notification.data?.signedTransactionInfo;
      return signedTransaction ? verifyTransaction(signedTransaction) : null;
    },
  };
}

export interface ProductAccess {
  access: "full_access" | "subscription_required";
  action: SubscriptionAction | null;
  appAccountToken: string;
  productId: string;
}

async function entitlementForUser(db: D1Database, userId: string): Promise<ProductEntitlementRow> {
  const token = crypto.randomUUID();
  await db.prepare(
    `INSERT INTO product_entitlements (user_id, app_account_token)
     VALUES (?1, ?2)
     ON CONFLICT(user_id) DO NOTHING`,
  ).bind(userId, token).run();
  const row = await db.prepare(
    `SELECT app_account_token, provider_product_id, access_expires_at, revoked_at
     FROM product_entitlements WHERE user_id = ?1`,
  ).bind(userId).first<ProductEntitlementRow>();
  if (!row) throw new Error("Product entitlement could not be materialized");
  return row;
}

async function reconcileTransaction(
  env: Env,
  userId: string,
  transaction: VerifiedAppleTransaction,
): Promise<void> {
  if (transaction.bundleId !== env.APPLE_APP_BUNDLE_ID) {
    throw new Response(JSON.stringify({ error: "Apple transaction is for a different app" }), {
      status: 422,
      headers: { "content-type": "application/json" },
    });
  }
  if (transaction.productId !== ANNUAL_SUBSCRIPTION_PRODUCT_ID) {
    throw new Response(JSON.stringify({ error: "Apple transaction is for an unsupported product" }), {
      status: 422,
      headers: { "content-type": "application/json" },
    });
  }
  const entitlement = await entitlementForUser(env.DB, userId);
  if (!transaction.appAccountToken || transaction.appAccountToken !== entitlement.app_account_token) {
    throw new Response(JSON.stringify({ error: "This purchase belongs to a different Cha-Ching account" }), {
      status: 409,
      headers: { "content-type": "application/json" },
    });
  }
  await env.DB.prepare(
    `UPDATE product_entitlements SET
       provider_product_id = ?1,
       provider_original_transaction_id = ?2,
       provider_transaction_id = ?3,
       access_expires_at = ?4,
       revoked_at = ?5,
       provider_event_signed_at = ?6,
       verified_at = ?7,
       updated_at = CURRENT_TIMESTAMP
     WHERE user_id = ?8
       AND (provider_event_signed_at IS NULL OR provider_event_signed_at <= ?6)`,
  ).bind(
    transaction.productId,
    transaction.originalTransactionId,
    transaction.transactionId,
    transaction.expiresDate,
    transaction.revocationDate,
    transaction.signedDate,
    Date.now(),
    userId,
  ).run();
}

export async function getProductAccess(
  db: D1Database,
  userId: string,
  now = Date.now(),
): Promise<ProductAccess> {
  const row = await entitlementForUser(db, userId);
  const isActive = row.revoked_at === null
    && row.access_expires_at !== null
    && row.access_expires_at > now;
  const action: SubscriptionAction | null = isActive
    ? null
    : row.provider_product_id === null
      ? "start_free_trial"
      : "subscribe_again";
  return {
    access: isActive ? "full_access" : "subscription_required",
    action,
    appAccountToken: row.app_account_token,
    productId: ANNUAL_SUBSCRIPTION_PRODUCT_ID,
  };
}

export async function hasProductAccess(
  env: Env,
  userId: string,
  now = Date.now(),
): Promise<boolean> {
  if (env.PRODUCT_ACCESS_ENFORCEMENT !== "enabled") return true;
  const row = await env.DB.prepare(
    `SELECT 1 AS active FROM product_entitlements
     WHERE user_id = ?1 AND revoked_at IS NULL AND access_expires_at > ?2`,
  ).bind(userId, now).first<{ active: number }>();
  return row?.active === 1;
}

export async function requireProductAccess(env: Env, userId: string): Promise<void> {
  if (env.PRODUCT_ACCESS_ENFORCEMENT !== "enabled") return;
  const access = await getProductAccess(env.DB, userId);
  if (access.access === "full_access") return;
  throw new Response(JSON.stringify({ error: "Subscription required", action: access.action }), {
    status: 403,
    headers: { "content-type": "application/json" },
  });
}

export async function handleSubscriptionRequest(
  env: Env,
  auth: Auth,
  request: Request,
  verifier?: AppleSignedDataVerifier,
): Promise<Response> {
  const url = new URL(request.url);
  const user = await requireUser(auth, request);
  if (request.method === "GET" && url.pathname === "/v1/subscription") {
    return Response.json(await getProductAccess(env.DB, user.id));
  }
  if (request.method === "POST" && url.pathname === "/v1/subscription/sync") {
    const signedDataVerifier = verifier ?? appleSignedDataVerifier(env);
    const body = await request.json<{ signedTransaction?: unknown }>();
    if (typeof body.signedTransaction !== "string" || body.signedTransaction.length > 32_000) {
      return Response.json({ error: "A signed Apple transaction is required" }, { status: 400 });
    }
    const transaction = await signedDataVerifier.verifyTransaction(body.signedTransaction);
    await reconcileTransaction(env, user.id, transaction);
    return Response.json(await getProductAccess(env.DB, user.id));
  }
  return Response.json({ error: "Not found" }, { status: 404 });
}

export async function handleAppleSubscriptionNotification(
  env: Env,
  request: Request,
  verifier: AppleSignedDataVerifier = appleSignedDataVerifier(env),
): Promise<Response> {
  if (request.method !== "POST") return Response.json({ error: "Not found" }, { status: 404 });
  const body = await request.json<{ signedPayload?: unknown }>();
  if (typeof body.signedPayload !== "string" || body.signedPayload.length > 64_000) {
    return Response.json({ error: "A signed Apple notification is required" }, { status: 400 });
  }
  const transaction = await verifier.verifyNotification(body.signedPayload);
  if (!transaction?.appAccountToken) return new Response(null, { status: 204 });
  const entitlement = await env.DB.prepare(
    "SELECT user_id FROM product_entitlements WHERE app_account_token = ?1",
  ).bind(transaction.appAccountToken).first<{ user_id: string }>();
  if (!entitlement) return new Response(null, { status: 204 });
  await reconcileTransaction(env, entitlement.user_id, transaction);
  return new Response(null, { status: 204 });
}
